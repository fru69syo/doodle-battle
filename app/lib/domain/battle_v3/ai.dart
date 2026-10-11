/// 「おまかせ」 AI (timeout auto-pick, おまかせ toggle, CPU opponents, ghosts).
/// Deterministic given its RNG stream (stream 1 for side a, 2 for side b).
/// docs/GAME_DESIGN_V2.md §6.6, docs/BATTLE_V3.md §AI.
///
/// Tiers: よわい / ふつう share the design's scoring (ふつう = the normative
/// おまかせ: timeouts, ghosts and the server always use it); つよい uses
/// [scoreMoveStrong], which reads hit / crit chances, the time a move costs,
/// the opponent's charge and shield, and thinks faster (see [AiTier]).
library;

import 'engine.dart';
import 'moves.dart';
import 'rng.dart';
import 'spec.dart';

enum AiTier {
  weak(40, 10),
  normal(10, 10),
  strong(0, 4);

  const AiTier(this.randomPct, this.thinkTicks);

  /// Chance (%) of a random usable move instead of the best one.
  final int randomPct;

  /// Ticks a CPU of this tier "thinks" after becoming ready.
  final int thinkTicks;

  /// Kid-facing label.
  String get label => switch (this) {
    weak => 'よわい',
    normal => 'ふつう',
    strong => 'つよい',
  };

  static AiTier fromName(String n) => values.byName(n);
}

/// Picks a slot for [side]: usable moves only; with [AiTier.randomPct] a
/// random usable move (`nextInt(100)` → `nextInt(count)`), else the best
/// score (ties → lowest slot). Slot 0 is always usable.
int chooseMove(
  Battle b,
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
  if (roll < tier.randomPct) {
    return usable[rng.nextInt(usable.length)];
  }
  var best = usable.first;
  var bestScore = -1 << 40;
  for (final i in usable) {
    final s = tier == AiTier.strong
        ? scoreMoveStrong(b, side, i)
        : scoreMove(b, side, f.moves[i]);
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}

int _pts(int points, int maxHp) => points * maxHp ~/ 1000;

/// HP-equivalent score of [m] for [side] right now (ふつう / よわい).
/// 1 budget point = 1/1000 of the opponent's max HP (§5.3).
int scoreMove(Battle b, int side, Move m) {
  final s = b.spec;
  final me = b.fighters[side];
  final foe = b.fighters[1 - side];
  final t = 1 - side;
  final costPenalty =
      _pts(m.spCost * 5 ~/ 4 * 6 ~/ 10, foe.maxHp) +
      _pts(m.castTicks, foe.maxHp);
  var score = 0;
  switch (m.kind) {
    case MoveKind.physical:
    case MoveKind.special:
      final per = b.baseHitDamage(side, t, m);
      var e = per * m.hits * m.accuracy * 95 ~/ 10000;
      e = e * (100 - foe.shieldPct) ~/ 100;
      if (e >= foe.hp) return 1000000000 - m.spCost * 1000 - m.castTicks;
      score = e;
      score += _pts(_secondaryValue(m, me, foe), foe.maxHp);
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
        score = _pts(moveValue(m), foe.maxHp) * 8 ~/ 10;
      }
    case MoveKind.debuff:
      score = foe.stages[m.stat.index] < 0
          ? 0
          : _pts(moveValue(m), foe.maxHp) * 8 ~/ 10;
    case MoveKind.status:
      final has = m.status == StatusKind.poison
          ? foe.poisonTicks > 0
          : foe.paralyzeTicks > 0;
      score = has ? 0 : _pts(moveValue(m), foe.maxHp);
    case MoveKind.shield:
      final threat =
          (foe.phase == Phase.casting && foe.castLeft >= 2) ||
          foe.gauge * 100 >= s.gaugeMax * 85;
      score = me.shieldPct > 0
          ? 0
          : _pts(moveValue(m), foe.maxHp) * (threat ? 20 : 3) ~/ 10;
  }
  return score - costPenalty;
}

