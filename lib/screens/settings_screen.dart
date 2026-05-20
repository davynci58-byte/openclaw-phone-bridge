import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/openclaw_node_service.dart';
import '../services/storage_service.dart';
import '../config.dart';

/// Settings screen for configuring OpenClaw connection.
class SettingsScreen extends StatefulWidget {
  final OpenClawNodeService nodeService;

  const SettingsScreen({super.key, required this.nodeService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _hostCtl;
  late TextEditingController _portCtl;
  late TextEditingController _pathCtl;
  late TextEditingController _tokenCtl;
  bool _useTls = true;

  @override
  void initState() {
    super.initState();
    _hostCtl = TextEditingController(text: AppConfig.gatewayHost);
    _portCtl =
        TextEditingController(text: AppConfig.gatewayPort.toString());
    _pathCtl = TextEditingController(text: AppConfig.gatewayPath);
    _tokenCtl = TextEditingController(text: _maskedToken);
    _loadPrefs();
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _portCtl.dispose();
    _pathCtl.dispose();
    _tokenCtl.dispose();
    super.dispose();
  }

  String get _maskedToken {
    final t = AppConfig.gatewayToken;
    return t.length > 8 ? '${t.substring(0, 4)}...${t.substring(t.length - 4)}' : t;
  }

  Future<String> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('gateway_token') ?? '';
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('gateway_host');
    final port = prefs.getInt('gateway_port');
    final path = prefs.getString('gateway_path');
    final tls = prefs.getBool('gateway_tls');
    final token = prefs.getString('gateway_token');
    setState(() {
      if (host != null) _hostCtl.text = host;
      if (port != null) _portCtl.text = port.toString();
      if (path != null) _pathCtl.text = path;
      if (tls != null) _useTls = tls;
      if (token != null && token.isNotEmpty) _tokenCtl.text = token;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gateway_host', _hostCtl.text.trim());
    await prefs.setInt('gateway_port', int.tryParse(_portCtl.text) ?? 443);
    await prefs.setString('gateway_path', _pathCtl.text.trim());
    await prefs.setBool('gateway_tls', _useTls);
    await prefs.setString('gateway_token', _tokenCtl.text.trim());
  }

  // ── Manage Connection ───────────────────────────────────────────

  Future<void> _reconnect() async {
    await _savePrefs();
    await widget.nodeService.stop();
    await Future.delayed(const Duration(milliseconds: 500));
    await widget.nodeService.start();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reconnecting...')),
      );
    }
  }

  Future<void> _disconnect() async {
    await widget.nodeService.stop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Connection Section ─────────────────────────────────
          Text('OpenClaw Gateway',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 12),
          TextField(
            controller: _hostCtl,
            decoration: const InputDecoration(
              labelText: 'Host / IP',
              hintText: 'your-vps.com or 123.456.789.0',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _portCtl,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '443',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: SwitchListTile(
                  title: const Text('TLS (WSS)'),
                  value: _useTls,
                  onChanged: (v) => setState(() => _useTls = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pathCtl,
            decoration: const InputDecoration(
              labelText: 'WebSocket Path',
              hintText: '/gateway/',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtl,
            decoration: const InputDecoration(
              labelText: 'Gateway Token',
              hintText: 'Your OpenClaw gateway token',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),

          // Connection controls
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _reconnect,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reconnect'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            'Tip: Connect to konoyves.shop:443 with TLS ON and path /gateway/',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),

          // ── Connection Status ──────────────────────────────────
          Text('Connection Status',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<String>(
                valueListenable: widget.nodeService.statusNotifier,
                builder: (_, status, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Status', status),
                    const SizedBox(height: 8),
                    _infoRow('Device ID', widget.nodeService.shortDeviceId),
                    const SizedBox(height: 8),
                    _infoRow('Role', 'Node'),
                    const SizedBox(height: 8),
                    _infoRow('Version', AppConfig.appVersion),
                    const SizedBox(height: 8),
                    _infoRow(
                        'Capabilities', AppConfig.nodeCaps.join(', ')),
                    const SizedBox(height: 8),
                    _infoRow(
                        'Commands', AppConfig.nodeCommands.join(', ')),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── About ──────────────────────────────────────────────
          Text('About',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield),
              title: const Text('OpenClaw Phone Bridge'),
              subtitle: const Text('Version 1.0.0 — Flutter'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
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
    );
  }
}
