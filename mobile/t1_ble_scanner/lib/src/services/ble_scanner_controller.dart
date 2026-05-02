import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_config.dart';
import '../models/beacon_view_model.dart';
import '../utils/beacon_utils.dart';
import 't1_crypto.dart';

class BleScannerController extends ChangeNotifier {
  BleScannerController();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  AppConfig? _config;
  T1LookupSettings? _activeSettings;
  Map<String, T1LookupEntry> _lookupTable = const {};
  final LinkedHashMap<String, BeaconViewModel> _devices =
      LinkedHashMap<String, BeaconViewModel>();

  bool _initializing = true;
  bool _scanning = false;
  String _status = 'Загрузка локальной конфигурации...';
  String? _error;

  bool get initializing => _initializing;
  bool get scanning => _scanning;
  String get status => _status;
  String? get error => _error;
  AppConfig? get config => _config;

  /// Текущее состояние BLE-адаптера.
  BluetoothAdapterState get bleAdapterState => FlutterBluePlus.adapterStateNow;

  /// Стрим изменений состояния BLE-адаптера.
  Stream<BluetoothAdapterState> get bleAdapterStateStream =>
      FlutterBluePlus.adapterState;

  T1LookupSettings? get activeSettings => _activeSettings;

  List<BeaconViewModel> get devices =>
      _devices.values.toList(growable: false)
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

  Future<void> startScan({required T1LookupSettings settings}) async {
    if (_config == null || _scanning) return;

    _activeSettings = settings;
    _error = null;

    debugPrint('[T1] startScan called, adapterState=${FlutterBluePlus.adapterStateNow}');

    final granted = await _ensurePermissions();
    debugPrint('[T1] permissions granted=$granted');
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

      debugPrint('[T1] Starting BLE scan (flutter_blue_plus)...');

      // flutter_blue_plus: allowDuplicates=true — получаем обновления при
      // каждом пакете, даже если MAC не менялся.
      // androidUsesFineLocation=true — нужно для сканирования на всех версиях Android.
      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final r in results) {
            _handleScanResult(r);
          }
          _status = 'Сканирование — пакетов: ${_devices.length}';
          notifyListeners();
        },
        onError: (Object error) {
          debugPrint('[T1] Scan error: $error');
          _error = error.toString();
          _status = 'Ошибка сканирования BLE';
          _scanning = false;
          notifyListeners();
        },
      );

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
    await FlutterBluePlus.stopScan();
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
      // Xiaomi HyperOS требует Location даже на Android 12+
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final allGranted =
          statuses.values.every((s) => s.isGranted || s.isLimited);

      if (!allGranted) {
        final denied = statuses.entries
            .where((e) => !e.value.isGranted && !e.value.isLimited)
            .map((e) => e.key.toString())
            .join(', ');
        _status = 'Нет разрешений: $denied';
        notifyListeners();
      }

      return allGranted;
    }

    if (Platform.isIOS) {
      final statuses = await <Permission>[Permission.bluetooth].request();
      return statuses.values.every((s) => s.isGranted);
    }

    return true;
  }

  void _handleScanResult(ScanResult result) {
    final advData = result.advertisementData;
    final mfrMap = advData.manufacturerData;

    // flutter_blue_plus возвращает manufacturerData как Map<int, List<int>>,
    // где ключ = Company ID (int), значение = данные БЕЗ company ID.
    // Для iBeacon: key=0x004C, value=[0x02, 0x15, UUID(16), major(2), minor(2), txPower]
    List<int>? mfrBytes;
    int? companyId;
    if (mfrMap.isNotEmpty) {
      companyId = mfrMap.keys.first;
      mfrBytes = mfrMap.values.first;
      final mfrHex =
          mfrBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      debugPrint(
          '[T1] ${result.device.remoteId} rssi=${result.rssi} '
          'company=0x${companyId.toRadixString(16).padLeft(4, "0")} '
          'mfr=${mfrBytes.length}b [$mfrHex]');
    } else {
      debugPrint(
          '[T1] ${result.device.remoteId} rssi=${result.rssi} mfr=0b []');
    }

    final iBeacon = _parseIBeacon(companyId, mfrBytes);
    final deviceId = result.device.remoteId.str;
    final key = iBeacon != null
        ? 'ib:${iBeacon.uuid}:${iBeacon.major}:${iBeacon.minor}'
        : 'dev:$deviceId';

    final operator =
        iBeacon == null ? null : _config?.operatorsByUuid[iBeacon.uuid];
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

    final name = advData.advName.isNotEmpty
        ? advData.advName
        : result.device.platformName.isNotEmpty
            ? result.device.platformName
            : null;

    _devices[key] = BeaconViewModel(
      id: key,
      deviceName: name,
      rssi: result.rssi,
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

  /// Парсит iBeacon из данных flutter_blue_plus.
  ///
  /// flutter_blue_plus возвращает manufacturerData как Map<int, List<int>>:
  ///   - companyId: Company ID (напр. 0x004C для Apple)
  ///   - data: байты БЕЗ company ID → [0x02, 0x15, UUID(16), major(2), minor(2), txPower]
  ///
  /// Также поддерживаем старый формат с company ID включённым в начале.
  IBeaconFrame? _parseIBeacon(int? companyId, List<int>? data) {
    if (data == null || data.isEmpty) return null;

    int base; // индекс байта 0x02 (iBeacon subtype) в data

    if (companyId == 0x004C && data.length >= 23 &&
        data[0] == 0x02 && data[1] == 0x15) {
      // flutter_blue_plus формат: company ID отдельно, data = [0x02 0x15 ...]
      base = 0;
    } else if (data.length >= 25 &&
        data[0] == 0x4C && data[1] == 0x00 &&
        data[2] == 0x02 && data[3] == 0x15) {
      // Формат с company ID включённым в data (совместимость)
      base = 2;
    } else if (data.length >= 23 &&
        data[0] == 0x02 && data[1] == 0x15) {
      // Любой производитель, iBeacon subtype
      base = 0;
    } else {
      return null;
    }

    if (data.length < base + 23) return null;

    final uuid = bytesToHex(data.sublist(base + 2, base + 18));
    final major = (data[base + 18] << 8) | data[base + 19];
    final minor = (data[base + 20] << 8) | data[base + 21];
    final txPowerRaw = data[base + 22];
    final txPower = txPowerRaw > 127 ? txPowerRaw - 256 : txPowerRaw;

    debugPrint('[T1] iBeacon: uuid=$uuid '
        'major=0x${major.toRadixString(16)} '
        'minor=0x${minor.toRadixString(16)} '
        'tx=$txPower');

    return IBeaconFrame(uuid: uuid, major: major, minor: minor, txPower: txPower);
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}
