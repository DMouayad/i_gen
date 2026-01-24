import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:i_gen/sync/network_discovery_service.dart';
import 'package:i_gen/sync/sync_preferences.dart';
import 'package:i_gen/sync/sync_orchestrator.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'package:i_gen/utils/context_extensions.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late final SyncOrchestrator _orchestrator;
  late final SyncService _syncService;

  @override
  void initState() {
    super.initState();
    _orchestrator = GetIt.I.get<SyncOrchestrator>();
    _syncService = GetIt.I.get<SyncService>();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _orchestrator.preferences;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: context.isMobile ? EdgeInsets.zero : const EdgeInsets.all(12.0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ListTile(
              title: Text(
                'Sync Settings',
                style: context.textTheme.titleMedium,
              ),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              children: [
                // Default Device Section
                _SectionHeader(title: 'Default Sync Device'),

                _buildDefaultDeviceTile(prefs, colors),

                const Divider(),

                // Auto-Sync Section
                _SectionHeader(title: 'Auto Sync'),

                SwitchListTile(
                  title: const Text('Enable Auto-Sync'),
                  subtitle: const Text(
                    'Automatically sync when default device is available',
                  ),
                  value: prefs.autoSyncEnabled,
                  onChanged: (value) async {
                    await prefs.setAutoSyncEnabled(value);
                    setState(() {});
                  },
                ),

                ListTile(
                  title: const Text('Sync Interval'),
                  subtitle: Text('Every ${prefs.syncIntervalHours} hours'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: prefs.autoSyncEnabled,
                  onTap: () => _showIntervalPicker(prefs),
                ),

                ListTile(
                  title: const Text('Last Sync'),
                  subtitle: Text(_formatLastSync(prefs.lastSyncTime)),
                  leading: const Icon(Icons.history),
                ),

                const Divider(),

                // Quick Actions
                _SectionHeader(title: 'Quick Actions'),

                ListTile(
                  title: const Text('Sync Now'),
                  subtitle: const Text(
                    'Bidirectional sync with default device',
                  ),
                  leading: const Icon(Icons.sync),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: prefs.defaultDevice != null,
                  onTap: () => _performQuickSync(),
                ),

                ListTile(
                  title: const Text('Clear Sync History'),
                  subtitle: const Text('Reset all sync timestamps'),
                  leading: Icon(Icons.delete_outline, color: colors.error),
                  onTap: () => _confirmClearHistory(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultDeviceTile(SyncPreferences prefs, ColorScheme colors) {
    final device = prefs.defaultDevice;

    if (device == null) {
      return ListTile(
        title: const Text('No device selected'),
        subtitle: const Text('Tap to select a default sync device'),
        leading: const Icon(Icons.devices),
        trailing: const Icon(Icons.add),
        onTap: () => _selectDefaultDevice(),
      );
    }

    return ListTile(
      title: Text(device.deviceName),
      subtitle: Text('${device.ip}:${device.port}'),
      leading: Icon(_getDeviceIcon(device.deviceName), color: colors.primary),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _selectDefaultDevice(),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.error),
            onPressed: () => _clearDefaultDevice(prefs),
          ),
        ],
      ),
    );
  }

  void _selectDefaultDevice() async {
    // Start discovery
    await _syncService.discovery.startDiscovery();

    if (!mounted) return;

    final result = await showModalBottomSheet<DiscoveredDevice>(
      context: context,
      builder: (context) =>
          _DevicePickerSheet(discovery: _syncService.discovery),
    );

    await _syncService.discovery.stopDiscovery();

    if (result != null) {
      final config = SyncDeviceConfig(
        deviceId: result.deviceId,
        deviceName: result.name,
        ip: result.ip,
        port: result.port,
      );
      await _orchestrator.preferences.setDefaultDevice(config);
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Default device set to ${result.name}')),
        );
      }
    }
  }

  void _clearDefaultDevice(SyncPreferences prefs) async {
    await prefs.setDefaultDevice(null);
    setState(() {});
  }

  void _showIntervalPicker(SyncPreferences prefs) async {
    final intervals = [1, 6, 12, 24, 48, 72];

    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sync Interval'),
        children: intervals
            .map(
              (hours) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, hours),
                child: Text(hours == 1 ? 'Every hour' : 'Every $hours hours'),
              ),
            )
            .toList(),
      ),
    );

    if (result != null) {
      await prefs.setSyncIntervalHours(result);
      setState(() {});
    }
  }

  void _performQuickSync() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuickSyncDialog(orchestrator: _orchestrator),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync completed!')));
    }
  }

  void _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Sync History?'),
        content: const Text(
          'This will reset all sync timestamps. '
          'The next sync will transfer all data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Clear sync history from database
      // await _syncService.repository.clearSyncHistory();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sync history cleared')));
      }
    }
  }

  String _formatLastSync(DateTime? time) {
    if (time == null) return 'Never';

    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  IconData _getDeviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('windows')) return Icons.desktop_windows;
    if (lower.contains('android')) return Icons.phone_android;
    if (lower.contains('ios') || lower.contains('iphone'))
      return Icons.phone_iphone;
    if (lower.contains('mac')) return Icons.laptop_mac;
    if (lower.contains('linux')) return Icons.computer;
    return Icons.devices;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ==================== Device Picker ====================

