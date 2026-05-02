import '../utils/beacon_utils.dart';

class T1LookupSettings {
  const T1LookupSettings({
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
}

class T1LookupEntry {
  const T1LookupEntry({
    required this.tagId,
    required this.slot,
    required this.major,
    required this.minor,
    required this.mac,
  });

  final int tagId;
  final int slot;
  final int major;
  final int minor;
  final String mac;
}

class T1Decoder {
  static Future<Map<String, T1LookupEntry>> buildLookupTable(T1LookupSettings settings) async {
    final key = parseHexKey(settings.keyHex);
    final table = <String, T1LookupEntry>{};
    final slots = _buildSlots(settings);

    for (var tagId = 0; tagId <= settings.maxTagId; tagId++) {
      for (final slot in slots) {
        final block = List<int>.filled(16, 0, growable: false);
        block[0] = (tagId >> 8) & 0xFF;
        block[1] = tagId & 0xFF;
        block[2] = (slot >> 24) & 0xFF;
        block[3] = (slot >> 16) & 0xFF;
        block[4] = (slot >> 8) & 0xFF;
        block[5] = slot & 0xFF;

        final out = _aes128EncryptBlock(key, block);
        final major = (out[0] << 8) | out[1];
        final minor = (out[2] << 8) | out[3];
        final mac = formatMac(<int>[
          out[4] | 0xC0,
          out[5],
          out[6],
          out[7],
          out[8],
          out[9],
        ]);
        table['$major:$minor'] = T1LookupEntry(
          tagId: tagId,
          slot: slot,
          major: major,
          minor: minor,
          mac: mac,
        );
      }
      if (tagId % 25 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return table;
  }

  static List<int> _buildSlots(T1LookupSettings settings) {
    if (settings.mode == T1ScanMode.prototype) {
      return List<int>.generate(settings.prototypeSlotMax + 1, (index) => index, growable: false);
    }
    final nowSlot = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 300;
    final from = nowSlot > settings.productionSlotWindow
        ? nowSlot - settings.productionSlotWindow
        : 0;
    final to = nowSlot + settings.productionSlotWindow;
    return List<int>.generate(to - from + 1, (index) => from + index, growable: false);
  }

  static List<int> _aes128EncryptBlock(List<int> key, List<int> block) {
    final roundKeys = _expandKey(key);
    final state = List<int>.generate(16, (index) => block[index] ^ roundKeys[index], growable: false);

    for (var round = 1; round <= 10; round++) {
      for (var i = 0; i < 16; i++) {
        state[i] = _sbox[state[i]];
      }

      _shiftRows(state);

      if (round < 10) {
        _mixColumns(state);
      }

      final offset = round * 16;
      for (var i = 0; i < 16; i++) {
        state[i] ^= roundKeys[offset + i];
      }
    }
    return state;
  }

  static List<int> _expandKey(List<int> key) {
    final expanded = List<int>.from(key, growable: true);
    const rcon = <int>[0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36];

    for (var wordIndex = 4; wordIndex < 44; wordIndex++) {
      var temp = expanded.sublist((wordIndex - 1) * 4, wordIndex * 4);
      if (wordIndex % 4 == 0) {
        temp = <int>[
          _sbox[temp[1]] ^ rcon[(wordIndex ~/ 4) - 1],
          _sbox[temp[2]],
          _sbox[temp[3]],
          _sbox[temp[0]],
        ];
      }
      for (var j = 0; j < 4; j++) {
        expanded.add(expanded[(wordIndex - 4) * 4 + j] ^ temp[j]);
      }
    }

    return expanded;
  }

  static void _shiftRows(List<int> state) {
    final s1 = state[1];
    state[1] = state[5];
    state[5] = state[9];
    state[9] = state[13];
    state[13] = s1;

    final s2 = state[2];
    final s6 = state[6];
    state[2] = state[10];
    state[6] = state[14];
    state[10] = s2;
    state[14] = s6;

    final s3 = state[3];
    state[3] = state[15];
    state[15] = state[11];
    state[11] = state[7];
    state[7] = s3;
  }

  static void _mixColumns(List<int> state) {
    for (var column = 0; column < 4; column++) {
      final offset = column * 4;
      final a0 = state[offset];
      final a1 = state[offset + 1];
      final a2 = state[offset + 2];
      final a3 = state[offset + 3];

      state[offset] = _gmul(2, a0) ^ _gmul(3, a1) ^ a2 ^ a3;
      state[offset + 1] = a0 ^ _gmul(2, a1) ^ _gmul(3, a2) ^ a3;
      state[offset + 2] = a0 ^ a1 ^ _gmul(2, a2) ^ _gmul(3, a3);
      state[offset + 3] = _gmul(3, a0) ^ a1 ^ a2 ^ _gmul(2, a3);
    }
  }

  static int _gmul(int a, int b) {
    var x = a;
    var y = b;
    var p = 0;
    for (var i = 0; i < 8; i++) {
      if ((y & 1) != 0) {
        p ^= x;
      }
      final hiBit = x & 0x80;
      x = (x << 1) & 0xFF;
      if (hiBit != 0) {
        x ^= 0x1B;
      }
      y >>= 1;
    }
    return p;
  }

  static const List<int> _sbox = <int>[
    0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
    0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
    0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
    0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
    0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
    0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
    0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
    0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
    0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
    0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
    0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
    0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
    0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
    0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
    0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
    0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
  ];
}