int _secondaryValue(Move m, Fighter me, Fighter foe) => switch (m.secondary) {
  SecondaryType.poison when foe.poisonTicks == 0 =>
    m.secondaryChance * kPoisonValue ~/ 100,
  SecondaryType.paralyze when foe.paralyzeTicks == 0 =>
    m.secondaryChance * kParalyzeValue ~/ 100,
  SecondaryType.debuff => m.secondaryChance * kDebuffSecondaryValue ~/ 100,
  SecondaryType.drain => me.hp * 2 < me.maxHp ? m.drainPct * m.power ~/ 100 : 0,
  _ => 0,
};

/// Expected damage (HP, ×1) of one use of damage move [m] by [side] now:
/// real hit and crit chances, mean variance, the target's shield and the
/// heat-up ramp.
int expectedDamage(Battle b, int side, Move m) {
  final s = b.spec;
  final t = 1 - side;
  final foe = b.fighters[t];
  final per = b.baseHitDamage(side, t, m);
  final hit = b.hitChance(side, t, m.accuracy);
  final crit = b.critMille(side, t, m.critBonus);
  final meanVar = s.varianceMinPct + (s.varianceSpan - 1) ~/ 2;
  var e =
      per *
      m.hits *
      hit *
      (1000 + crit * (s.critMultiplierPct - 100) ~/ 100) ~/
      100000;
  e = e * meanVar ~/ 100;
  e = e * (100 - foe.shieldPct) ~/ 100;
  return e * b.heatPct() ~/ 100;
}

/// Ticks [side] needs to fill an empty gauge at the current rates.
int _cycleTicks(Battle b, int side) {
  final r = b.fillRate(side);
  return r <= 0 ? b.spec.gaugeMax : (b.spec.gaugeMax + r - 1) ~/ r;
}

/// The best expected damage the opponent of [side] can deal with one move
/// it can afford now (what a shield would block).
int _foeThreat(Battle b, int side) {
  final t = 1 - side;
  final foe = b.fighters[t];
  if (foe.phase == Phase.casting) {
    final m = foe.moves[foe.castSlot];
    return m.isDamage ? expectedDamage(b, t, m) : 0;
  }
  var best = 0;
  for (var i = 0; i < foe.moves.length; i++) {
    final m = foe.moves[i];
    if (!m.isDamage || !foe.usable(i)) continue;
    final e = expectedDamage(b, t, m);
    if (e > best) best = e;
  }
  return best;
}

