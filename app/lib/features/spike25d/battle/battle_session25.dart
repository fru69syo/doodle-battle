import 'dart:typed_data';

import '../../../domain/battle/rng.dart';
import '../../../domain/battle_v2/battle_v2.dart';
import '../../../domain/battle_v2/sim_v2.dart'
    show randomBloomer, randomKid, setupAt;
import '../anim/clips.dart';
import '../rig/rig.dart';
import '../rig/rigged_character.dart';
import 'director25d.dart';

/// One side of a prototype battle.
class Side25 {
  const Side25({
    required this.png,
    required this.name,
    this.level = 12,
    this.bloomer = false,
    this.rig,
    this.genomeSeed = 1,
  });
  final Uint8List png;
  final String name;
  final int level;

  /// Hidden late bloomer (polished / AI-made picture). Internal only: the
  /// UI never receives this flag, only the look it implies.
  final bool bloomer;

  /// Stored (possibly edited) rig; auto-rigged when null.
  final CharacterRig? rig;
  final int genomeSeed;
}

/// Builds the characters off the UI thread-friendly way (pure Dart).
RiggedCharacter buildSideCharacter(Side25 s) {
  // Hidden late bloomer: simplified look until the Lv50 rebuild, then the
  // full rig like everyone else (SPEC §12.2, GAME_DESIGN_V2 §4.4).
  final simple = s.bloomer && s.level < const V2Spec().rebirthLevel;
  return buildRiggedCharacterFromPng(
    s.png,
    rig: s.rig,
    options: BuildOptions(simplified: simple),
  );
}

/// The real v3 ATB engine (10 Hz integer ticks, GAME_DESIGN_V2 §6) plus the
/// 2.5D director. The UI calls [advance] every frame and [tap] on a move
/// button; everything else is read-only state for drawing.
class BattleSession25 {
  BattleSession25({
    required this.sides,
    required List<RiggedCharacter> characters,
    int seed = 7,
    this.alwaysAuto = false,
  }) : director = Director25(
         contexts: [
           for (final c in characters)
             AnimContext(c.rig, limited: c.simplified),
         ],
         seed: seed,
         halfWidth: [for (final c in characters) halfWidthOf(c)],
         fxScale: [
           for (var i = 0; i < 2; i++)
             characters[i].simplified
                 ? 0.5
                 : (sides[i].level >= 50 ? 1.4 : 1.0),
         ],
       ) {
    const spec = V2Spec();
    final setups = <FighterSetupV2>[];
    for (final s in sides) {
      final r = Mulberry32(s.genomeSeed);
      final g = s.bloomer ? randomBloomer(spec, r) : randomKid(spec, r);
      final base = setupAt(spec, g, s.level);
      setups.add(
        FighterSetupV2(
          stats: base.stats,
          attr: base.attr,
          moves: base.moves,
          label: s.name,
        ),
      );
    }
    engine = newBattle(
      spec,
      setups[0],
      setups[1],
      seed: seed,
      recordEvents: true,
    );
    for (var i = 0; i < 2; i++) {
      director.fighters[i].shownHp = engine.fighters[i].maxHp.toDouble();
    }
  }

  final List<Side25> sides;
  final Director25 director;
  late final AtbBattle engine;

  /// おまかせ for the player (small children).
  bool alwaysAuto;

  /// Move chosen by the player: used on the tick the gauge is full
  /// (さきどり when tapped early, GAME_DESIGN_V2 §6.3).
  int? pending;
  double _acc = 0;
  int _seen = 0;

  final _cpu = aiController();
  final _auto = aiController();

  int? _player(AtbBattle b, int side) {
    if (alwaysAuto) return _auto(b, side);
    final p = pending;
    if (p == null) return null;
    return p;
  }

  bool get over => director.winner != null;

  FighterV2 fighter(int side) => engine.fighters[side];

  /// Seconds left to choose (only while the player's gauge is full).
  double? get choiceLeft {
    final f = engine.fighters[0];
    if (f.phase != Phase.ready || alwaysAuto) return null;
    return (engine.spec.decisionTicks - f.readyTicks) / engine.spec.tickHz;
  }

  /// The player taps move [slot]. Returns false when it can not be used.
  bool tap(int slot) {
    final f = engine.fighters[0];
    if (engine.finished || slot >= f.moves.length) return false;
    if (f.phase == Phase.casting) return false;
    pending = slot;
    return true;
  }

  bool usable(int slot) => engine.fighters[0].usable(slot);

  /// Advances wall-clock time [dt] (s): engine ticks at 10 Hz, director
  /// every frame.
  void advance(double dt) {
    _acc += dt;
    while (_acc >= 0.1 && !engine.finished) {
      _acc -= 0.1;
      engine.step(_player, _cpu);
    }
    final ev = engine.events;
    for (; _seen < ev.length; _seen++) {
      final e = ev[_seen];
      if (e.type == 'choose' && e.data['side'] == 0) pending = null;
      director.handle(e, engine);
    }
    director.syncStatus(engine);
    director.update(dt);
  }
}

/// Half the drawing's width in world units when it stands
/// [StagePainter.charHeight] tall.
double halfWidthOf(RiggedCharacter c) {
  var top = double.infinity, minX = double.infinity, maxX = -double.infinity;
  for (var i = 0; i < c.rest.length; i += 2) {
    final x = c.rest[i], y = c.rest[i + 1];
    if (y < top) top = y;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
  }
  final h = (c.rig.groundY - top).clamp(1.0, 1e9);
  return 0.5 * (maxX - minX) / h * 1.25;
}
