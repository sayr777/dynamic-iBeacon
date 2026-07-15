import 'package:flutter_test/flutter_test.dart';
import 'package:t1_ble_scanner/src/models/beacon_view_model.dart';

void main() {
  group('BeaconViewModel.isActive', () {
    test('true when lastSeen < 30 seconds ago', () {
      final vm = BeaconViewModel(
        id: 'dev:AA:BB:CC',
        rssi: -70,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 10)),
      );
      expect(vm.isActive, isTrue);
    });

    test('false when lastSeen == 30 seconds ago', () {
      final vm = BeaconViewModel(
        id: 'dev:AA:BB:CC',
        rssi: -70,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      expect(vm.isActive, isFalse);
    });

    test('false when lastSeen > 30 seconds ago', () {
      final vm = BeaconViewModel(
        id: 'dev:AA:BB:CC',
        rssi: -70,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 60)),
      );
      expect(vm.isActive, isFalse);
    });

    test('true when lastSeen is exactly now', () {
      final vm = BeaconViewModel(
        id: 'dev:AA:BB:CC',
        rssi: -70,
        lastSeen: DateTime.now(),
      );
      expect(vm.isActive, isTrue);
    });
  });

  group('BeaconViewModel.copyWith', () {
    late BeaconViewModel base;

    setUp(() {
      base = BeaconViewModel(
        id: 'ib:uuid:1:2',
        rssi: -80,
        lastSeen: DateTime(2024, 1, 1, 12, 0, 0),
        lastInterval: const Duration(seconds: 2),
        iBeacon: const IBeaconFrame(
          uuid: 'fda50693-a4e2-4fb1-afcf-c6eb07647825',
          major: 100,
          minor: 200,
          txPower: -59,
        ),
      );
    });

    test('preserves lastInterval when not specified (sentinel)', () {
      final copy = base.copyWith(rssi: -75);
      expect(copy.lastInterval, equals(const Duration(seconds: 2)));
    });

    test('clears lastInterval when explicitly set to null', () {
      final copy = base.copyWith(lastInterval: null);
      expect(copy.lastInterval, isNull);
    });

    test('updates lastInterval when new value provided', () {
      final copy = base.copyWith(lastInterval: const Duration(seconds: 5));
      expect(copy.lastInterval, equals(const Duration(seconds: 5)));
    });

    test('preserves id field (immutable)', () {
      final copy = base.copyWith(rssi: -99);
      expect(copy.id, equals(base.id));
    });

    test('updates rssi', () {
      final copy = base.copyWith(rssi: -55);
      expect(copy.rssi, equals(-55));
    });
  });

  group('BeaconViewModel interval semantics', () {
    test('first packet has null interval', () {
      final vm = BeaconViewModel(
        id: 'dev:11:22:33',
        rssi: -65,
        lastSeen: DateTime.now(),
        lastInterval: null,
      );
      expect(vm.lastInterval, isNull);
    });

    test('second packet has real interval', () {
      final t0 = DateTime(2024, 6, 1, 10, 0, 0);
      final t1 = DateTime(2024, 6, 1, 10, 0, 2); // 2 seconds later

      // Simulate: first packet stored existing entry
      final existing = BeaconViewModel(
        id: 'dev:11:22:33',
        rssi: -65,
        lastSeen: t0,
        lastInterval: null,
      );

      // Simulate: second packet computation
      final interval = t1.difference(existing.lastSeen);
      final vm = BeaconViewModel(
        id: 'dev:11:22:33',
        rssi: -66,
        lastSeen: t1,
        lastInterval: interval,
      );

      expect(vm.lastInterval, equals(const Duration(seconds: 2)));
    });

    test('interval < 10 ms is treated as artefact (not stored)', () {
      // Simulates the T1 key-change artefact: diff ≈ 0 ms
      final t0 = DateTime(2024, 6, 1, 10, 0, 0);
      final t1 = t0.add(const Duration(milliseconds: 3));

      final diff = t1.difference(t0);
      // Controller skips diff < 10 ms (artefact from ib:...→t1:... key change)
      expect(diff.inMilliseconds >= 10, isFalse);
    });

    test('interval >= 10 ms is valid and stored', () {
      final t0 = DateTime(2024, 6, 1, 10, 0, 0);
      final t1 = t0.add(const Duration(milliseconds: 500));

      final diff = t1.difference(t0);
      expect(diff.inMilliseconds >= 10, isTrue);
    });
  });

  group('IBeaconFrame', () {
    test('stores all fields correctly', () {
      const frame = IBeaconFrame(
        uuid: 'fda50693-a4e2-4fb1-afcf-c6eb07647825',
        major: 0x20CD,
        minor: 0xF4A0,
        txPower: -59,
      );
      expect(frame.uuid, 'fda50693-a4e2-4fb1-afcf-c6eb07647825');
      expect(frame.major, 0x20CD);
      expect(frame.minor, 0xF4A0);
      expect(frame.txPower, -59);
    });
  });
}
