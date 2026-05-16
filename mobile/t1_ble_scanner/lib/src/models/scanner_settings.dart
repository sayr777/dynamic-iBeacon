import '../services/t1_crypto.dart';
import '../utils/beacon_utils.dart';
import 'app_config.dart';

class ScannerSettings {
  const ScannerSettings({
    required this.keyHex,
    required this.mode,
    required this.maxTagId,
    required this.productionSlotWindow,
    required this.prototypeSlotMax,
  });

  final String keyHex;
  final T1ScanMode mode;
  final int maxTagId;
  final int productionSlotWindow;
  final int prototypeSlotMax;

  factory ScannerSettings.fromDefaults(ScanDefaults defaults) {
    return ScannerSettings(
      keyHex: defaults.keyHex,
      mode: T1ScanMode.production,
      maxTagId: defaults.tagMax,
      productionSlotWindow: defaults.productionSlotWindow,
      prototypeSlotMax: defaults.prototypeSlotMax,
    );
  }

  ScannerSettings copyWith({
    String? keyHex,
    T1ScanMode? mode,
    int? maxTagId,
    int? productionSlotWindow,
    int? prototypeSlotMax,
  }) {
    return ScannerSettings(
      keyHex: keyHex ?? this.keyHex,
      mode: mode ?? this.mode,
      maxTagId: maxTagId ?? this.maxTagId,
      productionSlotWindow: productionSlotWindow ?? this.productionSlotWindow,
      prototypeSlotMax: prototypeSlotMax ?? this.prototypeSlotMax,
    );
  }

  T1LookupSettings toLookupSettings() {
    return T1LookupSettings(
      keyHex: keyHex,
      mode: mode,
      maxTagId: maxTagId,
      productionSlotWindow: productionSlotWindow,
      prototypeSlotMax: prototypeSlotMax,
    );
  }
}
