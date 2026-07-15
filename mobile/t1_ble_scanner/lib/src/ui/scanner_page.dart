import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/beacon_view_model.dart';
import '../services/ble_scanner_controller.dart';
import '../services/operators_repository.dart';
import '../services/stops_repository.dart';
import '../services/t1_crypto.dart';
import '../utils/beacon_utils.dart';
import 'operators_editor_page.dart';
import 'radar_view.dart';
import 'settings_sheet.dart';
import 'stops_editor_page.dart';
import 'tag_id_panel.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with SingleTickerProviderStateMixin {
  late final BleScannerController _controller;
  late final StopsRepository _stopsRepo;
  late final OperatorsRepository _operatorsRepo;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _tagMaxCtrl;
  late final TextEditingController _prodWindowCtrl;
  late final TextEditingController _protoSlotMaxCtrl;
  late final TabController _tabCtrl;

  T1ScanMode _scanMode = T1ScanMode.production;

  @override
  void initState() {
    super.initState();
    _controller = BleScannerController()..addListener(_onControllerChanged);
    _stopsRepo = StopsRepository();
    _controller.attachStopsRepository(_stopsRepo);
    _operatorsRepo = OperatorsRepository();
    _controller.attachOperatorsRepository(_operatorsRepo);
    _keyCtrl = TextEditingController();
    _tagMaxCtrl = TextEditingController();
    _prodWindowCtrl = TextEditingController();
    _protoSlotMaxCtrl = TextEditingController();
    _tabCtrl = TabController(length: 2, vsync: this);
    _controller.initialize();
  }

  bool _autoStartDone = false;

  bool _stopsInitialized = false;
  bool _operatorsInitialized = false;

  void _onControllerChanged() {
    final config = _controller.config;
    if (config == null) return;

    // One-time: populate scan setting fields and stops defaults.
    if (_keyCtrl.text.isEmpty) {
      _keyCtrl.text = config.defaults.keyHex;
      _tagMaxCtrl.text = config.defaults.tagMax.toString();
      _prodWindowCtrl.text = config.defaults.productionSlotWindow.toString();
      _protoSlotMaxCtrl.text = config.defaults.prototypeSlotMax.toString();
    }
    if (!_stopsInitialized) {
      _stopsInitialized = true;
      // Load prefs first, then merge config stops for missing tagIds.
      _stopsRepo.load().then((_) => _stopsRepo.setDefaults(config.stops));
    }
    if (!_operatorsInitialized) {
      _operatorsInitialized = true;
      // Load prefs first, then merge config external operators for missing UUIDs.
      // T1's own (local) operator is excluded — it's handled via isT1 flag.
      _operatorsRepo.load().then((_) {
        _operatorsRepo.setFromConfig(
          config.externalOperators
              .map((op) => (uuid: op.uuid, name: op.name, code: op.code))
              .toList(),
        );
      });
    }

    // Auto-start: once, as soon as config is loaded and BLE is ready.
    if (!_autoStartDone && !_controller.initializing && !_controller.scanning) {
      _autoStartDone = true;
      _startScan();
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _stopsRepo.dispose();
    _operatorsRepo.dispose();
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _keyCtrl.dispose();
    _tagMaxCtrl.dispose();
    _prodWindowCtrl.dispose();
    _protoSlotMaxCtrl.dispose();
    super.dispose();
  }

  // ── scan control ──────────────────────────────────────────────────────────

  Future<void> _startScan() async {
    if (_controller.scanning) return;

    // adapterStateNow may be `unknown` right after app start — wait for the
    // first known state (up to 4 s) before deciding whether BT is on.
    var bleState = _controller.bleAdapterState;
    if (bleState == BluetoothAdapterState.unknown ||
        bleState == BluetoothAdapterState.turningOn) {
      bleState = await _controller.bleAdapterStateStream
          .firstWhere((s) =>
              s != BluetoothAdapterState.unknown &&
              s != BluetoothAdapterState.turningOn)
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => _controller.bleAdapterState,
          );
    }

    if (bleState != BluetoothAdapterState.on) {
      await _showBluetoothDialog();
      if (_controller.bleAdapterState != BluetoothAdapterState.on) return;
    }

    final settings = T1LookupSettings(
      keyHex: _keyCtrl.text.trim(),
      mode: _scanMode,
      maxTagId: int.tryParse(_tagMaxCtrl.text.trim()) ?? 100,
      productionSlotWindow: int.tryParse(_prodWindowCtrl.text.trim()) ?? 5,
      prototypeSlotMax: int.tryParse(_protoSlotMaxCtrl.text.trim()) ?? 2000,
    );
    await _controller.startScan(settings: settings);
  }

  /// Restart scan with current settings (e.g. after settings change).
  Future<void> _restartScan() async {
    await _controller.stopScan();
    await _startScan();
  }

  Future<void> _showBluetoothDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.bluetooth_disabled, color: Colors.orangeAccent),
          SizedBox(width: 10),
          Text('Bluetooth выключен'),
        ]),
        content: const Text(
          'Включите Bluetooth на устройстве и нажмите «Повторить».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.bluetooth),
            label: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  void _openStopsEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StopsEditorPage(repository: _stopsRepo),
      ),
    );
  }

  void _openOperatorsEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OperatorsEditorPage(repository: _operatorsRepo),
      ),
    );
  }

  Future<void> _openSettings() async {
    final previousMode = _scanMode;
    final previousKey = _keyCtrl.text;
    final previousTagMax = _tagMaxCtrl.text;
    final previousProdWindow = _prodWindowCtrl.text;
    final previousProtoSlotMax = _protoSlotMaxCtrl.text;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SettingsSheet(
        keyController: _keyCtrl,
        tagMaxController: _tagMaxCtrl,
        prodWindowController: _prodWindowCtrl,
        protoSlotMaxController: _protoSlotMaxCtrl,
        initialMode: _scanMode,
        config: _controller.config,
        onModeChanged: (m) => setState(() => _scanMode = m),
      ),
    );

    final changed = previousMode != _scanMode ||
        previousKey != _keyCtrl.text ||
        previousTagMax != _tagMaxCtrl.text ||
        previousProdWindow != _prodWindowCtrl.text ||
        previousProtoSlotMax != _protoSlotMaxCtrl.text;

    if (changed && _controller.scanning && mounted) {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 120), _restartScan),
      );
    }
  }

  // ── scan toggle ───────────────────────────────────────────────────────────

  Future<void> _toggleScan() async {
    if (_controller.scanning) {
      await _controller.stopScan();
      _controller.clearDevices();
    } else {
      await _startScan();
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final devices = _controller.devices;
        final scanning = _controller.scanning;
        final initializing = _controller.initializing;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F172A),
            title: GestureDetector(
              onTap: initializing ? null : _toggleScan,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: scanning
                      ? const Color(0xFF1D4ED8).withValues(alpha: 0.25)
                      : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: scanning
                        ? const Color(0xFF3B82F6)
                        : Colors.white24,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      scanning
                          ? Icons.sensors_rounded
                          : Icons.sensors_off_rounded,
                      size: 16,
                      color: scanning
                          ? const Color(0xFF60A5FA)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'T1 BLE Control',
                      style: TextStyle(
                        color: scanning ? Colors.white : Colors.white38,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (scanning) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                onPressed: _controller.clearDevices,
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Очистить список',
              ),
              IconButton(
                onPressed: _openStopsEditor,
                icon: const Icon(Icons.edit_location_alt_outlined),
                tooltip: 'Справочник остановок',
              ),
              IconButton(
                onPressed: _openOperatorsEditor,
                icon: const Icon(Icons.sensors_rounded),
                tooltip: 'Операторы UUID',
              ),
              IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Настройки',
              ),
            ],
          ),
          body: initializing
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _StatusStrip(controller: _controller),
                    TabBar(
                      controller: _tabCtrl,
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      tabs: const [
                        Tab(icon: Icon(Icons.radar_rounded), text: 'Радар'),
                        Tab(
                          icon: Icon(Icons.list_alt_rounded),
                          text: 'Список',
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _RadarTab(devices: devices, scanning: scanning),
                          _ListTab(
                            devices: devices,
                            mode: _controller.activeSettings?.mode ??
                                T1ScanMode.production,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status strip
// ─────────────────────────────────────────────────────────────────────────────

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.controller});

  final BleScannerController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.devices;
    final iBeacons = items.where((d) => d.isIBeacon).length;
    final t1 = items.where((d) => d.isT1).length;
    final resolved = items.where((d) => d.isResolved).length;

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.status,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white54),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (controller.error != null)
            Text(
              controller.error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.orangeAccent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Chip('Всего', '${items.length}', Colors.white70),
                const SizedBox(width: 6),
                _Chip('iBeacon', '$iBeacons', Colors.lightBlueAccent),
                const SizedBox(width: 6),
                _Chip('T1', '$t1', Colors.orangeAccent),
                const SizedBox(width: 6),
                _Chip('Расшифровано', '$resolved', Colors.greenAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF172554),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Radar tab
// ─────────────────────────────────────────────────────────────────────────────

class _RadarTab extends StatelessWidget {
  const _RadarTab({required this.devices, required this.scanning});

  final List<BeaconViewModel> devices;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Radar: square, up to 60 % of available height.
        Expanded(
          flex: 3,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: AspectRatio(
                aspectRatio: 1,
                child: RadarView(devices: devices, scanning: scanning),
              ),
            ),
          ),
        ),
        // Resolved TagID panel.
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            child: TagIdPanel(devices: devices),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List tab
// ─────────────────────────────────────────────────────────────────────────────

class _ListTab extends StatelessWidget {
  const _ListTab({required this.devices, required this.mode});

  final List<BeaconViewModel> devices;
  final T1ScanMode mode;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bluetooth_searching,
                  size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                'BLE-пакетов нет.\nЗапустите сканирование.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.white38),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      itemCount: devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _DeviceCard(item: devices[i], mode: mode),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device card (detailed view for the List tab)
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.item, required this.mode});

  final BeaconViewModel item;
  final T1ScanMode mode;

  @override
  Widget build(BuildContext context) {
    final borderColor = item.isResolved
        ? Colors.greenAccent
        : item.isT1
            ? Colors.orangeAccent
            : item.isIBeacon
                ? Colors.lightBlueAccent
                : Colors.white12;

    final title = shortDisplayName(
      fallback:
          item.iBeacon == null ? 'BLE device' : formatUuid(item.iBeacon!.uuid),
      preferred: item.deviceName,
    );

    final active = item.isActive;

    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                _ActivityBadge(active: active),
                const SizedBox(width: 8),
                Text(
                  '${item.rssi} dBm',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _badge(item.isResolved
                    ? 'T1 resolved'
                    : item.isT1
                        ? 'T1'
                        : item.isIBeacon
                            ? 'iBeacon'
                            : 'BLE'),
                if (item.operatorCode?.isNotEmpty == true)
                  _badge(item.operatorCode!),
                if (item.resolvedData != null)
                  _badge('Stop #${item.resolvedData!.tagId}'),
              ],
            ),
            const SizedBox(height: 10),
            if (item.resolvedData?.stopName != null)
              Text(
                item.resolvedData!.stopName!,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.greenAccent),
              ),
            if (item.note?.isNotEmpty == true) ...[
              if (item.resolvedData?.stopName != null)
                const SizedBox(height: 4),
              Text(
                item.note!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white54),
              ),
            ],
            const SizedBox(height: 8),
            if (item.radioMac != null) _kv('Radio MAC', item.radioMac!),
            _kv('Seen', _fmtTime(item.lastSeen)),
            if (item.lastInterval != null)
              _kv('Интервал посылки', _fmtInterval(item.lastInterval!)),
            if (item.iBeacon != null) ...[
              _kv('UUID', formatUuid(item.iBeacon!.uuid)),
              _kv('Major / Minor',
                  '${item.iBeacon!.major} / ${item.iBeacon!.minor}'),
              _kv('Salt',
                  '0x${item.iBeacon!.major.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
              _kv('Device Hash',
                  '0x${item.iBeacon!.minor.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
              _kv('TX power', '${item.iBeacon!.txPower} dBm'),
              _kv('Scenario Type', '0x02'),
              _kv('Version', '0x15'),
              if (item.companyId != null)
                _kv('Device Type',
                    '0x${item.companyId!.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
            ],
            if (item.resolvedData != null) ...[
              _kv('Slot', '${item.resolvedData!.slot}'),
              _kv('Slot start', formatSlotStart(item.resolvedData!.slot, mode)),
              _kv('Derived MAC', item.resolvedData!.mac),
            ],
            if (item.companyId != null && item.iBeacon == null)
              _kv('Device Type',
                  '0x${item.companyId!.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
            _kv('Flags', item.connectable ? 'Connectable' : 'Non-connectable'),
            if (item.serviceUuids.isNotEmpty)
              _kv('Services', item.serviceUuids.join(', ')),
            if (item.rawMfrHex != null) _kv('Raw data', item.rawMfrHex!),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(l.hour)}:${p(l.minute)}:${p(l.second)}';
  }

  String _fmtInterval(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '$ms мс';
    return '${(ms / 1000.0).toStringAsFixed(1)} сек';
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(key,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity badge
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityBadge extends StatelessWidget {
  const _ActivityBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.greenAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Активна' : 'Нет сигнала',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
