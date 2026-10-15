/// Battle AI with stackable gauge bars: the kid's 「おまかせ」 switch (a random
/// move, then wait for its bars), and the tiered CPU / ghost AI
/// (よわい / ふつう / つよい) that reasons about bars. Deterministic given
/// its RNG stream (stream 1 for side a, 2 for side b).
/// docs/GAME_DESIGN_V2.md §6.6, docs/BATTLE_V3.md §AI.
///
/// Both work as a *plan*: the move the fighter saves bars for
/// ([Fighter.aiPlan]); it fires on the first tick the bars are there and a
/// new plan is made after each use.
library;

import 'engine.dart';
import 'moves.dart';
import 'rng.dart';
import 'spec.dart';

enum AiTier {
  weak(40, 10, 0),
  normal(25, 10, 1),
  strong(0, 4, 5);

  const AiTier(this.randomPct, this.thinkTicks, this.saveBars);

  /// How many bars beyond what it has now this tier will save up for
  /// (よわい spends what it has, ふつう waits for one more bar at most,
  /// つよい plans for any move).
  final int saveBars;

  /// Chance (%) of planning a random eligible move instead of the best one.
  final int randomPct;

  /// Ticks a CPU of this tier "thinks" once it has a full bar.
  final int thinkTicks;

  /// Kid-facing label.
  String get label => switch (this) {
    weak => 'よわい',
    normal => 'ふつう',
    strong => 'つよい',
  };

  static AiTier fromName(String n) => values.byName(n);
}

/// Slots [side] may plan for: off cooldown and costing at most its max
/// bars (slot 0 always qualifies).
List<int> eligibleSlots(Battle b, int side) {
  final f = b.fighters[side];
  return [
    for (var i = 0; i < f.moves.length; i++)
      if (f.eligible(i)) i,
  ];
}

/// おまかせ: a uniformly random eligible move (`nextInt(count)` on [rng]).
int omakasePick(Battle b, int side, Mulberry32 rng) {
  final e = eligibleSlots(b, side);
  if (e.isEmpty) return 0;
  return e[rng.nextInt(e.length)];
}

/// The kid's おまかせ switch (offline; the realtime server runs the same
/// rule): pick a random eligible move, wait until its bars are there, use
/// it, pick again. No thinking time.
Controller omakaseController() => (b, side) {
  final f = b.fighters[side];
  final p = f.aiPlan ??= omakasePick(b, side, b.aiRng[side]);
  return f.usable(p) ? p : null;
};

/// Plans a move for [side] among the eligible ones: with
/// [AiTier.randomPct] a random one (`nextInt(100)` → `nextInt(count)`),
/// else the best score (ties → lowest slot). The plan may need more bars
/// than [side] has now (saving up).
int chooseMove(
  Battle b,
  int side,
  Mulberry32 rng, {
  AiTier tier = AiTier.normal,
}) {
  final e = eligibleSlots(b, side);
  if (e.isEmpty) return 0;
  final roll = rng.nextInt(100);
  if (roll < tier.randomPct) return e[rng.nextInt(e.length)];
  return bestMove(b, side, tier: tier);
}

