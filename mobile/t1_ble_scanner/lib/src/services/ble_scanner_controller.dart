import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_config.dart';
import '../models/beacon_view_model.dart';
import '../utils/beacon_utils.dart';
import 't1_crypto.dart';
import 'operators_repository.dart';
import 'stops_repository.dart';

class BleScannerController extends ChangeNotifier {
  BleScannerController();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<bool>? _isScanningSubscription;
  Timer? _notifyDebounce;
  Timer? _scanRestartTimer;

  AppConfig? _config;
  StopsRepository? _stopsRepo;
  OperatorsRepository? _operatorsRepo;
  T1LookupSettings? _activeSettings;
  final Map<String, T1LookupEntry> _resolvedT1Cache = {};
  final Set<String> _resolvingT1Keys = <String>{};
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

  /// Attaches a [StopsRepository] so the controller picks up live name changes.
  void attachStopsRepository(StopsRepository repo) {
    _stopsRepo?.removeListener(_onStopsChanged);
    _stopsRepo = repo;
    repo.addListener(_onStopsChanged);
  }

  /// Attaches an [OperatorsRepository] to resolve custom UUID operators.
  void attachOperatorsRepository(OperatorsRepository repo) {
    _operatorsRepo?.removeListener(_onOperatorsChanged);
    _operatorsRepo = repo;
    repo.addListener(_onOperatorsChanged);
  }

