import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/openclaw_command.dart';

/// Possible connection states.
enum NodeConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Callback for invoke commands from the Gateway.
typedef InvokeCallback = Future<Map<String, dynamic>> Function(
    String command, Map<String, dynamic> args);

/// Bi-directional WebSocket node connection to the OpenClaw Gateway.
class OpenClawNodeService {
  final SharedPreferences _prefs;
  final InvokeCallback onInvoke;

  WebSocketChannel? _channel;
  Timer? _tickTimer;
  Timer? _reconnectTimer;
  bool _active = false;
  int _requestIdCounter = 0;
  String? _connectNonce;
  int _reconnectAttempts = 0;
  bool _debug = true;

  final ValueNotifier<NodeConnectionState> stateNotifier =
      ValueNotifier(NodeConnectionState.disconnected);
  final ValueNotifier<String> statusNotifier = ValueNotifier('Disconnected');

  OpenClawNodeService({
    required SharedPreferences prefs,
    required this.onInvoke,
  }) : _prefs = prefs;

  // ── Device Identity ──────────────────────────────────────────────

  String get deviceId {
    final id = _prefs.getString('device_id');
    if (id != null) return id;
    final newId = 'phone-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}';
    _prefs.setString('device_id', newId);
    return newId;
  }

  String get shortDeviceId =>
      deviceId.length > 10 ? deviceId.substring(0, 10) : deviceId;

  String get _deviceSecret {
    var secret = _prefs.getString('device_secret');
    if (secret == null) {
      final bytes = List<int>.generate(32, (_) => Random().nextInt(256));
      secret = base64Encode(bytes);
      _prefs.setString('device_secret', secret);
    }
    return secret;
  }

  String get _devicePublicId {
    // Derive a stable public identifier from the secret
    final hash = sha256.convert(utf8.encode(_deviceSecret));
    return hash.toString().substring(0, 16);
  }

  String? get deviceToken => _prefs.getString('device_token');
  Future<void> setDeviceToken(String? token) async {
    if (token == null) {
      await _prefs.remove('device_token');
    } else {
      await _prefs.setString('device_token', token);
    }
  }

  bool get isConnected => _channel != null && _active;

  // ── Lifecycle ─────────────────────────────────────────────────────

  Future<void> start() async {
    _active = true;
    _connect();
  }

  Future<void> stop() async {
    _active = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    await _channel?.sink.close(1000, 'Client shutdown');
    _channel = null;
    _updateState(NodeConnectionState.disconnected, 'Disconnected');
  }

  // ── Connection ────────────────────────────────────────────────────

  void _connect() {
    if (!_active) return;
    _updateState(NodeConnectionState.connecting, 'Connecting...');

    try {
      final uri = _buildWsUri();
      log('🔌 Connecting to $uri');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Timeout fallback for older Gateways
      Future.delayed(const Duration(seconds: 8), () {
        if (_connectNonce == null && _active) {
          log('⚠️ No connect.challenge received, sending connect directly');
          _sendConnectFrame();
        }
      });
    } catch (e) {
      log('❌ Connect error: $e');
      _scheduleReconnect();
    }
  }

  Uri _buildWsUri() {
    final scheme = AppConfig.useTls ? 'wss' : 'ws';
    return Uri.parse('$scheme://${AppConfig.gatewayHost}:${AppConfig.gatewayPort}${AppConfig.gatewayPath}');
  }

  // ── Message Handler ────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      final json = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : Map<String, dynamic>.from(raw as Map);
      final frame = WsFrame.fromJson(json);

      if (_debug) log('📩 <- ${jsonEncode(json)}');

      if (frame.isConnectChallenge) {
        _connectNonce = frame.payload?['nonce'] as String?;
        log('🔐 Challenge received, signing...');
        _sendConnectFrame();
        return;
      }

      if (frame.isHelloOk) {
        _onHelloOk(frame);
        return;
      }

      if (frame.isTick) return; // keepalive, ignore

      if (frame.isShutdown) {
        log('⚠️ Gateway shutdown');
        _updateState(NodeConnectionState.disconnected, 'Gateway shutdown');
        _scheduleReconnect();
        return;
      }

      if (frame.isInvokeRequest) {
        _handleInvoke(frame.payload ?? {});
        return;
      }

      if (frame.type == WsFrame.res && frame.id != null) {
        log('📡 RPC response: ${frame.id} ok=${frame.ok}');
        return;
      }

