import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/beacon_view_model.dart';
import '../services/ble_scanner_controller.dart';
import '../services/t1_crypto.dart';
import '../utils/beacon_utils.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late final BleScannerController _controller;
  late final TextEditingController _keyController;
  late final TextEditingController _tagMaxController;
  late final TextEditingController _prodWindowController;
  late final TextEditingController _protoSlotMaxController;
  T1ScanMode _scanMode = T1ScanMode.production;
  StreamSubscription<BluetoothAdapterState>? _bleStatusSub;

  @override
  void initState() {
    super.initState();
    _controller = BleScannerController()..addListener(_onControllerChanged);
    _keyController = TextEditingController();
    _tagMaxController = TextEditingController();
    _prodWindowController = TextEditingController();
    _protoSlotMaxController = TextEditingController();
    _controller.initialize();

    // Когда Bluetooth включается — автоматически закрываем диалог
    _bleStatusSub = _controller.bleAdapterStateStream.listen((state) {
      if (state == BluetoothAdapterState.on && mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      }
    });
  }

  void _onControllerChanged() {
    final defaults = _controller.config?.defaults;
    if (defaults == null) return;
    if (_keyController.text.isEmpty) {
      _keyController.text = defaults.keyHex;
      _tagMaxController.text = defaults.tagMax.toString();
      _prodWindowController.text = defaults.productionSlotWindow.toString();
      _protoSlotMaxController.text = defaults.prototypeSlotMax.toString();
    }
  }

  @override
  void dispose() {
    _bleStatusSub?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _keyController.dispose();
    _tagMaxController.dispose();
    _prodWindowController.dispose();
    _protoSlotMaxController.dispose();
    super.dispose();
  }

  Future<void> _requestBluetooth() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Bluetooth выключен'),
          ],
        ),
        content: const Text(
          'Для сканирования BLE-меток необходимо включить Bluetooth.\n\n'
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

  Future<void> _toggleScan() async {
    if (_controller.scanning) {
      await _controller.stopScan();
      return;
    }

    // Проверить статус Bluetooth перед запуском
    if (_controller.bleAdapterState != BluetoothAdapterState.on) {
      await _requestBluetooth();
      if (_controller.bleAdapterState != BluetoothAdapterState.on) return;
    }

    final settings = T1LookupSettings(
      keyHex: _keyController.text.trim(),
      mode: _scanMode,
      maxTagId: int.tryParse(_tagMaxController.text.trim()) ?? 100,
      productionSlotWindow: int.tryParse(_prodWindowController.text.trim()) ?? 5,
      prototypeSlotMax: int.tryParse(_protoSlotMaxController.text.trim()) ?? 1000,
    );
    await _controller.startScan(settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('T1 BLE Scanner'),
            centerTitle: false,
            actions: [
              IconButton(
                onPressed: _controller.clearDevices,
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Очистить список',
              ),
            ],
          ),
          body: _controller.initializing
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildSettingsCard(context),
                        const SizedBox(height: 12),
                        _buildStatusCard(context),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _buildDeviceList(context),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSettingsCard(BuildContext context) {
    final config = _controller.config;
    final local = config?.localOperator;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Локальная конфигурация',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Офлайн-режим: все справочники лежат в assets, сетевые вызовы не используются.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (local != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(label: 'T1 UUID', value: formatUuid(local.uuid)),
                  _InfoChip(label: 'T1 код', value: local.code),
                  _InfoChip(label: 'Остановок', value: '${config?.stops.length ?? 0}'),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'AES-128 KEY для T1',
                helperText: 'Используется только для локальной дешифровки T1',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<T1ScanMode>(
              initialValue: _scanMode,
              decoration: const InputDecoration(
                labelText: 'Режим T1',
              ),
              items: T1ScanMode.values
                  .map(
                    (mode) => DropdownMenuItem<T1ScanMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (mode) {
                if (mode == null) return;
                setState(() => _scanMode = mode);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'TagID до',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _scanMode == T1ScanMode.production
                        ? _prodWindowController
                        : _protoSlotMaxController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _scanMode == T1ScanMode.production ? 'Слоты ±' : 'Слоты 0..',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _toggleScan,
                icon: Icon(_controller.scanning ? Icons.stop_circle_outlined : Icons.bluetooth_searching),
                label: Text(_controller.scanning ? 'Остановить сканирование' : 'Начать сканирование'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final items = _controller.devices;
    final iBeacons = items.where((device) => device.isIBeacon).length;
    final t1 = items.where((device) => device.isT1).length;
    final resolved = items.where((device) => device.isResolved).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _controller.status,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_controller.error != null) ...[
              const SizedBox(height: 6),
              Text(
                _controller.error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orangeAccent),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: 'Всего', value: '${items.length}'),
                _InfoChip(label: 'iBeacon', value: '$iBeacons'),
                _InfoChip(label: 'T1', value: '$t1'),
                _InfoChip(label: 'Дешифровано', value: '$resolved'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(BuildContext context) {
    final items = _controller.devices;
    if (items.isEmpty) {
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'BLE-пакетов пока нет. Запустите сканирование рядом с метками.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _DeviceCard(
          item: item,
          mode: _controller.activeSettings?.mode ?? T1ScanMode.production,
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.item,
    required this.mode,
  });

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
      fallback: item.iBeacon == null ? 'BLE device' : formatUuid(item.iBeacon!.uuid),
      preferred: item.deviceName,
    );

    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${item.rssi} dBm',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _badge(item.isResolved ? 'T1 resolved' : item.isT1 ? 'T1' : item.isIBeacon ? 'iBeacon' : 'BLE'),
                if (item.operatorCode != null && item.operatorCode!.isNotEmpty) _badge(item.operatorCode!),
                if (item.resolvedData != null) _badge('Stop #${item.resolvedData!.tagId}'),
              ],
            ),
            const SizedBox(height: 10),
            if (item.resolvedData?.stopName != null)
              Text(
                item.resolvedData!.stopName!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.greenAccent),
              ),
            if (item.note != null && item.note!.isNotEmpty) ...[
              if (item.resolvedData?.stopName != null) const SizedBox(height: 6),
              Text(
                item.note!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 10),
            _kv('Seen', item.lastSeen.toIso8601String()),
            if (item.iBeacon != null) ...[
              _kv('UUID', formatUuid(item.iBeacon!.uuid)),
              _kv('Major / Minor', '${item.iBeacon!.major} / ${item.iBeacon!.minor}'),
              _kv('TX power', '${item.iBeacon!.txPower} dBm'),
            ],
            if (item.resolvedData != null) ...[
              _kv('Slot', '${item.resolvedData!.slot}'),
              _kv('Slot start', formatSlotStart(item.resolvedData!.slot, mode)),
              _kv('Derived MAC', item.resolvedData!.mac),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              key,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF172554),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white70),
            ),
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
