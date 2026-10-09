import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle/battle.dart';

/// Repo-relative paths (flutter test runs with cwd = app/).
const sharedSpecPath = '../shared/battle_spec/battle_spec.json';
const goldenPath = '../shared/battle_spec/golden_vectors.json';
const assetCopyPath = 'assets/battle/battle_spec.json';
const cpuManifestPath = 'assets/cpu/manifest.json';

BattleSpec loadSpecFromFile() =>
    BattleSpec.fromJsonString(File(sharedSpecPath).readAsStringSync());

Map<String, Object?> readJson(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();
