import 'package:flutter/material.dart';
import '../services/openclaw_node_service.dart';

/// A small status indicator bar showing OpenClaw connection state.
class ConnectionStatusBar extends StatelessWidget {
  final OpenClawNodeService service;

  const ConnectionStatusBar({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NodeConnectionState>(
      valueListenable: service.stateNotifier,
      builder: (context, state, _) {
        final (color, icon, label) = switch (state) {
          NodeConnectionState.connected => (
            Colors.green,
            Icons.cloud_done,
            'OpenClaw Connected',
          ),
          NodeConnectionState.connecting => (
            Colors.orange,
            Icons.cloud_upload,
            'Connecting...',
          ),
          NodeConnectionState.reconnecting => (
            Colors.orangeAccent,
            Icons.sync,
            'Reconnecting...',
          ),
          NodeConnectionState.error => (
            Colors.red,
            Icons.cloud_off,
            'Connection Error',
          ),
          NodeConnectionState.disconnected => (
            Colors.grey,
            Icons.cloud_off,
            'Disconnected',
          ),
        };

        return GestureDetector(
          onTap: () => _showDetail(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              border: Border(
                bottom: BorderSide(color: color.withOpacity(0.3), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  service.shortDeviceId,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withOpacity(0.7),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenClaw Connection'),
        content: ValueListenableBuilder<String>(
          valueListenable: service.statusNotifier,
          builder: (_, status, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Status', status),
              _row('Device ID', service.shortDeviceId),
              _row('Role', 'Node'),
              _row('Server', 'VPS Gateway'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

/// A compact connection dot for app bars.
class ConnectionDot extends StatelessWidget {
  final OpenClawNodeService service;

  const ConnectionDot({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NodeConnectionState>(
      valueListenable: service.stateNotifier,
      builder: (_, state, __) {
        final color = switch (state) {
          NodeConnectionState.connected => Colors.green,
          NodeConnectionState.connecting => Colors.orange,
          NodeConnectionState.reconnecting => Colors.orangeAccent,
          _ => Colors.grey,
        };
        return Tooltip(
          message: 'OpenClaw: ${state.name}',
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
        );
      },
    );
  }
}
