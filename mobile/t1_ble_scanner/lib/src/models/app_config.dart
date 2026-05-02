import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../utils/beacon_utils.dart';

class OperatorConfig {
  const OperatorConfig({
    required this.name,
    required this.code,
    required this.uuid,
    required this.scope,
  });

  final String name;
  final String code;
  final String uuid;
  final OperatorScope scope;

  factory OperatorConfig.fromJson(Map<String, dynamic> json, OperatorScope scope) {
    return OperatorConfig(
      name: (json['name'] as String? ?? '').trim(),
      code: (json['code'] as String? ?? json['name'] as String? ?? '').trim(),
      uuid: normalizeUuid(json['uuid'] as String? ?? ''),
      scope: scope,
    );
  }
}

enum OperatorScope {
  local,
  external,
}

class ScanDefaults {
  const ScanDefaults({
    required this.keyHex,
    required this.tagMax,
    required this.productionSlotWindow,
    required this.prototypeSlotMax,
  });

  final String keyHex;
  final int tagMax;
  final int productionSlotWindow;
  final int prototypeSlotMax;

  factory ScanDefaults.fromJson(Map<String, dynamic>? json) {
    return ScanDefaults(
      keyHex: (json?['keyHex'] as String? ?? '2B7E151628AED2A6ABF7158809CF4F3C').toUpperCase(),
      tagMax: (json?['tagMax'] as num? ?? 100).toInt(),
      productionSlotWindow: (json?['productionSlotWindow'] as num? ?? 5).toInt(),
      prototypeSlotMax: (json?['prototypeSlotMax'] as num? ?? 1000).toInt(),
    );
  }
}

class AppConfig {
  const AppConfig({
    required this.localOperator,
    required this.externalOperators,
    required this.stops,
    required this.defaults,
  });

  final OperatorConfig localOperator;
  final List<OperatorConfig> externalOperators;
  final Map<int, String> stops;
  final ScanDefaults defaults;

  Map<String, OperatorConfig> get operatorsByUuid {
    final map = <String, OperatorConfig>{localOperator.uuid: localOperator};
    for (final operator in externalOperators) {
      map[operator.uuid] = operator;
    }
    return map;
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final stopsJson = (json['stops'] as Map<String, dynamic>? ?? const <String, dynamic>{});
    return AppConfig(
      localOperator: OperatorConfig.fromJson(
        json['local'] as Map<String, dynamic>? ?? const <String, dynamic>{},
        OperatorScope.local,
      ),
      externalOperators: (json['external'] as List<dynamic>? ?? const [])
          .map((item) => OperatorConfig.fromJson(item as Map<String, dynamic>, OperatorScope.external))
          .toList(growable: false),
      stops: {
        for (final entry in stopsJson.entries)
          int.tryParse(entry.key) ?? -1: (entry.value as String).trim(),
      }..remove(-1),
      defaults: ScanDefaults.fromJson(json['defaults'] as Map<String, dynamic>?),
    );
  }

  static Future<AppConfig> load() async {
    final raw = await rootBundle.loadString('assets/config/app_config.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AppConfig.fromJson(json);
  }
}
