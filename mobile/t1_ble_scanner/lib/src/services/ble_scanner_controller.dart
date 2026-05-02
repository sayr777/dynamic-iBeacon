import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_config.dart';
import '../models/beacon_view_model.dart';
import '../utils/beacon_utils.dart';
import 't1_crypto.dart';

class BleScannerController extends ChangeNotifier {
  BleScannerController({
    FlutterReactiveBle? ble,
  }) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  AppConfig? _config;
  T1LookupSettings? _activeSettings;
  Map<String, T1LookupEntry> _lookupTable = const {};
  final LinkedHashMap<String, BeaconViewModel> _devices = LinkedHashMap<String, BeaconViewModel>();

  bool _initializing = true;
  bool _scanning = false;
  String _status = 'Загрузка локальной конфигурации...';
  String? _error;

  bool get initializing => _initializing;
  bool get scanning => _scanning;
  String get status => _status;
  String? get error => _error;
  AppConfig? get config => _config;
  BleStatus get bleStatus => _ble.status;
  Stream<BleStatus> get bleStatusStream => _ble.statusStream;
  T1LookupSettings? get activeSettings => _activeSettings;
  List<BeaconViewModel> get devices => _devices.values.toList(growable: false)
    ..sort((a, b) {
      if (a.isResolved != b.isResolved) return a.isResolved ? -1 : 1;
      if (a.isT1 != b.isT1) return a.isT1 ? -1 : 1;
      if (a.isIBeacon != b.isIBeacon) return a.isIBeacon ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });

  Future<void> initialize() async {
    try {
      _config = await AppConfig.load();
      _status = 'Конфигурация загружена. Готов к локальному сканированию.';
      _error = null;
    } catch (error) {
      _status = 'Не удалось загрузить локальную конфигурацию.';
      _error = error.toString();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> startScan({
    required T1LookupSettings settings,
  }) async {
    if (_config == null || _scanning) return;

    _activeSettings = settings;
    _error = null;

    final granted = await _ensurePermissions();
    if (!granted) {
      _status = 'Нет разрешений BLE. Разрешите сканирование и повторите.';
      notifyListeners();
      return;
    }

    try {
      _status = 'Подготовка локальной таблицы T1...';
      notifyListeners();

      _lookupTable = await T1Decoder.buildLookupTable(settings);
      _status = _lookupTable.isEmpty
          ? 'Сканирование BLE без дешифровки T1'
          : 'Сканирование BLE с локальной дешифровкой T1';

      _scanSubscription = _ble
          .scanForDevices(
            withServices: const <Uuid>[],
            scanMode: ScanMode.lowLatency,
          )
          .listen(_handleScanResult, onError: (Object error) {
        _error = error.toString();
        _status = 'Ошибка сканирования BLE';
        _scanning = false;
        notifyListeners();
      });

      _scanning = true;
      notifyListeners();
    } on FormatException catch (error) {
      _status = 'Неверный T1 KEY';
      _error = error.message;
      _scanning = false;
      notifyListeners();
    } catch (error) {
      _status = 'Не удалось запустить BLE-сканирование';
      _error = error.toString();
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanning = false;
    _status = 'Сканирование остановлено';
    notifyListeners();
  }

  void clearDevices() {
    _devices.clear();
    notifyListeners();
  }

  Future<bool> _ensurePermissions() async {
    if (Platform.isAndroid) {
      final permissions = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];
      final statuses = await permissions.request();
      return statuses.values.every((status) => status.isGranted);
    }

    if (Platform.isIOS) {
      final statuses = await <Permission>[
        Permission.bluetooth,
      ].request();
      return statuses.values.every((status) => status.isGranted);
    }

    return true;
  }

  void _handleScanResult(DiscoveredDevice device) {
    final iBeacon = _parseIBeacon(device.manufacturerData);
    final key = iBeacon != null
        ? 'ib:${iBeacon.uuid}:${iBeacon.major}:${iBeacon.minor}'
        : 'dev:${device.id}';

    final operator = iBeacon == null ? null : _config?.operatorsByUuid[iBeacon.uuid];
    final isT1 = operator?.scope == OperatorScope.local;
    T1ResolvedData? resolvedData;
    var note = '';
    var resolved = false;

    if (isT1 && iBeacon != null) {
      final lookup = _lookupTable['${iBeacon.major}:${iBeacon.minor}'];
      if (lookup != null) {
        resolved = true;
        resolvedData = T1ResolvedData(
          tagId: lookup.tagId,
          slot: lookup.slot,
          mac: lookup.mac,
          stopName: _config?.stops[lookup.tagId],
        );
        note = resolvedData.stopName == null
            ? 'T1: номер остановки расшифрован, но не найден в справочнике'
            : 'T1: остановка расшифрована локально';
      } else {
        note = 'T1: пакет распознан по UUID, но не дешифрован текущим ключом/слотом';
      }
    } else if (iBeacon != null && operator != null) {
      note = 'iBeacon известного внешнего оператора';
    } else if (iBeacon != null) {
      note = 'Неизвестный iBeacon';
    } else {
      note = 'BLE устройство без iBeacon payload';
    }

    _devices[key] = BeaconViewModel(
      id: key,
      deviceName: device.name.isEmpty ? null : device.name,
      rssi: device.rssi,
      lastSeen: DateTime.now(),
      iBeacon: iBeacon,
      operatorName: operator?.name,
      operatorCode: operator?.code,
      isT1: isT1,
      isResolved: resolved,
      note: note,
      resolvedData: resolvedData,
    );

    notifyListeners();
  }

  IBeaconFrame? _parseIBeacon(List<int> manufacturerData) {
    if (manufacturerData.length < 25) return null;
    if (manufacturerData[0] != 0x4C || manufacturerData[1] != 0x00) return null;
    if (manufacturerData[2] != 0x02 || manufacturerData[3] != 0x15) return null;

    final uuid = bytesToHex(manufacturerData.sublist(4, 20));
    final major = (manufacturerData[20] << 8) | manufacturerData[21];
    final minor = (manufacturerData[22] << 8) | manufacturerData[23];
    final txPowerRaw = manufacturerData[24];
    final txPower = txPowerRaw > 127 ? txPowerRaw - 256 : txPowerRaw;

    return IBeaconFrame(
      uuid: uuid,
      major: major,
      minor: minor,
      txPower: txPower,
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }
}
