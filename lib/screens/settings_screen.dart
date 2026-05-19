import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/openclaw_node_service.dart';
import '../config.dart';

/// Settings screen for OpenClaw connection configuration.
class SettingsScreen extends StatefulWidget {
  final OpenClawNodeService nodeService;

  const SettingsScreen({super.key, required this.nodeService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostCtl = TextEditingController(text: AppConfig.gatewayHost);
  final _portCtl = TextEditingController(text: AppConfig.gatewayPort.toString());
  final _tokenCtl = TextEditingController();
  bool _useTls = AppConfig.useTls;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _portCtl.dispose();
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostCtl.text = prefs.getString('gw_host') ?? AppConfig.gatewayHost;
      _portCtl.text = (prefs.getInt('gw_port') ?? AppConfig.gatewayPort).toString();
      _useTls = prefs.getBool('gw_tls') ?? AppConfig.useTls;
      final savedToken = prefs.getString('gw_token') ?? '';
      _tokenCtl.text = savedToken;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gw_host', _hostCtl.text.trim());
    await prefs.setInt('gw_port', int.tryParse(_portCtl.text) ?? 443);
    await prefs.setBool('gw_tls', _useTls);
    if (_tokenCtl.text.isNotEmpty) await prefs.setString('gw_token', _tokenCtl.text);
  }

  Future<void> _reconnect() async {
    await _savePrefs();
    await widget.nodeService.stop();
    await Future.delayed(const Duration(milliseconds: 500));
    await widget.nodeService.start();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reconnecting...')),
    );
  }

  Future<void> _disconnect() async {
    await widget.nodeService.stop();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('OpenClaw Gateway', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _hostCtl,
            decoration: const InputDecoration(
              labelText: 'Host / IP',
              hintText: 'vps.example.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
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
                child: SwitchListTile(
                  title: const Text('TLS'),
                  value: _useTls,
                  onChanged: (v) => setState(() => _useTls = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtl,
            decoration: const InputDecoration(
              labelText: 'Gateway Token',
              hintText: 'Your OpenClaw auth token',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
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
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text('Status', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                    _infoRow('Device', widget.nodeService.shortDeviceId),
                    _infoRow('Role', 'Node'),
                    _infoRow('Caps', AppConfig.nodeCaps.join(', ')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