/// The best-scoring eligible move within the tier's saving horizon
/// ([AiTier.saveBars]; no randomness). Slot 0 is always a candidate.
int bestMove(Battle b, int side, {AiTier tier = AiTier.normal}) {
  final f = b.fighters[side];
  final reach = f.bars + tier.saveBars;
  final e = [
    for (final i in eligibleSlots(b, side))
      if (i == 0 || f.moves[i].bars <= reach) i,
  ];
  if (e.isEmpty) return 0;
  var best = e.first;
  var bestScore = -1 << 52;
  for (final i in e) {
    final s = tier == AiTier.strong
        ? scoreMoveStrong(b, side, i)
        : scoreMove(b, side, i);
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}

/// One decision of the tiered AI for [side] (CPU, ghosts, the simulator):
/// nothing until it has held a full bar for [think] ticks (at least one
/// full bar even when [think] is 0); then it plans
/// ([chooseMove]; つよい re-plans every tick with [bestMove]; ふつう and
/// よわい switch to a finishing blow they can afford now) and uses the plan
/// once its bars are there.
int? aiDecide(Battle b, int side, {required AiTier tier, required int think}) {
  final f = b.fighters[side];
  if (f.bars < 1 || f.waitTicks < think) return null;
  if (tier == AiTier.strong) {
    f.aiPlan = bestMove(b, side, tier: tier);
  } else {
    f.aiPlan ??= chooseMove(b, side, b.aiRng[side], tier: tier);
    if (tier == AiTier.normal && !f.usable(f.aiPlan!)) {
      final ko = _finisherNow(b, side);
      if (ko != null) f.aiPlan = ko;
    }
  }
  final p = f.aiPlan!;
  return f.usable(p) ? p : null;
}

/// Controller for the tiered AI ([aiDecide]). [thinkTicks] defaults to the
/// tier's ([AiTier.thinkTicks]).
Controller aiController({int? thinkTicks, AiTier tier = AiTier.normal}) {
  final think = thinkTicks ?? tier.thinkTicks;
  return (b, side) => aiDecide(b, side, tier: tier, think: think);
}

int _pts(int points, int maxHp) => points * maxHp ~/ 1000;

/// Ticks [side] needs for one bar at the current rates.
int barTicks(Battle b, int side) {
  final r = b.fillRate(side);
  return r <= 0 ? b.spec.gaugeMax : (b.spec.gaugeMax + r - 1) ~/ r;
}

/// Ticks until [side] has [bars] full bars at the current rate (0 = now).
int ticksToBars(Battle b, int side, int bars) {
  final f = b.fighters[side];
  final need = bars * b.spec.gaugeMax - f.gauge;
  if (need <= 0) return 0;
  final r = b.fillRate(side);
  return r <= 0 ? 1 << 20 : (need + r - 1) ~/ r;
}

/// The cheapest damage move [side] can use now that is expected to KO.
int? _finisherNow(Battle b, int side) {
  final f = b.fighters[side];
  final foe = b.fighters[1 - side];
  int? best;
  for (var i = 0; i < f.moves.length; i++) {
    final m = f.moves[i];
    if (!m.isDamage || !f.usable(i)) continue;
    final per = b.baseHitDamage(side, 1 - side, m);
    var e = per * m.hits * m.accuracy * 95 ~/ 10000;
    e = e * (100 - foe.shieldPct) ~/ 100;
    if (e >= foe.hp && (best == null || m.bars < f.moves[best].bars)) {
      best = i;
    }
  }
  return best;
}

/// ふつう / よわい: HP-equivalent value of one use of the move in [slot]
/// per bar it costs (×100), a little less when it has to be saved for.
/// 1 budget point = 1/1000 of the opponent's max HP (§5.3). A KO the
/// fighter can afford now is top (the cheapest first).
int scoreMove(Battle b, int side, int slot) {
  final s = b.spec;
  final me = b.fighters[side];
  final foe = b.fighters[1 - side];
  final m = me.moves[slot];
  final t = 1 - side;
  final now = me.gauge >= m.bars * s.gaugeMax;
  var v = 0;
  switch (m.kind) {
    case MoveKind.physical:
    case MoveKind.special:
      final per = b.baseHitDamage(side, t, m);
      var e = per * m.hits * m.accuracy * 95 ~/ 10000;
      e = e * (100 - foe.shieldPct) ~/ 100;
      if (e >= foe.hp) {
        if (now) return 1000000000 - m.bars * 1000 - m.castTicks;
        e = foe.hp;
      }
      v = e + _pts(_secondaryValue(m, me, foe), foe.maxHp);
    case MoveKind.heal:
      final missing = me.maxHp - me.hp;
      final est = me.maxHp * m.healPct ~/ 100;
      final amt = est < missing ? est : missing;
      final hpPct = me.hp * 100 ~/ me.maxHp;
      v = hpPct < 50 ? amt * 12 ~/ 10 : (hpPct < 75 ? amt * 3 ~/ 10 : 0);
    case MoveKind.buff:
      v = me.stages[m.stat.index] > 0 || me.hp * 100 < me.maxHp * 40
          ? 0
          : _pts(moveValue(m), foe.maxHp) * 8 ~/ 10;
    case MoveKind.debuff:
      v = foe.stages[m.stat.index] < 0
          ? 0
          : _pts(moveValue(m), foe.maxHp) * 8 ~/ 10;
    case MoveKind.status:
      final has = m.status == StatusKind.poison
          ? foe.poisonTicks > 0
          : foe.paralyzeTicks > 0;
      v = has ? 0 : _pts(moveValue(m), foe.maxHp);
    case MoveKind.shield:
      final threat =
          (foe.phase == Phase.casting && foe.castLeft >= 2) || foe.bars >= 2;
      v = me.shieldPct > 0
          ? 0
          : _pts(moveValue(m), foe.maxHp) * (threat ? 20 : 3) ~/ 10;
  }
  var score = (v - _pts(m.castTicks, foe.maxHp)) * 100 ~/ m.bars;
  if (!now) score = score * 97 ~/ 100;
  return score;
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

/// Expected damage (HP, ×1) of one use of damage move [m] by [side]:
/// real hit and crit chances, mean variance, the target's shield and the
/// heat-up ramp — now, or [inTicks] ticks from now (a shield that will have
/// expired no longer counts; the heat-up ramp of that tick).
int expectedDamage(Battle b, int side, Move m, {int inTicks = 0}) {
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
  if (foe.shieldTicks > inTicks) e = e * (100 - foe.shieldPct) ~/ 100;
  return e * _heatAt(b, b.tick + inTicks) ~/ 100;
}

int _heatAt(Battle b, int tick) {
  final s = b.spec;
  return tick <= s.heatUpStartTick
      ? 100
      : 100 + s.heatUpPctPerSecond * ((tick - s.heatUpStartTick) ~/ s.tickHz);
}

/// The most damage the opponent of [side] is expected to deal with one
/// move it can use within [ticks] (its banked bars plus what fills in that
/// time; a move it is casting counts in full). Ignores my shield.
int foeThreatWithin(Battle b, int side, int ticks) {
  final t = 1 - side;
  final foe = b.fighters[t];
  if (foe.phase == Phase.casting) {
    final m = foe.moves[foe.castSlot];
    return m.isDamage ? expectedDamage(b, t, m) : 0;
  }
  var best = 0;
  for (var i = 0; i < foe.moves.length; i++) {
    final m = foe.moves[i];
    if (!m.isDamage || !foe.canQueue(i)) continue;
    if (foe.cooldowns[i] > ticks) continue;
    if (ticksToBars(b, t, m.bars) + m.castTicks > ticks) continue;
    final e = expectedDamage(b, t, m);
    if (e > best) best = e;
  }
  return best;
}

/// つよい: HP-equivalent value per bar-time (scaled to one 36-tick bar),
/// with real hit / crit odds; sure and likely finishing blows first; no
/// saving up while the opponent can finish it first; shields valued by the
/// hit the opponent can afford during them (its banked bars); heals sized
/// by what they restore; buffs / debuffs by the damage they add.
int scoreMoveStrong(Battle b, int side, int slot) {
  final s = b.spec;
  final me = b.fighters[side];
  final foe = b.fighters[1 - side];
  final m = me.moves[slot];
  final t = 1 - side;
  final cycle = barTicks(b, side);
  final wait = ticksToBars(b, side, m.bars);
  final time = m.bars * cycle + m.castTicks;
  int perTime(int v) {
    var x = v * 36 * 100 ~/ time;
    // Saving up while the opponent can KO first is not worth it.
    if (wait > 0 && foeThreatWithin(b, side, wait + m.castTicks) >= me.hp) {
      x = x ~/ 4;
    }
    return x;
  }

  switch (m.kind) {
    case MoveKind.physical:
    case MoveKind.special:
      final e = expectedDamage(b, side, m, inTicks: wait + m.castTicks);
      final hit = b.hitChance(side, t, m.accuracy);
      if (wait == 0) {
        // A sure KO: the lowest possible roll of every hit still finishes.
        final minHit =
            b.baseHitDamage(side, t, m) *
            s.varianceMinPct ~/
            100 *
            (100 - foe.shieldPct) ~/
            100 *
            b.heatPct() ~/
            100;
        if (hit >= 100 && minHit * m.hits >= foe.hp) {
          return 2000000000 - m.castTicks * 1000 - m.bars;
        }
        if (e >= foe.hp) {
          return 1000000000 + hit * 1000 - m.castTicks * 10 - m.bars * 100;
        }
      }
      final sec = _pts(_secondaryValue(m, me, foe), foe.maxHp);
      return perTime((e < foe.hp ? e : foe.hp) + sec);
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
      return perTime(v);
    case MoveKind.shield:
      if (me.shieldPct > 0) return 0;
      // The hit the opponent can deliver while the shield is up.
      final threat = foeThreatWithin(b, side, wait + m.durationTicks);
      final soon = foeThreatWithin(b, side, wait + 6);
      final v = (soon > 0 ? threat : threat ~/ 3) * m.shieldPct ~/ 100;
      return perTime(v);
    case MoveKind.buff:
    case MoveKind.debuff:
      final target = m.kind == MoveKind.buff ? me : foe;
      final active = m.kind == MoveKind.buff
          ? target.stages[m.stat.index] > 0
          : target.stages[m.stat.index] < 0;
      if (active || me.hp * 100 < me.maxHp * 35) return 0;
      // Damage my bars gain over the duration (≈ +25 % per stage on the
      // affected side of the damage formula): the bars I hold after paying
      // for it plus those that fill meanwhile, at my best damage per bar.
      final left = me.bars - m.bars < 0 ? 0 : me.bars - m.bars;
      final actions = 1 + left + m.durationTicks ~/ (cycle + 5);
      var best = 0;
      for (final x in me.moves) {
        if (!x.isDamage) continue;
        final e = expectedDamage(b, side, x) ~/ x.bars;
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
      return perTime(v < 0 ? 0 : v);
    case MoveKind.status:
      final has = m.status == StatusKind.poison
          ? foe.poisonTicks > 0
          : foe.paralyzeTicks > 0;
      if (has) return 0;
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
      return perTime(v);
  }
}
