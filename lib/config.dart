/// App configuration — edit these to match your OpenClaw VPS setup.
class AppConfig {
  AppConfig._();

  /// Your OpenClaw Gateway URL (behind nginx proxy on your domain).
  /// Uses the same port 443 as your chess bot via the /openclaw/ path.
  static const String gatewayHost = 'konoyves.shop';
  static const int gatewayPort = 443;
  static const bool useTls = true;

  /// Path prefix for WebSocket connections (nginx location proxying to Gateway).
  static const String gatewayPath = '/openclaw/';

  /// Gateway auth token — set via: openclaw config patch
  static const String gatewayToken = '5720c3d31ae1cb0063506b6a014f43a242f3ec436a5fa18a';
  static const String gatewayPassword = '';

  /// Device display name shown in OpenClaw's node list.
  static const String deviceDisplayName = "Kono's Phone";

  /// App version — matches pubspec.
  static const String appVersion = '1.0.0';

  /// Reconnect delays (ms).
  static const int reconnectBaseMs = 1000;
  static const int reconnectMaxMs = 30000;

  /// Node capabilities declared to Gateway.
  static const List<String> nodeCaps = ['alarm', 'calendar', 'notification', 'phone'];

  /// Node commands the app can handle.
  static const List<String> nodeCommands = [
    'alarm.set',
    'alarm.list',
    'alarm.clear',
    'alarm.toggle',
    'calendar.list',
    'calendar.add',
    'calendar.remove',
    'calendar.upcoming',
    'notification.send',
    'phone.ping',
  ];
}
