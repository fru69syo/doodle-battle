import 'dart:convert';

import 'package:flutter/services.dart';

import 'battle_spec.dart';
import 'cpu_roster.dart';

/// Asset key of the bundled copy of `shared/battle_spec/battle_spec.json`.
const battleSpecAssetKey = 'assets/battle/battle_spec.json';

/// Loads the battle spec bundled with the app.
Future<BattleSpec> loadBattleSpec([AssetBundle? bundle]) async {
  final source = await (bundle ?? rootBundle).loadString(battleSpecAssetKey);
  return BattleSpec.fromJsonString(source);
}

/// Asset key of Vision's CPU doodle manifest.
const cpuManifestAssetKey = 'assets/cpu/manifest.json';

/// Loads the bundled CPU characters.
Future<CpuRoster> loadCpuRoster([AssetBundle? bundle]) async {
  final source = await (bundle ?? rootBundle).loadString(cpuManifestAssetKey);
  return CpuRoster.fromManifestJson(
    (jsonDecode(source) as Map).cast<String, Object?>(),
  );
}