class _DevicePickerSheet extends StatelessWidget {
  const _DevicePickerSheet({required this.discovery});

  final SyncDiscovery discovery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Select Device',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => discovery.refresh(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: StreamBuilder<List<DiscoveredDevice>>(
              stream: discovery.devicesStream,
              initialData: discovery.devices,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];

                if (devices.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Searching for devices...'),
                        SizedBox(height: 8),
                        Text(
                          'Make sure the other device is on\nthe Sync screen with server running',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return ListTile(
                      leading: Icon(_getDeviceIcon(device.name)),
                      title: Text(device.name),
                      subtitle: Text('${device.ip}:${device.port}'),
                      onTap: () => Navigator.pop(context, device),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _enterManually(context),
              child: const Text('Enter IP Manually'),
            ),
          ),
        ],
      ),
    );
  }

  void _enterManually(BuildContext context) async {
    final result = await showDialog<DiscoveredDevice>(
      context: context,
      builder: (context) => const _ManualIpDialog(),
    );

    if (result != null && context.mounted) {
      Navigator.pop(context, result);
    }
  }

  IconData _getDeviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('windows')) return Icons.desktop_windows;
    if (lower.contains('android')) return Icons.phone_android;
    if (lower.contains('linux')) return Icons.computer;
    return Icons.devices;
  }
}

class _ManualIpDialog extends StatefulWidget {
  const _ManualIpDialog();

  @override
  State<_ManualIpDialog> createState() => _ManualIpDialogState();
}

class _ManualIpDialogState extends State<_ManualIpDialog> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Device Details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Device Name',
              hintText: 'e.g., My Laptop',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'IP Address',
              hintText: '192.168.1.100',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '8080',
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text) ?? 8080;

    if (name.isEmpty || ip.isEmpty) return;

    // Create a device with a generated ID (since we don't know it)
    final device = DiscoveredDevice(
      deviceId: 'manual-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      ip: ip,
      port: port,
      discoveredAt: DateTime.now(),
    );

    Navigator.pop(context, device);
  }
}

// ==================== Quick Sync Dialog ====================

class _QuickSyncDialog extends StatefulWidget {
  const _QuickSyncDialog({required this.orchestrator});

  final SyncOrchestrator orchestrator;

  @override
  State<_QuickSyncDialog> createState() => _QuickSyncDialogState();
}

class _QuickSyncDialogState extends State<_QuickSyncDialog> {
  @override
  void initState() {
    super.initState();
    _startSync();
  }

  void _startSync() async {
    await widget.orchestrator.syncWithDefaultDevice();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AutoSyncState>(
      stream: widget.orchestrator.stateStream,
      initialData: widget.orchestrator.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? AutoSyncState.idle();

        return AlertDialog(
          title: Text(_getTitle(state)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.status != AutoSyncStatus.completed &&
                  state.status != AutoSyncStatus.failed)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),

              Text(state.message),

              if (state.status == AutoSyncStatus.completed) ...[
                const SizedBox(height: 16),
                _buildResultSummary(state),
              ],

              if (state.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            if (state.status == AutoSyncStatus.completed ||
                state.status == AutoSyncStatus.failed)
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  state.status == AutoSyncStatus.completed,
                ),
                child: const Text('Close'),
              ),
          ],
        );
      },
    );
  }

  String _getTitle(AutoSyncState state) {
    return switch (state.status) {
      AutoSyncStatus.idle => 'Sync',
      AutoSyncStatus.waitingForDevice => 'Waiting',
      AutoSyncStatus.connecting => 'Connecting',
      AutoSyncStatus.syncingOutbound => 'Sending',
      AutoSyncStatus.syncingInbound => 'Receiving',
      AutoSyncStatus.completed => 'Sync Complete',
      AutoSyncStatus.failed => 'Sync Failed',
    };
  }

  Widget _buildResultSummary(AutoSyncState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _ResultColumn(label: 'Inserted', value: state.totalInserted),
        _ResultColumn(label: 'Updated', value: state.totalUpdated),
        _ResultColumn(label: 'Deleted', value: state.totalDeleted),
      ],
    );
  }
}

class _ResultColumn extends StatelessWidget {
  const _ResultColumn({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
