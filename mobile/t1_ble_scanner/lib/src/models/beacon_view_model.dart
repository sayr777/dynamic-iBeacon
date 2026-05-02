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
    this.iBeacon,
    this.operatorName,
    this.operatorCode,
    this.isT1 = false,
    this.isResolved = false,
    this.note,
    this.resolvedData,
  });

  final String id;
  final String? deviceName;
  final int rssi;
  final DateTime lastSeen;
  final IBeaconFrame? iBeacon;
  final String? operatorName;
  final String? operatorCode;
  final bool isT1;
  final bool isResolved;
  final String? note;
  final T1ResolvedData? resolvedData;

  bool get isIBeacon => iBeacon != null;

  BeaconViewModel copyWith({
    String? deviceName,
    int? rssi,
    DateTime? lastSeen,
    IBeaconFrame? iBeacon,
    String? operatorName,
    String? operatorCode,
    bool? isT1,
    bool? isResolved,
    String? note,
    T1ResolvedData? resolvedData,
  }) {
    return BeaconViewModel(
      id: id,
      deviceName: deviceName ?? this.deviceName,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      iBeacon: iBeacon ?? this.iBeacon,
      operatorName: operatorName ?? this.operatorName,
      operatorCode: operatorCode ?? this.operatorCode,
      isT1: isT1 ?? this.isT1,
      isResolved: isResolved ?? this.isResolved,
      note: note ?? this.note,
      resolvedData: resolvedData ?? this.resolvedData,
    );
  }
}
