import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/sync/client.dart';
import 'package:i_gen/sync/network_discovery_service.dart';
import 'package:i_gen/sync/server.dart';
import 'package:i_gen/sync/sync_models.dart';
import 'package:i_gen/sync/sync_qr.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'package:i_gen/sync/network_utils.dart';
import 'package:i_gen/sync/device_identity.dart';
import 'package:i_gen/sync/widgets/qr_display.dart';
import 'package:i_gen/sync/widgets/qr_scanner.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8080');

  SyncService get _syncService => GetIt.I.get<SyncService>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Start discovery when screen opens
    _syncService.discovery.startDiscovery();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _syncService.discovery.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.download), text: 'Receive'),
            Tab(icon: Icon(Icons.upload), text: 'Send'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ReceiveTab(syncService: _syncService),
          _SendTab(
            syncService: _syncService,
            ipController: _ipController,
            portController: _portController,
          ),
        ],
      ),
    );
  }
}

// ==================== RECEIVE TAB ====================

class _ReceiveTab extends StatelessWidget {
  const _ReceiveTab({required this.syncService});

  final SyncService syncService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServerState>(
      stream: syncService.server.stateStream,
      initialData: syncService.server.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? ServerState.stopped();
        return _ReceiveContent(
          state: state,
          onStart: () => _startServer(context),
          onStop: () => syncService.server.stop(),
        );
      },
    );
  }

  Future<void> _startServer(BuildContext context) async {
    try {
      await syncService.server.start();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start server: $e')));
      }
    }
  }
}

