/// PROTOTYPE — v2 real-time ATB battle at a fixed 10 Hz tick, integer maths.
/// docs/GAME_DESIGN_V2.md §6. The production engine must expose the same
/// model as a pure `step(state, inputs) -> (state, events)`; this reference
/// keeps the state in a mutable object for Monte Carlo speed.
library;

import '../battle/rng.dart';
import 'moves_v2.dart';
import 'stats_v2.dart';
import 'v2_spec.dart';

/// What one fighter brings into a battle.
class FighterSetupV2 {
  const FighterSetupV2({
    required this.stats,
    required this.attr,
    required this.moves,
    this.label = '',
  });
  final List<int> stats;
  final Attr attr;

  /// Unlocked moves only (2..4).
  final List<MoveV2> moves;
  final String label;
}

enum Phase { charging, ready, casting }

class FighterV2 {
  FighterV2(V2Spec s, this.setup)
    : stats = List.of(setup.stats),
      maxHp = maxHpOf(s, setup.stats),
      hp = maxHpOf(s, setup.stats),
      sp = s.spStartCenti,
      cooldowns = List.filled(setup.moves.length, 0);

  final FighterSetupV2 setup;
  final List<int> stats;
  final int maxHp;
  int hp;

  /// SP in centi-SP (0..10000 = 0..100 SP).
  int sp;
  int gauge = 0;
  Phase phase = Phase.charging;
  int readyTicks = 0;
  int castSlot = -1;
  int castLeft = 0;
  final List<int> cooldowns;
  final List<int> stages = List.filled(10, 0);
  final List<int> stageTicks = List.filled(10, 0);
  int poisonTicks = 0;
  int paralyzeTicks = 0;
  int shieldPct = 0;
  int shieldTicks = 0;
  int healUses = 0;
  int actions = 0;
  int autoPicks = 0;

  List<MoveV2> get moves => setup.moves;
  Attr get attr => setup.attr;

  bool usable(int slot) =>
      cooldowns[slot] == 0 && sp >= moves[slot].spCost * 100;
}

/// Event log entry (only recorded when `recordEvents` is on).
class BattleEventV2 {
  const BattleEventV2(this.tick, this.type, this.data);
  final int tick;
  final String type;
  final Map<String, Object?> data;
  Map<String, Object?> toJson() => {'tick': tick, 'type': type, ...data};
  @override
  String toString() => '$tick $type $data';
}

/// Decides a move for a ready fighter. Returns a slot index, or null to keep
/// thinking (the engine auto-picks after `decisionTicks`).
typedef Controller = int? Function(AtbBattle battle, int side);

/// Auto-pick used on timeout and by おまかせ (set by ai_v2.dart).
typedef AutoPicker = int Function(AtbBattle battle, int side, Mulberry32 rng);

class AtbBattle {
  AtbBattle(
    this.spec,
    FighterSetupV2 a,
    FighterSetupV2 b, {
    required int seed,
    required this.autoPick,
    this.recordEvents = false,
  }) : fighters = [FighterV2(spec, a), FighterV2(spec, b)],
       rng = Mulberry32(deriveSeed(seed, 0)),
       aiRng = [
         Mulberry32(deriveSeed(seed, 1)),
         Mulberry32(deriveSeed(seed, 2)),
       ];

  final V2Spec spec;
  final List<FighterV2> fighters;
  final Mulberry32 rng;
  final List<Mulberry32> aiRng;
  final AutoPicker autoPick;
  final bool recordEvents;
  final List<BattleEventV2> events = [];
  int tick = 0;
  int? winner;
  String? endReason;

  bool get finished => winner != null;

  void _ev(String type, Map<String, Object?> data) {
    if (recordEvents) events.add(BattleEventV2(tick, type, data));
  }

  /// Effective stat with buff stages.
  int eff(int side, Stat st) {
    final f = fighters[side];
    final v = f.stats[st.index];
    final n = f.stages[st.index];
    final d = spec.stageDen;
    final r = n >= 0 ? v * (d + n) ~/ d : v * d ~/ (d - n);
    return r < 1 ? 1 : r;
  }

