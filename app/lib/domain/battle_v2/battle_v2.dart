/// PROTOTYPE — v2.0 combat model (game design spike, docs/GAME_DESIGN_V2.md).
///
/// Reference simulator for tuning; not wired into the app. The normative,
/// engine-agnostic definition is `shared/battle_spec_v3/` (JSON + golden
/// vectors); ports (TS / C# / GDScript) must match the golden vectors.
library;

export 'ai_v2.dart';
export 'atb_engine.dart';
export 'moves_v2.dart';
export 'progression_v2.dart';
export 'stats_v2.dart';
export 'v2_spec.dart';