  /// Called when operators change — re-classifies visible non-T1 iBeacon devices.
  void _onOperatorsChanged() {
    var changed = false;
    for (final key in _devices.keys.toList()) {
      final vm = _devices[key];
      if (vm == null || vm.isT1 || vm.iBeacon == null) continue;
      final uuid = vm.iBeacon!.uuid;
      final op = _operatorsRepo?.getByUuid(uuid);
      final newColor = op?.colorValue;
      if (newColor == vm.operatorColor &&
          op?.name == vm.operatorName &&
          op?.code == vm.operatorCode) {
        continue;
      }
      _devices[key] = vm.copyWith(
        operatorColor: newColor,
        operatorName: op?.name,
        operatorCode: op?.code,
        note: op != null ? 'iBeacon оператора «${op.name}»' : 'Неизвестный iBeacon',
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Looks up a stop name: custom entries override config defaults.
  String? _stopName(int tagId) =>
      _stopsRepo?.getName(tagId) ?? _config?.stops[tagId];

  /// Called when stops directory changes — refreshes names in resolved devices.
  void _onStopsChanged() {
    var changed = false;
    for (final key in _devices.keys.toList()) {
      final vm = _devices[key];
      if (vm == null || !vm.isResolved || vm.resolvedData == null) continue;
      final tagId = vm.resolvedData!.tagId;
      final newName = _stopName(tagId);
      if (newName == vm.resolvedData!.stopName) continue;
      _devices[key] = vm.copyWith(
        note: newName == null
            ? 'T1: номер остановки расшифрован, но не найден в справочнике'
            : 'T1: остановка расшифрована локально',
        resolvedData: T1ResolvedData(
          tagId: tagId,
          slot: vm.resolvedData!.slot,
          mac: vm.resolvedData!.mac,
          stopName: newName,
        ),
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  List<BeaconViewModel> get devices => _devices.values.toList(growable: false)
    ..sort((a, b) {
      if (a.isResolved != b.isResolved) return a.isResolved ? -1 : 1;
      if (a.isT1 != b.isT1) return a.isT1 ? -1 : 1;
      if (a.isIBeacon != b.isIBeacon) return a.isIBeacon ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });

  /// Debounced notify — coalesces rapid BLE packet bursts into one UI rebuild
  /// (max ~10 times/sec). This prevents jank when many devices are nearby.
  void _scheduleNotify() {
    if (_notifyDebounce?.isActive == true) return;
    _notifyDebounce = Timer(const Duration(milliseconds: 100), notifyListeners);
  }

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

    debugPrint(
        '[T1] startScan called, adapterState=${FlutterBluePlus.adapterStateNow}');

    final granted = await _ensurePermissions();
    debugPrint('[T1] permissions granted=$granted');
    if (!granted) {
      _status = 'Нет разрешений BLE. Разрешите сканирование и повторите.';
      notifyListeners();
      return;
    }

    _resolvedT1Cache.clear();
    _resolvingT1Keys.clear();
    _scanning = true;

    // Watch isScanning stream: if Android silently kills the scan while we
    // still think we're scanning, restart proactively.
    _isScanningSubscription?.cancel();
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((active) {
      if (!active && _scanning) {
        debugPrint('[T1] isScanning→false while _scanning=true — restarting');
        _scheduleRestart();
      }
    });

    await _startScanInternal();
  }

  /// Low-level: stops any existing scan/subscription, starts a new one, and
  /// arms the 25-minute proactive-restart timer. Does NOT touch _scanning.
  Future<void> _startScanInternal() async {
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    _notifyDebounce?.cancel();

    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    try {
      _status = 'Запуск BLE-сканирования...';
      notifyListeners();

      debugPrint('[T1] Starting BLE scan (flutter_blue_plus)...');

      // flutter_blue_plus: androidUsesFineLocation=true — нужно для сканирования
      // на всех версиях Android. lowLatency — максимальная частота пакетов.
      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
      );

      _status = 'Сканирование BLE запущено';

      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final r in results) {
            _handleScanResult(r);
          }
          // Update status once per batch — not inside the loop.
          _status = 'Сканирование — пакетов: ${_devices.length}';
          // Debounced: coalesces rapid bursts into one UI rebuild.
          _scheduleNotify();
        },
        onError: (Object error) {
          debugPrint('[T1] Scan error: $error');
          _error = error.toString();
          _status = 'Ошибка сканирования BLE';
          if (_scanning) {
            _scheduleRestart();
          }
        },
        onDone: () {
          // Android closed the stream — typically the 30-min OS kill.
          debugPrint('[T1] scanResults stream closed — restarting');
          if (_scanning) {
            _scheduleRestart();
          }
        },
      );

      // Proactive restart every 25 min — before Android's ~30-min silent kill.
      _scanRestartTimer = Timer(const Duration(minutes: 25), () {
        if (_scanning) {
          debugPrint('[T1] Proactive 25-min restart');
          _scheduleRestart();
        }
      });

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

  /// Restarts the scan loop after a brief pause (debounce duplicate triggers).
  /// Guards against restart loops when _scanning has already been cleared.
  bool _restarting = false;
  Future<void> _scheduleRestart() async {
    if (!_scanning || _restarting) return;
    _restarting = true;
    // Brief pause so the OS fully releases BLE resources before we restart.
    await Future<void>.delayed(const Duration(seconds: 2));
    _restarting = false;
    if (!_scanning) return; // user may have called stopScan during the delay
    _status = 'Перезапуск сканирования BLE...';
    notifyListeners();
    await _startScanInternal();
  }

  Future<void> stopScan() async {
    _scanning = false; // set first so in-flight restart guards bail out
    _restarting = false;
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    _isScanningSubscription?.cancel();
    _isScanningSubscription = null;
    _notifyDebounce?.cancel();
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _resolvedT1Cache.clear();
    _resolvingT1Keys.clear();
    _status = 'Сканирование остановлено';
    notifyListeners();
  }

  void clearDevices() {
    _devices.clear();
    // Clear resolution cache so T1 tags are re-resolved on the next packet.
    // Without this, slot-changed tags remain invisible after the list is cleared.
    _resolvedT1Cache.clear();
    _resolvingT1Keys.clear();
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
      if (kDebugMode) {
        final mfrHex =
            mfrBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        debugPrint('[T1] ${result.device.remoteId} rssi=${result.rssi} '
            'company=0x${companyId.toRadixString(16).padLeft(4, "0")} '
            'mfr=${mfrBytes.length}b [$mfrHex]');
      }
    }

    final iBeacon = _parseIBeacon(companyId, mfrBytes);
    final radioMac = result.device.remoteId.str;

    final configOperator =
        iBeacon == null ? null : _config?.operatorsByUuid[iBeacon.uuid];
    final isT1 = configOperator?.scope == OperatorScope.local;
    // For non-T1 iBeacons, look up in the operator registry (which covers
    // both config-origin and user-added operators, all with chosen colors).
    final registryOp =
        (iBeacon != null && !isT1) ? _operatorsRepo?.getByUuid(iBeacon.uuid) : null;
    T1ResolvedData? resolvedData;
    var note = '';
    var resolved = false;

    if (isT1 && iBeacon != null) {
      final lookupKey = '${iBeacon.major}:${iBeacon.minor}';
      final lookup = _resolvedT1Cache[lookupKey];
      if (lookup != null) {
        resolved = true;
        resolvedData = T1ResolvedData(
          tagId: lookup.tagId,
          slot: lookup.slot,
          mac: lookup.mac,
          stopName: _stopName(lookup.tagId),
        );
        note = resolvedData.stopName == null
            ? 'T1: номер остановки расшифрован, но не найден в справочнике'
            : 'T1: остановка расшифрована локально';
      } else {
        note = _resolvingT1Keys.contains(lookupKey)
            ? 'T1: локальная дешифровка выполняется...'
            : 'T1: пакет распознан по UUID, выполняется локальная дешифровка';
        _scheduleT1Resolution(
          lookupKey: lookupKey,
          frame: iBeacon,
        );
      }
    } else if (iBeacon != null && registryOp != null) {
      note = 'iBeacon оператора «${registryOp.name}»';
    } else if (iBeacon != null) {
      note = 'Неизвестный iBeacon';
    } else {
      note = 'BLE устройство без iBeacon payload';
    }

    // ── Key selection and deduplication ────────────────────────────────────
    // Resolved T1 entries are keyed by tagId so the same physical tag always
    // occupies the same slot regardless of slot rotation (major/minor change).
    // When a new resolved entry arrives, all stale unresolved T1 broadcasts
    // (from previous slots of the same or other dynamic tags) are removed.
    final String key;
    if (resolved && resolvedData != null) {
      key = 't1:${resolvedData.tagId}';
      // Remove ghost iBeacon entries from previous T1 slot broadcasts.
      _devices.removeWhere((k, v) => v.isT1 && !v.isResolved);
    } else if (iBeacon != null) {
      key = 'ib:${iBeacon.uuid}:${iBeacon.major}:${iBeacon.minor}';
    } else {
      key = 'dev:$radioMac';
    }

    final name = advData.advName.isNotEmpty
        ? advData.advName
        : result.device.platformName.isNotEmpty
            ? result.device.platformName
            : null;

    _devices[key] = BeaconViewModel(
      id: key,
      deviceName: name,
      radioMac: radioMac,
      rssi: result.rssi,
      lastSeen: DateTime.now(),
      iBeacon: iBeacon,
      operatorName: configOperator?.name ?? registryOp?.name,
      operatorCode: configOperator?.code ?? registryOp?.code,
      operatorColor: registryOp?.colorValue,
      isT1: isT1,
      isResolved: resolved,
      note: note,
      resolvedData: resolvedData,
    );
    // No notifyListeners() here — the stream listener batches all packets and
    // calls _scheduleNotify() once per scan cycle.
  }

  void _scheduleT1Resolution({
    required String lookupKey,
    required IBeaconFrame frame,
  }) {
    final settings = _activeSettings;
    if (settings == null || _resolvingT1Keys.contains(lookupKey)) {
      return;
    }

    _resolvingT1Keys.add(lookupKey);
    T1Decoder.resolveMajorMinor(settings, frame.major, frame.minor)
        .then((entry) {
      if (entry != null) {
        _resolvedT1Cache[lookupKey] = entry;
        final unresolvedKey = 'ib:${frame.uuid}:${frame.major}:${frame.minor}';
        final existing = _devices.remove(unresolvedKey);
        final stopName = _stopName(entry.tagId);

        _devices['t1:${entry.tagId}'] = BeaconViewModel(
          id: 't1:${entry.tagId}',
          deviceName: existing?.deviceName,
          radioMac: existing?.radioMac,
          rssi: existing?.rssi ?? -999,
          lastSeen: DateTime.now(),
          iBeacon: frame,
          operatorName: _config?.localOperator.name,
          operatorCode: _config?.localOperator.code,
          isT1: true,
          isResolved: true,
          note: stopName == null
              ? 'T1: номер остановки расшифрован, но не найден в справочнике'
              : 'T1: остановка расшифрована локально',
          resolvedData: T1ResolvedData(
            tagId: entry.tagId,
            slot: entry.slot,
            mac: entry.mac,
            stopName: stopName,
          ),
        );
      }
    }).catchError((Object error) {
      _error = error.toString();
    }).whenComplete(() {
      _resolvingT1Keys.remove(lookupKey);
      notifyListeners();
    });
  }

  /// Парсит iBeacon из данных flutter_blue_plus.
  ///
  /// flutter_blue_plus возвращает manufacturerData как Map(int, List(int)):
  ///   - companyId: Company ID (напр. 0x004C для Apple)
  ///   - data: байты БЕЗ company ID → [0x02, 0x15, UUID(16), major(2), minor(2), txPower]
  ///
  /// Также поддерживаем старый формат с company ID включённым в начале данных.
  IBeaconFrame? _parseIBeacon(int? companyId, List<int>? data) {
    if (data == null || data.isEmpty) return null;

    int base; // индекс байта 0x02 (iBeacon subtype) в data

    if (companyId == 0x004C &&
        data.length >= 23 &&
        data[0] == 0x02 &&
        data[1] == 0x15) {
      // flutter_blue_plus формат: company ID отдельно, data = [0x02 0x15 ...]
      base = 0;
    } else if (data.length >= 25 &&
        data[0] == 0x4C &&
        data[1] == 0x00 &&
        data[2] == 0x02 &&
        data[3] == 0x15) {
      // Формат с company ID включённым в data (совместимость)
      base = 2;
    } else if (data.length >= 23 && data[0] == 0x02 && data[1] == 0x15) {
      // Любой производитель, iBeacon subtype
      base = 0;
    } else {
      return null;
    }

    if (data.length < base + 23) return null;

    // normalizeUuid() в конфиге даёт lowercase — приводим к тому же регистру
    final uuid = bytesToHex(data.sublist(base + 2, base + 18)).toLowerCase();
    final major = (data[base + 18] << 8) | data[base + 19];
    final minor = (data[base + 20] << 8) | data[base + 21];
    final txPowerRaw = data[base + 22];
    final txPower = txPowerRaw > 127 ? txPowerRaw - 256 : txPowerRaw;

    if (kDebugMode) {
      debugPrint('[T1] iBeacon: uuid=$uuid '
          'major=0x${major.toRadixString(16)} '
          'minor=0x${minor.toRadixString(16)} '
          'tx=$txPower');
    }

    return IBeaconFrame(
        uuid: uuid, major: major, minor: minor, txPower: txPower);
  }

  @override
  void dispose() {
    _scanning = false;
    _restarting = false;
    _scanRestartTimer?.cancel();
    _isScanningSubscription?.cancel();
    _notifyDebounce?.cancel();
    _stopsRepo?.removeListener(_onStopsChanged);
    _operatorsRepo?.removeListener(_onOperatorsChanged);
    _adapterSub?.cancel();
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}
