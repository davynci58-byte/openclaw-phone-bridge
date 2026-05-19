/// App configuration — edit these to match your OpenClaw VPS setup.
class AppConfig {
  AppConfig._();

  /// Your OpenClaw Gateway host (VPS IP or domain).
  /// Keep this in your app's .env or hardcode for self-hosted.
  static const String gatewayHost = 'konoyves.shop';

  /// Gateway WebSocket port (same as HTTP port, usually 443 or 8443).
  static const int gatewayPort = 443;

  /// WebSocket path (e.g. /gateway/ for nginx proxy routes).
  /// This allows routing through the existing nginx on port 443
  /// without needing a separate port.
  static const String gatewayPath = '/gateway/';

  /// Use WSS (true) or WS (false) — always true for remote VPS.
  static const bool useTls = true;

  /// Gateway auth token or password — set in openclaw config.
  /// If gateway.auth.mode == "token", set OPENCLAW_GATEWAY_TOKEN.
  /// If gateway.auth.mode == "password", set OPENCLAW_GATEWAY_PASSWORD.
  static const String gatewayToken = '';

  /// Gateway password mode fallback.
  static const String gatewayPassword = '';

  /// Device display name shown in OpenClaw's node list.
  static const String deviceDisplayName = 'Kono\'s Phone';

  /// App version — matches pubspec.
  static const String appVersion = '1.0.0';

  /// Reconnect delays (ms).
  static const int reconnectBaseMs = 1000;
  static const int reconnectMaxMs = 30000;

  /// Node capabilities declared to Gateway.
  static const List<String> nodeCaps = [
    'alarm',
    'calendar',
    'notification',
    'phone',
  ];

  /// Node commands the app can handle.
  static const List<String> nodeCommands = [
    'alarm.set',
    'alarm.list',
    'alarm.clear',
    'calendar.list',
    'calendar.add',
    'calendar.remove',
    'notification.send',
    'phone.ping',
  ];
}
