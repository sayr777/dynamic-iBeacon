import 'dart:typed_data';

String normalizeUuid(String value) =>
    value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();

String formatUuid(String value) {
  final compact = normalizeUuid(value);
  if (compact.length != 32) return value;
  final formatted = '${compact.substring(0, 8)}-'
      '${compact.substring(8, 12)}-'
      '${compact.substring(12, 16)}-'
      '${compact.substring(16, 20)}-'
      '${compact.substring(20)}';
  return formatted.toUpperCase();
}

List<int> parseHexKey(String hex) {
  final normalized = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
  if (normalized.length != 32) {
    throw const FormatException('KEY must contain exactly 32 hex symbols');
  }
  return List<int>.generate(
    16,
    (index) => int.parse(normalized.substring(index * 2, index * 2 + 2), radix: 16),
    growable: false,
  );
}

String bytesToHex(Iterable<int> bytes, {String separator = ''}) {
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(separator);
}

String formatMac(Iterable<int> bytes) => bytesToHex(bytes, separator: ':');

String shortDisplayName({
  required String fallback,
  required String? preferred,
}) {
  final trimmed = preferred?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}

DateTime slotStart(int slot, T1ScanMode mode) {
  if (mode == T1ScanMode.production) {
    return DateTime.fromMillisecondsSinceEpoch(slot * 300 * 1000, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(slot * 10 * 1000, isUtc: true);
}

String formatSlotStart(int slot, T1ScanMode mode) {
  if (mode == T1ScanMode.production) {
    final ts = slotStart(slot, mode);
    final dd = ts.day.toString().padLeft(2, '0');
    final mm = ts.month.toString().padLeft(2, '0');
    final yyyy = ts.year.toString().padLeft(4, '0');
    final hh = ts.hour.toString().padLeft(2, '0');
    final min = ts.minute.toString().padLeft(2, '0');
    final ss = ts.second.toString().padLeft(2, '0');
    return '$dd.$mm.$yyyy $hh:$min:$ss UTC';
  }
  final seconds = slot * 10;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  return 'uptime ${hours > 0 ? '$hours h ' : ''}$minutes min $secs s';
}

enum T1ScanMode {
  production,
  prototype,
}

extension T1ScanModeLabel on T1ScanMode {
  String get label => this == T1ScanMode.production ? 'Production' : 'Prototype';
}

Uint8List listToBytes(List<int> bytes) => Uint8List.fromList(bytes);
