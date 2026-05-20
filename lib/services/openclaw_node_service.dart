import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config.dart';
import '../models/openclaw_command.dart';
import 'storage_service.dart';

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
  final StorageService _storage;
  final InvokeCallback onInvoke;

  WebSocketChannel? _channel;
  Timer? _tickTimer;
  Timer? _reconnectTimer;
  Timer? _fallbackTimer;
  StreamSubscription<dynamic>? _subscription;
  bool _active = false;
  int _requestIdCounter = 0;
  String? _connectNonce;
  bool _sentConnect = false;
  int _lastTickMs = 0;
  bool _debug = true;

  final ValueNotifier<NodeConnectionState> stateNotifier =
      ValueNotifier(NodeConnectionState.disconnected);
  final ValueNotifier<String> statusNotifier = ValueNotifier('Disconnected');

  final Map<String, Completer<Map<String, dynamic>>> _pendingRpcs = {};

  OpenClawNodeService({
    required StorageService storage,
    required this.onInvoke,
  }) : _storage = storage;

  String _deviceId = '';
  String get deviceId => _deviceId;
  String get shortDeviceId => deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId;

  bool get isConnected => _channel != null && _active;

  Future<void> start() async {
    await _ensureKeypair();
    _active = true;
    _connect();
  }

  Future<void> stop() async {
    _active = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'Client shutdown');
    _channel = null;
    // Clean up pending RPCs so they don't hang forever
    for (final completer in _pendingRpcs.values) {
      completer.completeError(Exception('Connection closed'));
    }
    _pendingRpcs.clear();
    _updateState(NodeConnectionState.disconnected, 'Disconnected');
  }

  // ── Key Management ────────────────────────────────────────────────

  Future<void> _ensureKeypair() async {
    if (_storage.rawIdentityKeyHex.isNotEmpty) {
      // Recompute deviceId on every start (critical after app restart)
      _deviceId = _sha256Hex(_storage.rawPublicKeyHex);
      return;
    }
    final kp = ed.generateKey();
    await _storage.storeKeypair(
      bytesToHex(kp.privateKey.bytes.toList()),
      bytesToHex(kp.publicKey.bytes.toList()),
    );
    // Compute deviceId = SHA-256(raw public key bytes), same as gateway
    _deviceId = _sha256Hex(_storage.rawPublicKeyHex);
    log('🔑 Generated new Ed25519 device keypair, deviceId=${_deviceId.substring(0, 8)}...');
  }

  ed.PrivateKey? get _privateKey {
    try {
      return ed.PrivateKey(Uint8List.fromList(hexToBytes(_storage.rawIdentityKeyHex)));
    } catch (_) {
      return null;
    }
  }

  // ── Connection ────────────────────────────────────────────────────

  void _connect() async {
    if (!_active) return;
    _updateState(NodeConnectionState.connecting, 'Connecting...');

    // Load the gateway token from user's settings before connecting
    await _loadGatewayToken();

    try {
      final uri = await _buildWsUri();
      _channel = WebSocketChannel.connect(uri);

      // Cancel old subscription before creating new one
      _subscription?.cancel();
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // If no connect.challenge in 10s (or missed it), send connect directly
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(const Duration(seconds: 10), () {
        if (!_sentConnect && _active) {
          log('⚠️ No connect.challenge received, sending connect directly');
          _sendConnect();
        }
      });
    } catch (e) {
      log('❌ Connect error: $e');
      _scheduleReconnect();
    }
  }

  Future<Uri> _buildWsUri() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('gateway_host') ?? AppConfig.gatewayHost;
    final port = prefs.getInt('gateway_port') ?? AppConfig.gatewayPort;
    final path = prefs.getString('gateway_path') ?? AppConfig.gatewayPath;
    final useTls = prefs.getBool('gateway_tls') ?? AppConfig.useTls;
    final scheme = useTls ? 'wss' : 'ws';
    final uri = Uri.parse('$scheme://$host:$port$path');
    log('🔗 Connecting to $uri');
    return uri;
  }

  // ── Message Handler ────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      final json = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : (raw as Map<String, dynamic>);
      final frame = WsFrame.fromJson(json);

      if (_debug) log('📩  <- ${jsonToString(json)}');

      if (frame.isConnectChallenge) {
        if (_sentConnect) return;
        _connectNonce = frame.payload?['nonce'] as String?;
        log('🔐 Received connect.challenge (nonce: ${_connectNonce?.substring(0, 8)}...)');
        _sendConnect();
        return;
      }

      if (frame.isHelloOk) {
        _onHelloOk(frame);
        return;
      }

      if (frame.isTick) {
        _lastTickMs = DateTime.now().millisecondsSinceEpoch;
        return;
      }

      if (frame.isShutdown) {
        log('⚠️ Gateway shutting down');
        _updateState(NodeConnectionState.disconnected, 'Gateway shutdown');
        _scheduleReconnect();
        return;
      }

      if (frame.isInvokeRequest) {
        _handleInvoke(frame.payload ?? {});
        return;
      }

      if (frame.type == WsFrame.res && frame.id != null) {
        final completer = _pendingRpcs.remove(frame.id);
        if (completer != null) {
          if (frame.ok == true) {
            completer.complete(frame.payload ?? {});
          } else {
            completer.completeError(
              Exception(frame.error ?? 'RPC failed: ${frame.id}'),
            );
          }
        }
        return;
      }

      if (frame.type == WsFrame.event) {
        log('📡 Event: ${frame.eventName}');
      }
    } catch (e) {
      log('⚠️ Parse error: $e');
    }
  }

  void _sendConnect() {
    if (_sentConnect) return;
    _sentConnect = true;
    _sendFrame(
      type: WsFrame.req,
      id: _nextRequestId(),
      method: 'connect',
      params: _createSignedConnectPayload(),
    );
  }

  String _gatewayToken = '';

  /// Load the gateway token from SharedPreferences (user settings).
  /// Must be called before connecting (called from _connect).
  Future<void> _loadGatewayToken() async {
    final prefs = await SharedPreferences.getInstance();
    _gatewayToken = prefs.getString('gateway_token') ?? '';
  }

  Map<String, dynamic> _createSignedConnectPayload() {
    final pk = _privateKey;
    final nonce = _connectNonce ?? '';
    final ts = DateTime.now().millisecondsSinceEpoch;

    // Gateway expects pipe-separated payload for signature verification:
    // v3|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce|platform|deviceFamily
    final authToken = _gatewayToken.isNotEmpty
        ? _gatewayToken
        : _storage.deviceToken ?? '';
    final scopes = <String>[];
    final signaturePayloadV3 = [
      'v3',
      _deviceId,
      'openclaw-android',
      'node',
      'node',
      scopes.join(','),
      ts.toString(),
      authToken,
      nonce,
      'android',       // platform
      '',               // deviceFamily
    ].join('|');

    final sig = pk != null
        ? bytesToBase64Url(ed.sign(pk, Uint8List.fromList(utf8.encode(signaturePayloadV3))).toList())
        : '';

    return {
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': {
        'id': 'openclaw-android',
        'version': AppConfig.appVersion,
        'platform': 'android',
        'mode': 'node',
      },
      'role': 'node',
      'scopes': scopes,
      'caps': AppConfig.nodeCaps,
      'commands': AppConfig.nodeCommands,
      'permissions': {
        'alarm.manage': true,
        'calendar.manage': true,
        'notification.send': true,
      },
      'auth': {
        if (authToken.isNotEmpty) 'token': authToken,
      },
      'locale': 'en-US',
      'userAgent': 'openclaw-flutter-phone-bridge/${AppConfig.appVersion}',
      'device': {
        'id': _deviceId,
        'publicKey': bytesToBase64Url(hexToBytes(_storage.rawPublicKeyHex)),
        'signature': sig,
        'signedAt': ts,
        'nonce': nonce,
      },
    };
  }

  void _onHelloOk(WsFrame frame) {
    final payload = frame.payload ?? {};
    final auth = payload['auth'] as Map<String, dynamic>?;
    final deviceToken = auth?['deviceToken'] as String?;

    if (deviceToken != null && deviceToken.isNotEmpty) {
      _storage.setDeviceToken(deviceToken);
      log('🔑 Stored device token');
    }

    final policy = payload['policy'] as Map<String, dynamic>?;
    final tickIntervalMs = policy?['tickIntervalMs'] as int? ?? 15000;

    // Track last tick timestamp, only reconnect if ticks actually stop
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(Duration(milliseconds: tickIntervalMs * 3), (_) {
      if (!_active) return;
      final elapsed = DateTime.now().millisecondsSinceEpoch - _lastTickMs;
      if (elapsed > tickIntervalMs * 3) {
        log('⚠️ Tick timeout — reconnecting (no tick for ${elapsed}ms)');
        _scheduleReconnect();
      }
    });

    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    final serverVersion = (payload['server'] as Map<String, dynamic>?)?
            ['version'] as String? ?? 'unknown';
    log('✅ Connected! Server v$serverVersion');

    _updateState(NodeConnectionState.connected, 'Connected to OpenClaw');
  }

  Future<void> _handleInvoke(Map<String, dynamic> payload) async {
    final invokeId = payload['invokeId'] as String? ?? '';
    final command = payload['command'] as String? ?? '';
    final args = (payload['args'] as Map<String, dynamic>?) ?? {};

    log('⚡ Invoke: $command $args');

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

  void sendNodeEvent(String eventName, Map<String, dynamic> payload) {
    _sendNodeEvent(eventName, payload);
  }

  void _sendNodeEvent(String eventName, Map<String, dynamic> payload) {
    if (!isConnected) return;
    _sendFrame(type: WsFrame.req, id: _nextRequestId(), method: 'node.event', params: {
      'event': eventName,
      'payload': payload,
    });
  }

  void _sendFrame({
    required String type,
    String? id,
    String? method,
    Map<String, dynamic>? params,
    String? event,
    Map<String, dynamic>? payload,
  }) {
    if (_channel == null) return;
    final msg = <String, dynamic>{
      'type': type,
      if (id != null) 'id': id,
      if (method != null) 'method': method,
      if (params != null) 'params': params,
      if (event != null) 'event': event,
      if (payload != null) 'payload': payload,
    };
    final raw = jsonEncode(msg);
    if (_debug) log('📤 -> ${jsonToString(msg)}');
    _channel!.sink.add(raw);
  }

  void _onError(dynamic error) {
    log('❌ WebSocket error: $error');
    _updateState(NodeConnectionState.error, 'Error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    log('🔌 WebSocket closed');
    _tickTimer?.cancel();
    _updateState(NodeConnectionState.disconnected, 'Disconnected');
    if (_active) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_active) return;
    _reconnectTimer?.cancel();
    final delay = _computeBackoff();
    _updateState(
      NodeConnectionState.reconnecting,
      'Reconnecting in ${delay ~/ 1000}s...',
    );
    log('🔄 Reconnecting in ${delay ~/ 1000}s');
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      _subscription?.cancel();
      _subscription = null;
      _channel = null;
      _connectNonce = null;
      _sentConnect = false;
      _connect();
    });
  }

  int _reconnectAttempts = 0;

  int _computeBackoff() {
    _reconnectAttempts++;
    final delay = min(
      AppConfig.reconnectBaseMs * pow(2, _reconnectAttempts - 1).toInt(),
      AppConfig.reconnectMaxMs,
    );
    return delay + (Random().nextInt(delay ~/ 2) - delay ~/ 4);
  }

  void resetReconnectBackoff() {
    _reconnectAttempts = 0;
  }

  void _updateState(NodeConnectionState state, String status) {
    stateNotifier.value = state;
    statusNotifier.value = status;
  }

  String _nextRequestId() {
    _requestIdCounter++;
    return 'flutter-${DateTime.now().millisecondsSinceEpoch}-$_requestIdCounter';
  }

  String bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String bytesToBase64Url(List<int> bytes) {
    final b64 = base64Encode(bytes);
    return b64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }

  List<int> hexToBytes(String hex) {
    final buf = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      buf.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return buf;
  }

  String _sha256Hex(String hexKey) {
    final bytes = hexToBytes(hexKey);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  String jsonToString(Map<String, dynamic> json) {
    final truncated = json.map((k, v) {
      if (v is String && v.length > 80) return MapEntry(k, '${v.substring(0, 80)}...');
      return MapEntry(k, v);
    });
    return jsonEncode(truncated);
  }

  void log(String msg) {
    if (_debug) debugPrint('🔷 [OCNode] $msg');
  }

  void setDebug(bool enabled) => _debug = enabled;

  void dispose() {
    _active = false;
    _reconnectTimer?.cancel();
    _fallbackTimer?.cancel();
    _tickTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    for (final completer in _pendingRpcs.values) {
      completer.completeError(Exception('Service disposed'));
    }
    _pendingRpcs.clear();
    stateNotifier.dispose();
    statusNotifier.dispose();
  }
}