  /// Relative-rate helper: base·(100(x+y) + w(x−y)) / (100(x+y)).
  int _rel(int base, int x, int y, int weightPct) {
    final sum = x + y;
    if (sum <= 0) return base;
    return base * (100 * sum + weightPct * (x - y)) ~/ (100 * sum);
  }

  int fillRate(int side) {
    var r = _rel(
      spec.gaugeFillPerTick,
      eff(side, Stat.agi),
      eff(1 - side, Stat.agi),
      spec.agiWeightPct,
    );
    if (fighters[side].paralyzeTicks > 0) r = r * spec.paralyzeFillPct ~/ 100;
    return r;
  }

  int heatPct() => tick <= spec.heatUpStartTick
      ? 100
      : 100 +
            spec.heatUpPctPerSecond *
                ((tick - spec.heatUpStartTick) ~/ spec.tickHz);

  /// Runs to the end with [ca] / [cb] as controllers. Returns the winner.
  int run(Controller ca, Controller cb) {
    while (!finished) {
      step(ca, cb);
    }
    return winner!;
  }

  /// Advances one tick (100 ms). Order (normative):
  /// 1 timers & poison (a, b) · 2 SP regen · 3 gauge fill · 4 decisions of
  /// ready fighters (a, b) · 5 resolutions due this tick (order a, b; when
  /// both resolve, one `nextInt(2)` picks who goes first) · 6 hard cap.
  void step(Controller ca, Controller cb) {
    if (finished) return;
    tick++;
    // 1. timers
    for (var i = 0; i < 2 && !finished; i++) {
      final f = fighters[i];
      for (var k = 0; k < f.cooldowns.length; k++) {
        if (f.cooldowns[k] > 0) f.cooldowns[k]--;
      }
      for (var k = 0; k < 10; k++) {
        if (f.stageTicks[k] > 0 && --f.stageTicks[k] == 0) f.stages[k] = 0;
      }
      if (f.shieldTicks > 0 && --f.shieldTicks == 0) f.shieldPct = 0;
      if (f.paralyzeTicks > 0) f.paralyzeTicks--;
      if (f.poisonTicks > 0) {
        f.poisonTicks--;
        if (f.poisonTicks % spec.tickHz == 0) {
          final d = f.maxHp * spec.poisonMillePerSecond ~/ 1000;
          _hurt(i, d < 1 ? 1 : d, 'poison');
        }
      }
    }
    if (finished) return;
    // 2. SP regen
    for (var i = 0; i < 2; i++) {
      final f = fighters[i];
      final r = _rel(
        spec.spRegenCentiPerTick,
        f.stats[Stat.sp.index],
        fighters[1 - i].stats[Stat.sp.index],
        spec.spWeightPct,
      );
      f.sp = (f.sp + r).clamp(0, spec.spMaxCenti);
    }
    // 3. gauges
    for (var i = 0; i < 2; i++) {
      final f = fighters[i];
      if (f.phase != Phase.charging) continue;
      f.gauge += fillRate(i);
      if (f.gauge >= spec.gaugeMax) {
        f.gauge = spec.gaugeMax;
        f.phase = Phase.ready;
        f.readyTicks = 0;
        _ev('ready', {'side': i});
      }
    }
    // 4. decisions
    final due = <int>[];
    for (var i = 0; i < 2; i++) {
      final f = fighters[i];
      if (f.phase == Phase.casting) {
        if (--f.castLeft <= 0) due.add(i);
        continue;
      }
      if (f.phase != Phase.ready) continue;
      var slot = (i == 0 ? ca : cb)(this, i);
      if (slot != null &&
          (slot < 0 || slot >= f.moves.length || !f.usable(slot))) {
        slot = null; // invalid input is ignored
      }
      if (slot == null) {
        f.readyTicks++;
        if (f.readyTicks < spec.decisionTicks) continue;
        slot = autoPick(this, i, aiRng[i]);
        f.autoPicks++;
        _ev('autoPick', {'side': i});
      }
      final m = f.moves[slot];
      f.sp -= m.spCost * 100;
      f.castSlot = slot;
      f.actions++;
      _ev('choose', {'side': i, 'slot': slot, 'cast': m.castTicks});
      if (m.castTicks > 0) {
        f.phase = Phase.casting;
        f.castLeft = m.castTicks;
      } else {
        due.add(i);
      }
    }
    // 5. resolutions
    if (due.length == 2 && rng.nextInt(2) == 1) {
      due.setAll(0, [due[1], due[0]]);
    }
    for (final i in due) {
      if (finished) break;
      _resolve(i);
    }
    // 6. hard cap
    if (!finished && tick >= spec.hardCapTick) {
      final a = fighters[0];
      final b = fighters[1];
      final l = a.hp * b.maxHp;
      final r = b.hp * a.maxHp;
      _end(l > r ? 0 : (r > l ? 1 : rng.nextInt(2)), 'timeUp');
    }
  }

