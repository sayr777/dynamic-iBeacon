import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the stop-name directory.
///
/// All stops are treated equally — there is no user/default distinction in the
/// API or UI. Config stops (from app_config.json) are merged in on first run
/// via [setDefaults] for tag-IDs that the user has not already defined or
/// explicitly deleted.
///
/// Persistence format (SharedPreferences key [_prefsKey]):
///   { "stops": { "42": "ул. Ленина" }, "deleted": [7, 99] }
/// The "deleted" list tracks config-origin entries the user explicitly removed
/// so they don't reappear after an app restart.
class StopsRepository extends ChangeNotifier {
  static const _prefsKey = 't1_stops_v1';

  StopsRepository();

  final Map<int, String> _stops = {};
  final Set<int> _deleted = {};

  // ── public api ──────────────────────────────────────────────────────────────

  /// All stops sorted by tagId.
  Map<int, String> get all => Map.fromEntries(
        _stops.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );

  /// Name for [tagId], or `null` if not found.
  String? getName(int tagId) => _stops[tagId];

  // ── setup ───────────────────────────────────────────────────────────────────

  /// Merges config defaults into the live map for tag-IDs that are not already
  /// present and have not been explicitly deleted by the user.
  /// Call this AFTER [load()] resolves.
  void setDefaults(Map<int, String> defaults) {
    var changed = false;
    for (final e in defaults.entries) {
      if (!_stops.containsKey(e.key) && !_deleted.contains(e.key)) {
        _stops[e.key] = e.value;
        changed = true;
      }
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
        _stops.clear();
        _deleted.clear();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('stops')) {
            // New format: { "stops": {...}, "deleted": [...] }
            final stopsMap = decoded['stops'] as Map<String, dynamic>? ?? {};
            for (final e in stopsMap.entries) {
              final id = int.tryParse(e.key);
              if (id != null && e.value is String) {
                _stops[id] = (e.value as String).trim();
              }
            }
            final deletedList = decoded['deleted'] as List<dynamic>? ?? [];
            for (final v in deletedList) {
              if (v is int) _deleted.add(v);
            }
          } else {
            // Legacy format: { "42": "ул. Ленина", ... } (custom-only map)
            for (final e in decoded.entries) {
              final id = int.tryParse(e.key);
              if (id != null && e.value is String) {
                _stops[id] = (e.value as String).trim();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Stops] load error: $e');
    }
    notifyListeners();
  }

  // ── mutations ───────────────────────────────────────────────────────────────

  Future<void> upsert(int tagId, String name) async {
    _deleted.remove(tagId); // un-delete if previously deleted
    _stops[tagId] = name.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> delete(int tagId) async {
    _stops.remove(tagId);
    _deleted.add(tagId); // tombstone so config re-merge doesn't bring it back
    await _persist();
    notifyListeners();
  }

  // ── private ─────────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'stops': {for (final e in _stops.entries) '${e.key}': e.value},
        'deleted': _deleted.toList(),
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[Stops] persist error: $e');
    }
  }
}
