/// Battle engine v3 (おえかきファイターズ v2.0): real-time ATB at 10 Hz,
/// ten stats, グー/チョキ/パー, move templates with a numeric budget, AI move
/// validation, growth to Lv100 and the single-player stage table.
///
/// Pure Dart (no Flutter). Bit-exact with the TypeScript port in
/// `shared/battle_engine_v3_ts/` (golden vectors in
/// `shared/battle_spec_v3/golden_vectors.json`). Design:
/// docs/GAME_DESIGN_V2.md; engine notes and balance: docs/BATTLE_V3.md.
library;

export 'ai.dart';
export 'engine.dart';
export 'features.dart';
export 'genome.dart';
export 'loadout.dart';
export 'moves.dart';
export 'offline_moves.dart';
export 'progression.dart';
export 'rng.dart';
export 'spec.dart';
export 'stages.dart';
export 'validator.dart';
