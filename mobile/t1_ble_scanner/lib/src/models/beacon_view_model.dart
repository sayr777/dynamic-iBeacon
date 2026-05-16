class IBeaconFrame {
  const IBeaconFrame({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.txPower,
  });

  final String uuid;
  final int major;
  final int minor;
  final int txPower;
}

class T1ResolvedData {
  const T1ResolvedData({
    required this.tagId,
    required this.slot,
    required this.mac,
    required this.stopName,
  });

  final int tagId;
  final int slot;
  final String mac;
  final String? stopName;
}

class BeaconViewModel {
  const BeaconViewModel({
    required this.id,
    required this.rssi,
    required this.lastSeen,
    this.deviceName,
    this.radioMac,
    this.iBeacon,
    this.operatorName,
    this.operatorCode,
    /// ARGB color for this operator's dot on the radar (null = no custom color).
    this.operatorColor,
    this.isT1 = false,
    this.isResolved = false,
    this.note,
    this.resolvedData,
  });

  final String id;
  final String? deviceName;
  /// Actual BLE radio MAC address (e.g. "CC:F6:DA:F6:36:F2").
  final String? radioMac;
  final int rssi;
  final DateTime lastSeen;
  final IBeaconFrame? iBeacon;
  final String? operatorName;
  final String? operatorCode;
  final int? operatorColor;
  final bool isT1;
  final bool isResolved;
  final String? note;
  final T1ResolvedData? resolvedData;

  bool get isIBeacon => iBeacon != null;

  /// True when a non-T1 operator has been matched and assigned a color.
  bool get isCustomOperator => operatorColor != null && !isT1;

  BeaconViewModel copyWith({
    String? deviceName,
    String? radioMac,
    int? rssi,
    DateTime? lastSeen,
    IBeaconFrame? iBeacon,
    String? operatorName,
    String? operatorCode,
    Object? operatorColor = _sentinel,
    bool? isT1,
    bool? isResolved,
    String? note,
    T1ResolvedData? resolvedData,
  }) {
    return BeaconViewModel(
      id: id,
      deviceName: deviceName ?? this.deviceName,
      radioMac: radioMac ?? this.radioMac,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      iBeacon: iBeacon ?? this.iBeacon,
      operatorName: operatorName ?? this.operatorName,
      operatorCode: operatorCode ?? this.operatorCode,
      operatorColor: identical(operatorColor, _sentinel)
          ? this.operatorColor
          : operatorColor as int?,
      isT1: isT1 ?? this.isT1,
      isResolved: isResolved ?? this.isResolved,
      note: note ?? this.note,
      resolvedData: resolvedData ?? this.resolvedData,
    );
  }
}

// Sentinel for nullable copyWith fields.
const _sentinel = Object();
