import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/beacon_utils.dart';

/// Default ARGB color for operators that don't have one stored yet.
const kOperatorDefaultColor = 0xFF40C4FF; // light blue

/// A UUID → operator mapping with a user-chosen display color.
class Operator {
  const Operator({
    required this.uuid,
    required this.name,
    required this.code,
    required this.colorValue,
  });

  /// Normalized UUID: lowercase, no dashes (32 hex chars).
  final String uuid;
  final String name;
  final String code;

  /// ARGB color integer (e.g. 0xFF40C4FF).
  final int colorValue;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'code': code,
        'color': colorValue,
      };

  factory Operator.fromJson(Map<String, dynamic> json) => Operator(
        uuid: normalizeUuid((json['uuid'] as String? ?? '')),
        name: (json['name'] as String? ?? '').trim(),
        code: (json['code'] as String? ?? '').trim(),
        colorValue: (json['color'] as int?) ?? kOperatorDefaultColor,
      );

  Operator copyWith({
    String? name,
    String? code,
    int? colorValue,
  }) =>
      Operator(
        uuid: uuid,
        name: name ?? this.name,
        code: code ?? this.code,
        colorValue: colorValue ?? this.colorValue,
      );
}

/// Manages UUID → operator mappings, all fully editable.
///
/// Config operators (from app_config.json, excluding the local T1 operator)
/// are pre-populated via [setFromConfig] and stored alongside user-added ones.
/// All operators can be edited and deleted. Deleted config operators do not
/// reappear after restart (tombstone set persisted separately).
///
/// Persistence key: [_prefsKey] — JSON:
///   { "operators": [...], "deleted": ["uuid1", ...] }
class OperatorsRepository extends ChangeNotifier {
  static const _prefsKey = 't1_operators_v1';

  final List<Operator> _operators = [];
  final Set<String> _deleted = {}; // normalized UUIDs of tombstoned entries

  // ── public api ──────────────────────────────────────────────────────────────

  List<Operator> get operators => List.unmodifiable(_operators);

  /// Returns the [Operator] matching [rawUuid], or `null` if not found.
  Operator? getByUuid(String rawUuid) {
    final uuid = normalizeUuid(rawUuid);
    try {
      return _operators.firstWhere((op) => op.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  // ── setup ───────────────────────────────────────────────────────────────────

  /// Pre-populates operators from app_config.json for UUIDs that the user has
  /// not already added or deleted.  Call this AFTER [load()] resolves.
  ///
  /// [ops] should contain only *external* (non-T1) operators.
  void setFromConfig(
      List<({String uuid, String name, String code})> ops) {
    var changed = false;
    for (final op in ops) {
      final uuid = normalizeUuid(op.uuid);
      if (_deleted.contains(uuid)) continue;
      if (_operators.any((e) => e.uuid == uuid)) continue;
      _operators.add(Operator(
        uuid: uuid,
        name: op.name,
        code: op.code,
        colorValue: kOperatorDefaultColor,
      ));
      changed = true;
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
  }

  // ── lifecycle ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _operators.clear();
        _deleted.clear();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          // New format: { "operators": [...], "deleted": [...] }
          if (decoded.containsKey('operators')) {
            final list = decoded['operators'] as List<dynamic>? ?? [];
            for (final item in list) {
              if (item is Map<String, dynamic>) {
                _operators.add(Operator.fromJson(item));
              }
            }
            final deletedList = decoded['deleted'] as List<dynamic>? ?? [];
            for (final v in deletedList) {
              if (v is String) _deleted.add(normalizeUuid(v));
            }
          } else {
            // Legacy format (old CustomOperator list stored directly as array
            // at the root — shouldn't happen, but handle gracefully).
          }
        } else if (decoded is List) {
          // Legacy format: plain array of {uuid, name, code}
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _operators.add(Operator.fromJson(item));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Operators] load error: $e');
    }
    notifyListeners();
  }

  // ── mutations ───────────────────────────────────────────────────────────────

  Future<void> upsert(Operator op) async {
    _deleted.remove(op.uuid);
    final idx = _operators.indexWhere((e) => e.uuid == op.uuid);
    if (idx >= 0) {
      _operators[idx] = op;
    } else {
      _operators.add(op);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String rawUuid) async {
    final uuid = normalizeUuid(rawUuid);
    _operators.removeWhere((op) => op.uuid == uuid);
    _deleted.add(uuid);
    await _persist();
    notifyListeners();
  }

  // ── private ─────────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'operators': _operators.map((op) => op.toJson()).toList(),
        'deleted': _deleted.toList(),
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[Operators] persist error: $e');
    }
  }
}