class _ReceiveContent extends StatelessWidget {
  const _ReceiveContent({
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final ServerState state;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Action Button
          FilledButton.icon(
            onPressed: state.status == ServerStatus.running ? onStop : onStart,
            icon: Icon(
              state.status == ServerStatus.running
                  ? Icons.stop
                  : Icons.play_arrow,
            ),
            label: Text(
              state.status == ServerStatus.running
                  ? 'Stop Server'
                  : 'Start Server',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, 48),
              backgroundColor: state.status == ServerStatus.running
                  ? colors.error
                  : colors.primary,
            ),
          ),
          const SizedBox(height: 12),
          // QR Code or Status
          if (state.status == ServerStatus.running)
            FutureBuilder<SyncQrData>(
              future: _buildQrData(state),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return SyncQrDisplay(qrData: snapshot.data!);
                }
                return const CircularProgressIndicator();
              },
            )
          else
            _buildStatusDisplay(context, colors),

          const SizedBox(height: 32),

          // Last sync result
          if (state.lastResult != null) ...[
            _SyncResultCard(result: state.lastResult!),
            const SizedBox(height: 24),
          ],

          // Instructions
          if (state.status == ServerStatus.stopped) ...[
            const SizedBox(height: 32),
            Text(
              'Start the server to receive data from another device.\n'
              'Make sure both devices are on the same Wi-Fi network.',
              style: TextStyle(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<SyncQrData> _buildQrData(ServerState state) async {
    return SyncQrData(
      ip: state.ip!,
      port: state.port!,
      deviceName: await DeviceIdentity.getDeviceName(),
      deviceId: await DeviceIdentity.getDeviceId(),
    );
  }

  Widget _buildStatusDisplay(BuildContext context, ColorScheme colors) {
    final (icon, color, title) = switch (state.status) {
      ServerStatus.stopped => (
        Icons.cloud_off,
        colors.onSurfaceVariant,
        'Server Stopped',
      ),
      ServerStatus.starting => (
        Icons.cloud_sync,
        colors.primary,
        'Starting...',
      ),
      ServerStatus.running => (
        Icons.cloud_done,
        colors.primary,
        'Server Running',
      ),
      ServerStatus.error => (Icons.error, colors.error, 'Server Error'),
    };

    return Column(
      children: [
        Icon(icon, size: 80, color: color),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (state.status == ServerStatus.error && state.error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              state.error!,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ],
    );
  }
}

// ==================== SEND TAB ====================

class _SendTab extends StatefulWidget {
  const _SendTab({
    required this.syncService,
    required this.ipController,
    required this.portController,
  });

  final SyncService syncService;
  final TextEditingController ipController;
  final TextEditingController portController;

  @override
  State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  bool _showManualInput = false;

  bool get _canScanQr => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClientState>(
      stream: widget.syncService.client.stateStream,
      initialData: widget.syncService.client.currentState,
      builder: (context, clientSnapshot) {
        final clientState = clientSnapshot.data ?? ClientState.idle();

        return StreamBuilder<List<DiscoveredDevice>>(
          stream: widget.syncService.discovery.devicesStream,
          initialData: widget.syncService.discovery.devices,
          builder: (context, devicesSnapshot) {
            final devices = devicesSnapshot.data ?? [];

            return _SendContent(
              clientState: clientState,
              devices: devices,
              showManualInput: _showManualInput,
              ipController: widget.ipController,
              portController: widget.portController,
              canScanQr: _canScanQr,
              onToggleManual: () =>
                  setState(() => _showManualInput = !_showManualInput),
              onRefresh: () => widget.syncService.discovery.refresh(),
              onSyncWithDevice: (device) => _syncWithDevice(device),
              onSyncManual: () => _syncManual(),
              onScanQr: () => _scanQrCode(),
            );
          },
        );
      },
    );
  }

  Future<void> _syncWithDevice(DiscoveredDevice device) async {
    try {
      await widget.syncService.client.syncWith(
        ip: device.ip,
        port: device.port,
      );
    } catch (_) {
      // Error shown via stream
    }
  }

  Future<void> _syncManual() async {
    final ip = widget.ipController.text.trim();
    final port = int.tryParse(widget.portController.text) ?? 8080;

    if (!NetworkUtils.isValidIp(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid IP address')),
      );
      return;
    }

    try {
      await widget.syncService.client.syncWith(ip: ip, port: port);
    } catch (_) {
      // Error shown via stream
    }
  }

  void _scanQrCode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyncQrScanner(
          onScanned: (data) {
            widget.ipController.text = data.ip;
            widget.portController.text = data.port.toString();
            setState(() => _showManualInput = true);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Found: ${data.deviceName} (${data.ip})'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SendContent extends StatelessWidget {
  const _SendContent({
    required this.clientState,
    required this.devices,
    required this.showManualInput,
    required this.ipController,
    required this.portController,
    required this.canScanQr,
    required this.onToggleManual,
    required this.onRefresh,
    required this.onSyncWithDevice,
    required this.onSyncManual,
    required this.onScanQr,
  });

  final ClientState clientState;
  final List<DiscoveredDevice> devices;
  final bool showManualInput;
  final TextEditingController ipController;
  final TextEditingController portController;
  final bool canScanQr;
  final VoidCallback onToggleManual;
  final VoidCallback onRefresh;
  final void Function(DiscoveredDevice) onSyncWithDevice;
  final VoidCallback onSyncManual;
  final VoidCallback onScanQr;

  bool get _isIdle =>
      clientState.status == ClientStatus.idle ||
      clientState.status == ClientStatus.success ||
      clientState.status == ClientStatus.error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card (when syncing)
            if (!_isIdle) ...[
              _StatusCard(state: clientState),
              const SizedBox(height: 16),
            ],

            // Discovered Devices
            _buildDiscoveredDevices(context, colors),

            const SizedBox(height: 16),

            // Alternative Methods
            _buildAlternativeMethods(context, colors),

            // Result Display
            if (clientState.result != null) ...[
              const SizedBox(height: 16),
              _SyncResultCard(result: clientState.result!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveredDevices(BuildContext context, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.devices, color: colors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Available Devices',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isIdle ? onRefresh : null,
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (devices.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.search,
                  size: 48,
                  color: colors.onSurfaceVariant.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Searching for devices...',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'Make sure the other device has started receiving',
                  style: TextStyle(
                    color: colors.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...devices.map(
            (device) => _DeviceCard(
              device: device,
              onSync: () => onSyncWithDevice(device),
              isEnabled: _isIdle,
            ),
          ),
      ],
    );
  }

  Widget _buildAlternativeMethods(BuildContext context, ColorScheme colors) {
    return Column(
      children: [
        // Divider
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR CONNECT MANUALLY',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),

        // Buttons Row
        Row(
          children: [
            if (canScanQr) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isIdle ? onScanQr : null,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isIdle ? onToggleManual : null,
                icon: Icon(showManualInput ? Icons.expand_less : Icons.edit),
                label: Text(showManualInput ? 'Hide' : 'Enter IP'),
              ),
            ),
          ],
        ),

        // Manual Input Section
        if (showManualInput) ...[
          const SizedBox(height: 16),
          _ManualInputSection(
            ipController: ipController,
            portController: portController,
            isEnabled: _isIdle,
            onSync: onSyncManual,
          ),
        ],
      ],
    );
  }
}

// ==================== DEVICE CARD ====================

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.onSync,
    required this.isEnabled,
  });

  final DiscoveredDevice device;
  final VoidCallback onSync;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_getDeviceIcon(), color: colors.onPrimaryContainer),
        ),
        title: Text(device.name),
        subtitle: Text(
          '${device.ip}:${device.port}',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        trailing: FilledButton(
          onPressed: isEnabled ? onSync : null,
          child: const Text('Sync'),
        ),
      ),
    );
  }

  IconData _getDeviceIcon() {
    final name = device.name.toLowerCase();
    if (name.contains('windows')) return Icons.desktop_windows;
    if (name.contains('android')) return Icons.phone_android;
    if (name.contains('ios') || name.contains('iphone'))
      return Icons.phone_iphone;
    if (name.contains('mac')) return Icons.laptop_mac;
    return Icons.devices;
  }
}