  void _end(int w, String reason) {
    winner = w;
    endReason = reason;
    _ev('end', {'winner': w, 'reason': reason});
  }

  void _hurt(int side, int amount, String cause) {
    final f = fighters[side];
    f.hp = f.hp - amount < 0 ? 0 : f.hp - amount;
    _ev('damage', {
      'target': side,
      'amount': amount,
      'hp': f.hp,
      'cause': cause,
    });
    if (f.hp == 0 && !finished) _end(1 - side, 'ko');
  }

  void _resolve(int i) {
    final f = fighters[i];
    final slot = f.castSlot;
    final m = f.moves[slot];
    f.phase = Phase.charging;
    f.gauge = 0;
    f.castSlot = -1;
    f.cooldowns[slot] = m.cooldownTicks;
    _ev('move', {'side': i, 'slot': slot, 'template': m.template});
    final t = 1 - i;
    switch (m.kind) {
      case MoveKind.physical:
      case MoveKind.special:
        _damageMove(i, t, m);
      case MoveKind.heal:
        final steps = spec.healDecaySteps;
        final decay =
            steps[f.healUses < steps.length ? f.healUses : steps.length - 1];
        f.healUses++;
        final intl = eff(i, Stat.intl);
        final str = eff(i, Stat.str);
        final scale = 75 + 50 * intl ~/ (intl + str);
        final heat = heatPct();
        final fade = heat >= 200 ? 0 : 200 - heat; // heals fade during heat-up
        var amt = f.maxHp * m.healPct * scale * decay ~/ 1000000 * fade ~/ 100;
        if (f.hp + amt > f.maxHp) amt = f.maxHp - f.hp;
        f.hp += amt;
        _ev('heal', {'side': i, 'amount': amt, 'hp': f.hp});
      case MoveKind.buff:
        _stage(i, m.stat, m.stages, m.durationTicks);
      case MoveKind.debuff:
        if (_hits(i, t, m.accuracy)) {
          _stage(t, m.stat, -m.stages, m.durationTicks);
        } else {
          _ev('miss', {'side': i});
        }
      case MoveKind.status:
        if (_hits(i, t, m.accuracy)) {
          _tryStatus(i, t, m.status!, m.chance);
        } else {
          _ev('miss', {'side': i});
        }
      case MoveKind.shield:
        f.shieldPct = m.shieldPct;
        f.shieldTicks = m.durationTicks;
        _ev('shield', {'side': i, 'pct': m.shieldPct});
    }
  }

  void _stage(int side, Stat st, int delta, int ticks) {
    final f = fighters[side];
    final n = (f.stages[st.index] + delta).clamp(-spec.maxStage, spec.maxStage);
    f.stages[st.index] = n;
    f.stageTicks[st.index] = ticks;
    _ev('stage', {'side': side, 'stat': st.code, 'stage': n});
  }

  /// Hit roll: hit% = acc + skew·(DEX_a − EVA_d)/(DEX_a + EVA_d), EVA =
  /// (AGI + LUK)/2, clamped to [hitMinPct, 100]. Always draws nextInt(100).
  bool _hits(int a, int d, int acc) {
    final dex = eff(a, Stat.dex);
    final eva = (eff(d, Stat.agi) + eff(d, Stat.luk)) ~/ 2;
    final sum = dex + eva;
    // acc >= 60 > hitSkewPct, so the numerator is always positive.
    var hit = (acc * sum + spec.hitSkewPct * (dex - eva)) ~/ sum;
    if (hit < spec.hitMinPct) hit = spec.hitMinPct;
    if (hit > 100) hit = 100;
    return rng.nextInt(100) < hit;
  }

