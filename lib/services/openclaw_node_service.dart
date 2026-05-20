import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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

/// Simple WebSocket relay client — no OpenClaw node protocol.
/// Connects to the relay server, authenticates with a token,
/// and handles invoke commands.
class OpenClawNodeService {
  final StorageService _storage;
  final InvokeCallback onInvoke;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _active = false;
  String? _clientId;
  bool _authenticated = false;
  bool _debug = true;
  int _reconnectAttempts = 0;

  final ValueNotifier<NodeConnectionState> stateNotifier =
      ValueNotifier(NodeConnectionState.disconnected);
  final ValueNotifier<String> statusNotifier = ValueNotifier('Disconnected');

  OpenClawNodeService({
    required StorageService storage,
    required this.onInvoke,
  }) : _storage = storage;

  String get deviceId => _clientId ?? 'unknown';
  String get shortDeviceId => deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId;
  bool get isConnected => _channel != null && _authenticated;

  Future<void> start() async {
    _active = true;
    _reconnectAttempts = 0;
    _connect();
  }

  Future<void> stop() async {
    _active = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'Client shutdown');
    _channel = null;
    _authenticated = false;
    _updateState(NodeConnectionState.disconnected, 'Disconnected');
  }

  void _connect() async {
    if (!_active) return;
    _updateState(NodeConnectionState.connecting, 'Connecting...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('gateway_host') ?? AppConfig.gatewayHost;
      final port = prefs.getInt('gateway_port') ?? AppConfig.gatewayPort;
      final useTls = prefs.getBool('gateway_tls') ?? AppConfig.useTls;
      final token = prefs.getString('gateway_token') ?? '';

      // Use /relay/ path instead of /gateway/
      final scheme = useTls ? 'wss' : 'ws';
      final uri = Uri.parse('$scheme://$host:$port/relay/');
      log('🔗 Connecting to $uri');

      _channel = WebSocketChannel.connect(uri);

      _subscription?.cancel();
      _subscription = _channel!.stream.listen(
        (data) => _onMessage(data),
        onError: (err) {
          log('❌ WebSocket error: $err');
          _scheduleReconnect();
        },
        onDone: () {
          log('🔌 Connection closed');
          _authenticated = false;
          _updateState(NodeConnectionState.disconnected, 'Disconnected');
          if (_active) _scheduleReconnect();
        },
      );

      // Send auth after connection
      await Future.delayed(const Duration(milliseconds: 500));
      _send({
        'type': 'auth',
        'token': token,
        'role': 'phone',
        'name': AppConfig.deviceDisplayName,
      });
    } catch (e) {
      log('❌ Connect error: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : (raw as Map<String, dynamic>);

      if (_debug) log('📩 <- ${jsonToString(msg)}');

      if (!_authenticated) {
        if (msg['type'] == 'auth.ok') {
          _authenticated = true;
          _clientId = msg['clientId'] as String?;
          _reconnectAttempts = 0;
          log('✅ Authenticated! Client ID: $_clientId');
          _updateState(NodeConnectionState.connected, 'Connected to Relay');
          return;
        }
        if (msg['type'] == 'error') {
          log('❌ Auth error: ${msg['message']}');
          _updateState(NodeConnectionState.error, 'Auth failed: ${msg['message']}');
          return;
        }
        return;
      }

      switch (msg['type']) {
        case 'invoke':
          _handleInvoke(msg);
          break;
        case 'pong':
          break;
        case 'error':
          log('⚠️ Server error: ${msg['message']}');
          break;
        default:
          log('📡 Unknown: ${msg['type']}');
      }
    } catch (e) {
      log('⚠️ Parse error: $e');
    }
  }

  Future<void> _handleInvoke(Map<String, dynamic> msg) async {
    final requestId = msg['requestId'] as String? ?? '';
    final command = msg['command'] as String? ?? '';
    final args = (msg['args'] as Map<String, dynamic>?) ?? {};

    log('⚡ Invoke: $command $args');

    try {
      final result = await onInvoke(command, args);
      _send({
        'type': 'invoke.result',
        'requestId': requestId,
        'ok': true,
        'data': result,
      });
    } catch (e) {
      log('❌ Invoke error: $e');
      _send({
        'type': 'invoke.result',
        'requestId': requestId,
        'ok': false,
        'error': e.toString(),
      });
    }
  }

  void sendNodeEvent(String eventName, Map<String, dynamic> payload) {
    _send({
      'type': 'event',
      'event': eventName,
      'data': payload,
    });
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel == null || !_authenticated) return;
    if (_debug) log('📤 -> ${jsonToString(msg)}');
    _channel!.sink.add(jsonEncode(msg));
  }

  void _scheduleReconnect() {
    if (!_active) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = (_reconnectAttempts <= 5)
        ? (_reconnectAttempts * 2000)
        : 30000;
    log('🔄 Reconnecting in ${delay ~/ 1000}s');
    _updateState(NodeConnectionState.reconnecting, 'Reconnecting...');
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _subscription?.cancel();
      _subscription = null;
      _channel = null;
      _authenticated = false;
      _connect();
    });
  }

  void _updateState(NodeConnectionState state, String status) {
    stateNotifier.value = state;
    statusNotifier.value = status;
  }

  String jsonToString(Map<String, dynamic> json) {
    final truncated = json.map((k, v) {
      if (v is String && v.length > 80) return MapEntry(k, '${v.substring(0, 80)}...');
      return MapEntry(k, v);
    });
    return jsonEncode(truncated);
  }

  void log(String msg) {
    if (_debug) debugPrint('🔷 [Relay] $msg');
  }

  void dispose() {
    _active = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    stateNotifier.dispose();
    statusNotifier.dispose();
  }
}
