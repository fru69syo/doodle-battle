/// Turning a character (genome + level + stored AI proposals) into a battle
/// [FighterSetup]: the stats at a level, the unlocked move slots, AI moves
/// re-validated against the current slot budget and offline moves for
/// everything else. Used by single-player, family battles, rated sync, the
/// server and the simulator, so every place fields a character the same way.
library;

import 'engine.dart';
import 'genome.dart';
import 'moves.dart';
import 'offline_moves.dart';
import 'progression.dart';
import 'spec.dart';
import 'validator.dart';

/// Offline stream of the move set active at [level] (12, or 14 once a
/// hidden bloomer is reborn).
int moveStreamAt(Genome g, int level) => g.rebornAt(level) ? 14 : 12;

/// The four slot moves a character has at [level] (locked slots included;
/// filter with [unlockedSlots]). [aiProposals] (index = slot, null = none)
/// are the normalised AI moves stored with the character: each is
/// re-validated against the slot budget at this level, and a rejected one
/// falls back to the offline move. [nameOverrides] (index = slot) rename a
/// move without touching its numbers (legacy v1 move names).
List<Move> movesAt(
  V3Spec s,
  Genome g,
  int level, {
  Attr? attr,
  List<Map<String, Object?>?> aiProposals = const [],
  List<String?> nameOverrides = const [],
  bool preForm = false,
  bool Function(String)? ngCheck,
}) {
  final factor = preForm ? s.bloomerPreMoveFactorPct : g.moveFactorPct(level);
  final stream = preForm ? 12 : moveStreamAt(g, level);
  final own = attr ?? g.attr;
  final offline = generateOfflineMoves(
    s,
    g,
    moveFactorPct: factor,
    stream: stream,
    attr: own,
  );
  final out = <Move>[];
  for (var i = 0; i < 4; i++) {
    var m = offline[i];
    final p = i < aiProposals.length ? aiProposals[i] : null;
    if (p != null) {
      final v = validateAiMove(
        s,
        p,
        slot: i,
        own: own,
        moveFactorPct: factor,
        ngCheck: ngCheck,
      );
      if (!v.rejected) m = v.move!;
    }
    final n = i < nameOverrides.length ? nameOverrides[i] : null;
    if (n != null && n.isNotEmpty) m = m.copyWith(name: n);
    out.add(m);
  }
  return out;
}

/// Battle setup at [level] (moves unlocked by level; hidden bloomers switch
/// to their rebirth stats and move set at Lv50).
FighterSetup setupAt(
  V3Spec s,
  Genome g,
  int level, {
  Attr? attr,
  List<Map<String, Object?>?> aiProposals = const [],
  List<String?> nameOverrides = const [],
  String label = '',
  int powerPct = 100,
}) {
  final moves = movesAt(
    s,
    g,
    level,
    attr: attr,
    aiProposals: aiProposals,
    nameOverrides: nameOverrides,
  );
  final stats = g.statsAt(level);
  return FighterSetup(
    stats: [for (final v in stats) v * powerPct ~/ 100],
    attr: attr ?? g.attr,
    moves: moves.sublist(0, unlockedSlots(s, level)),
    label: label,
  );
}

/// Rated-play setup (§8): stats synced to Lv50 with the character's own
/// growth (pre-rebirth form for a bloomer below Lv50), moves = the slots
/// unlocked at its actual level, budget of the sync level.
FighterSetup ratedSetup(
  V3Spec s,
  Genome g, {
  required int actualLevel,
  List<Map<String, Object?>?> aiProposals = const [],
  List<String?> nameOverrides = const [],
  String label = '',
}) {
  final r = ratedSync(s, actualLevel: actualLevel, isBloomer: g.isBloomer);
  final stats = g.statsAt(r.statLevel, preForm: r.preForm);
  final moves = movesAt(
    s,
    g,
    r.statLevel,
    aiProposals: aiProposals,
    nameOverrides: nameOverrides,
    preForm: r.preForm,
  );
  return FighterSetup(
    stats: stats,
    attr: g.attr,
    moves: moves.sublist(0, r.slotCount),
    label: label,
  );
}

/// Family-battle setup: the character as it would be at [battleLevel]
/// (handicap), without revealing a hidden bloomer's rebirth early: a
/// bloomer whose real level is below Lv50 keeps its pre-rebirth form.
FighterSetup familySetup(
  V3Spec s,
  Genome g, {
  required int actualLevel,
  required int battleLevel,
  List<Map<String, Object?>?> aiProposals = const [],
  List<String?> nameOverrides = const [],
  String label = '',
}) {
  final pre = g.isBloomer && actualLevel < s.rebirthLevel;
  final stats = g.statsAt(battleLevel, preForm: pre);
  final moves = movesAt(
    s,
    g,
    battleLevel,
    aiProposals: aiProposals,
    nameOverrides: nameOverrides,
    preForm: pre,
  );
  return FighterSetup(
    stats: stats,
    attr: g.attr,
    moves: moves.sublist(0, unlockedSlots(s, battleLevel)),
    label: label,
  );
}