  void _tryStatus(int a, int d, StatusKind k, int chance) {
    final luk = eff(a, Stat.luk);
    final vit = eff(d, Stat.vit);
    final p = _rel(chance, luk, vit, spec.statusLukSkewPct);
    if (rng.nextInt(100) >= p) return;
    final f = fighters[d];
    if (k == StatusKind.poison) {
      f.poisonTicks = spec.poisonTicks;
    } else {
      f.paralyzeTicks = spec.paralyzeTicks;
    }
    _ev('status', {'target': d, 'status': k.name});
  }

  /// Raw damage of one hit without RNG (also used by the AI).
  int baseHitDamage(int a, int d, MoveV2 m) {
    final fa = m.atkFormula;
    var atk = (eff(a, fa.a) * fa.pa + eff(a, fa.b) * fa.pb) ~/ 100;
    if (atk < 1) atk = 1;
    final def = eff(d, m.kind == MoveKind.physical ? Stat.def : Stat.res);
    final typePct = spec.typePct(typeChart(m.attr, fighters[d].attr, spec));
    final perHit = m.power ~/ m.hits;
    final raw = perHit * 2 * atk * atk ~/ (atk + def) ~/ 100;
    return raw * spec.damageScalePct * typePct ~/ 10000;
  }

  void _damageMove(int a, int d, MoveV2 m) {
    var landed = 0;
    var total = 0;
    final tf = fighters[d];
    for (var h = 0; h < m.hits && !finished; h++) {
      final hit = _hits(a, d, m.accuracy);
      final la = eff(a, Stat.luk);
      final ld = eff(d, Stat.luk);
      final critNum =
          spec.critBaseMille * (la + ld) + spec.critLukMille * (la - ld);
      final critM =
          (critNum <= 0 ? 0 : critNum ~/ (la + ld)) + m.critBonus * 10;
      final crit = rng.nextInt(1000) < critM;
      final variance = spec.varianceMinPct + rng.nextInt(spec.varianceSpan);
      if (!hit) {
        _ev('miss', {'side': a});
        continue;
      }
      var dmg = baseHitDamage(a, d, m);
      if (crit) dmg = dmg * spec.critMultiplierPct ~/ 100;
      dmg = dmg * variance ~/ 100;
      if (tf.shieldPct > 0) dmg = dmg * (100 - tf.shieldPct) ~/ 100;
      dmg = dmg * heatPct() ~/ 100;
      if (dmg < 1) dmg = 1;
      landed++;
      total += dmg;
      if (crit) _ev('crit', {'side': a});
      _hurt(d, dmg, 'move');
    }
    if (landed == 0 || finished) return;
    switch (m.secondary) {
      case SecondaryType.none:
        break;
      case SecondaryType.poison:
        _tryStatus(a, d, StatusKind.poison, m.secondaryChance);
      case SecondaryType.paralyze:
        _tryStatus(a, d, StatusKind.paralyze, m.secondaryChance);
      case SecondaryType.debuff:
        if (rng.nextInt(100) < m.secondaryChance) {
          _stage(d, m.secondaryStat, -1, 60);
        }
      case SecondaryType.drain:
        final f = fighters[a];
        var h = total * m.drainPct ~/ 100;
        if (f.hp + h > f.maxHp) h = f.maxHp - f.hp;
        f.hp += h;
        _ev('heal', {'side': a, 'amount': h, 'hp': f.hp});
    }
  }
}

/// Raw triangle multiplier (%) of [move] attribute against [defender].
int typeChart(Attr move, Attr defender, V2Spec s) {
  if (move == Attr.none || defender == Attr.none) return 100;
  if (move.beats == defender) return s.typeAdvantagePct;
  if (defender.beats == move) return s.typeDisadvantagePct;
  return 100;
}
