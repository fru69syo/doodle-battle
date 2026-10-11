/// PROTOTYPE — 「おまかせ」 AI for the v2 ATB battle (also the timeout
/// auto-pick, CPU opponents and ghosts). Deterministic given its RNG stream.
/// docs/GAME_DESIGN_V2.md §6.6.
library;

import '../battle/rng.dart';
import 'atb_engine.dart';
import 'moves_v2.dart';
import 'v2_spec.dart';

enum AiTier { weak, normal, strong }

/// Random-move probability (%) per tier.
const Map<AiTier, int> kAiRandomPct = {
  AiTier.weak: 40,
  AiTier.normal: 10,
  AiTier.strong: 0,
};

/// Scores every usable move in HP-equivalent units and returns the best
/// (ties → lowest slot). Slot 0 is always usable (sp 0, cooldown 0).
int chooseMove(
  AtbBattle b,
  int side,
  Mulberry32 rng, {
  AiTier tier = AiTier.normal,
}) {
  final f = b.fighters[side];
  final usable = [
    for (var i = 0; i < f.moves.length; i++)
      if (f.usable(i)) i,
  ];
  if (usable.isEmpty) return 0;
  final roll = rng.nextInt(100);
  if (roll < kAiRandomPct[tier]!) {
    return usable[rng.nextInt(usable.length)];
  }
  var best = usable.first;
  var bestScore = -1 << 40;
  for (final i in usable) {
    final s = scoreMove(b, side, f.moves[i]);
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}

/// HP-equivalent score of [m] for [side] right now (×1, integer).
int scoreMove(AtbBattle b, int side, MoveV2 m) {
  final s = b.spec;
  final me = b.fighters[side];
  final foe = b.fighters[1 - side];
  final t = 1 - side;
  int pts(int points, int maxHp) => points * maxHp ~/ 1000;
  final costPenalty =
      pts(m.spCost * 5 ~/ 4 * 6 ~/ 10, foe.maxHp) + pts(m.castTicks, foe.maxHp);
  var score = 0;
  switch (m.kind) {
    case MoveKind.physical:
    case MoveKind.special:
      final per = b.baseHitDamage(side, t, m);
      var e = per * m.hits * m.accuracy * 95 ~/ 10000;
      e = e * (100 - foe.shieldPct) ~/ 100;
      if (e >= foe.hp) return 1000000000 - m.spCost * 1000 - m.castTicks;
      score = e;
      final sec = switch (m.secondary) {
        SecondaryType.poison when foe.poisonTicks == 0 =>
          m.secondaryChance * kPoisonValue ~/ 100,
        SecondaryType.paralyze when foe.paralyzeTicks == 0 =>
          m.secondaryChance * kParalyzeValue ~/ 100,
        SecondaryType.debuff =>
          m.secondaryChance * kDebuffSecondaryValue ~/ 100,
        SecondaryType.drain =>
          me.hp * 2 < me.maxHp ? m.drainPct * m.power ~/ 100 : 0,
        _ => 0,
      };
      score += pts(sec, foe.maxHp);
    case MoveKind.heal:
      final missing = me.maxHp - me.hp;
      final est = me.maxHp * m.healPct ~/ 100;
      final amt = est < missing ? est : missing;
      final hpPct = me.hp * 100 ~/ me.maxHp;
      score = hpPct < 50 ? amt * 12 ~/ 10 : (hpPct < 75 ? amt * 3 ~/ 10 : 0);
    case MoveKind.buff:
      if (me.stages[m.stat.index] > 0 || me.hp * 100 < me.maxHp * 40) {
        score = 0;
      } else {
        score = pts(moveValue(m), foe.maxHp) * 8 ~/ 10;
      }
    case MoveKind.debuff:
      score = foe.stages[m.stat.index] < 0
          ? 0
          : pts(moveValue(m), foe.maxHp) * 8 ~/ 10;
    case MoveKind.status:
      final has = m.status == StatusKind.poison
          ? foe.poisonTicks > 0
          : foe.paralyzeTicks > 0;
      score = has ? 0 : pts(moveValue(m), foe.maxHp);
    case MoveKind.shield:
      final threat =
          (foe.phase == Phase.casting && foe.castLeft >= 2) ||
          foe.gauge * 100 >= s.gaugeMax * 85;
      score = me.shieldPct > 0
          ? 0
          : pts(moveValue(m), foe.maxHp) * (threat ? 20 : 3) ~/ 10;
  }
  return score - costPenalty;
}

/// Controller that "thinks" for [thinkTicks] after becoming ready, then
/// picks with [chooseMove] using the side's AI stream.
Controller aiController({int thinkTicks = 10, AiTier tier = AiTier.normal}) =>
    (b, side) {
      final f = b.fighters[side];
      if (f.readyTicks < thinkTicks) return null;
      return chooseMove(b, side, b.aiRng[side], tier: tier);
    };

/// Timeout auto-pick: the normal-tier AI.
int autoPickNormal(AtbBattle b, int side, Mulberry32 rng) =>
    chooseMove(b, side, rng);

/// Convenience: a battle between two setups with the standard auto-pick.
AtbBattle newBattle(
  V2Spec s,
  FighterSetupV2 a,
  FighterSetupV2 c, {
  required int seed,
  bool recordEvents = false,
}) => AtbBattle(
  s,
  a,
  c,
  seed: seed,
  autoPick: autoPickNormal,
  recordEvents: recordEvents,
);