      if (frame.type == WsFrame.event) {
        log('📡 Event: ${frame.eventName}');
      }
    } catch (e) {
      log('⚠️ Parse error: $e');
    }
  }

  // ── Connect Frame ─────────────────────────────────────────────────

  void _sendConnectFrame() {
    // HMAC-SHA256 signature over nonce + deviceId
    final nonce = _connectNonce ?? '';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final payloadToSign = '${deviceId}:$nonce:$ts';
    final hmac = Hmac(sha256, utf8.encode(_deviceSecret));
    final signature = base64Encode(hmac.convert(utf8.encode(payloadToSign)).bytes);

    final connectParams = {
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': {
        'id': 'flutter-phone-bridge',
        'version': AppConfig.appVersion,
        'platform': 'android',
        'mode': 'node',
      },
      'role': 'node',
      'scopes': <String>[],
      'caps': AppConfig.nodeCaps,
      'commands': AppConfig.nodeCommands,
      'permissions': {
        'alarm.manage': true,
        'calendar.manage': true,
        'notification.send': true,
      },
      'auth': {
        if (AppConfig.gatewayToken.isNotEmpty)
          'token': AppConfig.gatewayToken,
        if (deviceToken != null) 'token': deviceToken,
      },
      'locale': 'en-US',
      'userAgent': 'openclaw-flutter-phone-bridge/${AppConfig.appVersion}',
      'device': {
        'id': deviceId,
        'publicKey': _devicePublicId,
        'signature': signature,
        'signedAt': ts,
        'nonce': nonce,
      },
    };

    _sendFrame(
      type: WsFrame.req,
      id: _nextRequestId(),
      method: 'connect',
      params: connectParams,
    );
  }

  // ── Hello OK Handler ──────────────────────────────────────────────

  void _onHelloOk(WsFrame frame) {
    final payload = frame.payload ?? {};
    final auth = payload['auth'] as Map<String, dynamic>?;
    final token = auth?['deviceToken'] as String?;
    if (token != null && token.isNotEmpty) {
      setDeviceToken(token);
      log('🔑 Stored device token');
    }

    final policy = payload['policy'] as Map<String, dynamic>?;
    final tickMs = policy?['tickIntervalMs'] as int? ?? 15000;

    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(Duration(milliseconds: tickMs * 3), (_) {
      if (!_active) return;
      log('⚠️ Tick timeout — reconnecting');
      _scheduleReconnect();
    });

    _reconnectAttempts = 0;
    _updateState(NodeConnectionState.connected, 'Connected ✓');
    log('✅ Connected to OpenClaw Gateway!');
  }

  // ── Invoke Handler ────────────────────────────────────────────────

  Future<void> _handleInvoke(Map<String, dynamic> payload) async {
    final invokeId = payload['invokeId'] as String? ?? '';
    final command = payload['command'] as String? ?? '';
    final args = (payload['args'] as Map<String, dynamic>?) ?? {};

    log('⚡ Invoke: $command');
    try {
      final result = await onInvoke(command, args);
      _sendNodeEvent('node.invoke.result', {
        'invokeId': invokeId,
        'ok': true,
        'data': result,
      });
    } catch (e) {
      log('❌ Invoke error: $e');
      _sendNodeEvent('node.invoke.result', {
        'invokeId': invokeId,
        'ok': false,
        'error': e.toString(),
      });
    }
  }

  // ── Send Events ───────────────────────────────────────────────────

  void sendNodeEvent(String eventName, Map<String, dynamic> payload) {
    _sendNodeEvent(eventName, payload);
  }

  void _sendNodeEvent(String eventName, Map<String, dynamic> payload) {
    if (!isConnected) return;
    _sendFrame(
      type: WsFrame.req,
      id: _nextRequestId(),
      method: 'node.event',
      params: {
        'event': eventName,
        'payloadJSON': jsonEncode(payload),
      },
    );
  }

  void _sendFrame({
    required String type,
    String? id,
    String? method,
    Map<String, dynamic>? params,
  }) {
    if (_channel == null) return;
    final msg = <String, dynamic>{
      'type': type,
      if (id != null) 'id': id,
      if (method != null) 'method': method,
      if (params != null) 'params': params,
    };
    final raw = jsonEncode(msg);
    if (_debug) log('📤 -> $raw');
    _channel!.sink.add(raw);
  }

  // ── Error Handling & Reconnect ────────────────────────────────────

  void _onError(dynamic error) {
    log('❌ WS error: $error');
    _tickTimer?.cancel();
    _channel = null;
    _updateState(NodeConnectionState.error, 'Error');
    _scheduleReconnect();
  }

  void _onDone() {
    log('🔌 WS closed');
    _tickTimer?.cancel();
    _channel = null;
    _updateState(NodeConnectionState.disconnected, 'Disconnected');
    if (_active) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_active) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = (AppConfig.reconnectBaseMs *
            pow(2, min(_reconnectAttempts - 1, 6)).toInt())
        .clamp(AppConfig.reconnectBaseMs, AppConfig.reconnectMaxMs);
    _updateState(NodeConnectionState.reconnecting, 'Reconnecting in ${delay ~/ 1000}s');
    log('🔄 Reconnect in ${delay}ms');
    _reconnectTimer = Timer(Duration(milliseconds: delay + Random().nextInt(2000)), () {
      _channel = null;
      _connectNonce = null;
      _connect();
    });
  }

  void _updateState(NodeConnectionState state, String status) {
    stateNotifier.value = state;
    statusNotifier.value = status;
  }

  String _nextRequestId() {
    _requestIdCounter++;
    return 'fb-${DateTime.now().millisecondsSinceEpoch}-$_requestIdCounter';
  }

  void log(String msg) {
    if (_debug) debugPrint('🔷 $msg');
  }

  void setDebug(bool enabled) => _debug = enabled;

  void dispose() {
    _active = false;
    _reconnectTimer?.cancel();
    _tickTimer?.cancel();
    _channel?.sink.close();
    stateNotifier.dispose();
    statusNotifier.dispose();
  }
}