// ==================== MANUAL INPUT SECTION ====================

class _ManualInputSection extends StatelessWidget {
  const _ManualInputSection({
    required this.ipController,
    required this.portController,
    required this.isEnabled,
    required this.onSync,
  });

  final TextEditingController ipController;
  final TextEditingController portController;
  final bool isEnabled;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: ipController,
                  enabled: isEnabled,
                  decoration: const InputDecoration(
                    labelText: 'IP Address',
                    hintText: '192.168.1.100',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: portController,
                  enabled: isEnabled,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isEnabled ? onSync : null,
            icon: const Icon(Icons.sync),
            label: const Text('Sync Now'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== SHARED WIDGETS ====================

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final (icon, color, bgColor) = switch (state.status) {
      ClientStatus.idle => (
        Icons.hourglass_empty,
        colors.onSurfaceVariant,
        colors.surfaceContainerHighest,
      ),
      ClientStatus.connecting => (
        Icons.wifi_find,
        colors.primary,
        colors.primaryContainer,
      ),
      ClientStatus.syncing => (
        Icons.sync,
        colors.primary,
        colors.primaryContainer,
      ),
      ClientStatus.success => (
        Icons.check_circle,
        Colors.green,
        Colors.green.withOpacity(0.1),
      ),
      ClientStatus.error => (Icons.error, colors.error, colors.errorContainer),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (state.status == ClientStatus.syncing ||
              state.status == ClientStatus.connecting)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: state.progress,
              ),
            )
          else
            Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.message.isEmpty ? 'Ready to sync' : state.message,
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                ),
                if (state.status == ClientStatus.success &&
                    state.result != null &&
                    state.result!.inserted == 0 &&
                    state.result!.updated == 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tap sync again after making changes',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncResultCard extends StatelessWidget {
  const _SyncResultCard({required this.result});

  final SyncResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: colors.onSecondaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Sync Complete',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.onSecondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ResultItem(
                label: 'Inserted',
                value: result.inserted,
                icon: Icons.add_circle_outline,
              ),
              _ResultItem(
                label: 'Updated',
                value: result.updated,
                icon: Icons.edit,
              ),
              _ResultItem(
                label: 'Deleted',
                value: result.deleted,
                icon: Icons.delete_outline,
              ),
              _ResultItem(
                label: 'Skipped',
                value: result.skipped,
                icon: Icons.skip_next,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultItem extends StatelessWidget {
  const _ResultItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