/// つよい: HP-equivalent value per unit of time (scaled to a 36-tick
/// action), with real hit / crit odds, finishing blows that are sure to
/// land, shields timed against the opponent's charged move, heals sized by
/// what they actually restore, and buffs / debuffs valued by the damage
/// they add over their duration.
int scoreMoveStrong(Battle b, int side, int slot) {
  final s = b.spec;
  final me = b.fighters[side];
  final foe = b.fighters[1 - side];
  final m = me.moves[slot];
  final cycle = _cycleTicks(b, side);
  final time = cycle + m.castTicks;
  // SP spent now is SP the ひっさつ can not use later.
  final spPenalty = _pts(m.spCost * 5 ~/ 4 * 6 ~/ 10, foe.maxHp);
  int perTime(int v) => v * 36 ~/ time;
  switch (m.kind) {
    case MoveKind.physical:
    case MoveKind.special:
      final e = expectedDamage(b, side, m);
      // A sure KO: the lowest possible roll of every hit still finishes.
      final t = 1 - side;
      final hit = b.hitChance(side, t, m.accuracy);
      final minHit =
          b.baseHitDamage(side, t, m) *
          s.varianceMinPct ~/
          100 *
          (100 - foe.shieldPct) ~/
          100 *
          b.heatPct() ~/
          100;
      if (hit >= 100 && minHit * m.hits >= foe.hp) {
        return 2000000000 - m.castTicks * 1000 - m.spCost;
      }
      if (e >= foe.hp) {
        return 1000000000 + hit * 1000 - m.castTicks * 10 - m.spCost;
      }
      final sec = _pts(_secondaryValue(m, me, foe), foe.maxHp);
      return perTime(e + sec) - spPenalty;
    case MoveKind.heal:
      final steps = s.healDecaySteps;
      final decay =
          steps[me.healUses < steps.length ? me.healUses : steps.length - 1];
      final intl = b.eff(side, Stat.intl);
      final str = b.eff(side, Stat.str);
      final scale = 75 + 50 * intl ~/ (intl + str);
      final heat = b.heatPct();
      final fade = heat >= 200 ? 0 : 200 - heat;
      final est = me.maxHp * m.healPct * scale * decay ~/ 1000000 * fade ~/ 100;
      final missing = me.maxHp - me.hp;
      final amt = est < missing ? est : missing;
      final hpPct = me.hp * 100 ~/ me.maxHp;
      final v = hpPct < 45 ? amt * 13 ~/ 10 : (hpPct < 70 ? amt * 4 ~/ 10 : 0);
      return perTime(v) - spPenalty;
    case MoveKind.shield:
      if (me.shieldPct > 0) return -spPenalty;
      final threat = _foeThreat(b, side);
      final charged =
          (foe.phase == Phase.casting && foe.castLeft >= 2) ||
          foe.phase == Phase.ready ||
          foe.gauge * 100 >= s.gaugeMax * 80;
      final foeCycle = _cycleTicks(b, 1 - side);
      final blocks = charged ? 1 + m.durationTicks ~/ (foeCycle + 10) : 0;
      final v = threat * m.shieldPct ~/ 100 * blocks;
      return perTime(v) - spPenalty;
    case MoveKind.buff:
    case MoveKind.debuff:
      final target = m.kind == MoveKind.buff ? me : foe;
      final active = m.kind == MoveKind.buff
          ? target.stages[m.stat.index] > 0
          : target.stages[m.stat.index] < 0;
      if (active || me.hp * 100 < me.maxHp * 35) return -spPenalty;
      // Damage my next actions gain over the duration (≈ +25 % per stage
      // on the affected side of the damage formula).
      final actions = 1 + m.durationTicks ~/ (cycle + 5);
      var best = 0;
      for (final x in me.moves) {
        if (!x.isDamage) continue;
        final e = expectedDamage(b, side, x);
        if (e > best) best = e;
      }
      final relevant = switch (m.stat) {
        Stat.str || Stat.intl || Stat.def || Stat.res => 22,
        Stat.agi => 18,
        Stat.dex => 8,
        _ => 6,
      };
      final acc = m.kind == MoveKind.debuff
          ? b.hitChance(side, 1 - side, m.accuracy)
          : 100;
      final v =
          best * relevant * m.stages * (actions - 1) * acc ~/ 10000 - best ~/ 4;
      return perTime(v < 0 ? 0 : v) - spPenalty;
    case MoveKind.status:
      final has = m.status == StatusKind.poison
          ? foe.poisonTicks > 0
          : foe.paralyzeTicks > 0;
      if (has) return -spPenalty;
      final hit = b.hitChance(side, 1 - side, m.accuracy);
      final p = b.rel(
        m.chance,
        b.eff(side, Stat.luk),
        b.eff(1 - side, Stat.vit),
        s.statusLukSkewPct,
      );
      final full = m.status == StatusKind.poison
          ? foe.maxHp * s.poisonMillePerSecond ~/ 1000 * (s.poisonTicks ~/ 10)
          : _pts(kParalyzeValue, foe.maxHp);
      final v = full * hit * (p > 100 ? 100 : p) ~/ 10000;
      return perTime(v) - spPenalty;
  }
}

/// Controller that "thinks" for [thinkTicks] after becoming ready, then
/// picks with [chooseMove] on the side's AI stream. [thinkTicks] defaults
/// to the tier's ([AiTier.thinkTicks]).
Controller aiController({int? thinkTicks, AiTier tier = AiTier.normal}) {
  final think = thinkTicks ?? tier.thinkTicks;
  return (b, side) {
    final f = b.fighters[side];
    if (f.readyTicks < think) return null;
    return chooseMove(b, side, b.aiRng[side], tier: tier);
  };
}

/// Timeout auto-pick: the ふつう AI.
int autoPickNormal(Battle b, int side, Mulberry32 rng) =>
    chooseMove(b, side, rng);
