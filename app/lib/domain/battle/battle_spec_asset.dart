import 'package:flutter/services.dart';

import 'battle_spec.dart';

/// Asset key of the bundled copy of `shared/battle_spec/battle_spec.json`.
const battleSpecAssetKey = 'assets/battle/battle_spec.json';

/// Loads the battle spec bundled with the app.
Future<BattleSpec> loadBattleSpec([AssetBundle? bundle]) async {
  final source = await (bundle ?? rootBundle).loadString(battleSpecAssetKey);
  return BattleSpec.fromJsonString(source);
}
