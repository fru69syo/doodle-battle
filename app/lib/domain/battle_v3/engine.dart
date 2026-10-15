/// Real-time battle with stackable gauge bars, spec v4 (engine v3): a fixed
/// 10 Hz tick and integer maths only (docs/GAME_DESIGN_V2.md §6,
/// docs/BATTLE_V3.md). Pure Dart, no Flutter.
///
/// Usage (client, server and simulator use the same object):
///
/// ```dart
/// final b = Battle(spec, setupA, setupB, seed: seed);
/// b.queueInput(0, 1);                    // a tap / さきどり (any time;
///                                        // fires when enough bars)
/// final events = b.step(b: cpu);         // one 100 ms tick
/// ```
///
/// Each [step] runs the normative tick order (§6.1) and returns the events
/// of that tick (also appended to [events] when [Battle.recordEvents]).
/// The TS port (`shared/battle_engine_v3_ts/src/engine.ts`) is bit-exact;
/// golden vectors in `shared/battle_spec_v3/golden_vectors.json`.
library;

import 'genome.dart';
import 'moves.dart';
import 'rng.dart';
import 'spec.dart';

/// What one fighter brings into a battle.
class FighterSetup {
  const FighterSetup({
    required this.stats,
    required this.attr,
    required this.moves,
    required this.maxBars,
    this.label = '',
  });

  /// Ten stats in [Stat] order (already at the battle level).
  final List<int> stats;
  final Attr attr;

  /// Unlocked moves only (2..4). Slot 0 costs 1 bar and has no cooldown.
  final List<Move> moves;

  /// Gauge bars this fighter can stack (2..5, from its Lv1 base SP).
  final int maxBars;
  final String label;

  FighterSetup withStats(List<int> s) => FighterSetup(
    stats: s,
    attr: attr,
    moves: moves,
    maxBars: maxBars,
    label: label,
  );

  Map<String, Object?> toJson() => {
    'stats': stats,
    'attribute': attr.name,
    'maxBars': maxBars,
    'moves': [for (final m in moves) m.toJson()],
  };

  factory FighterSetup.fromJson(Map<String, Object?> j) => FighterSetup(
    stats: (j['stats']! as List).cast<int>(),
    attr: Attr.values.byName(j['attribute']! as String),
    maxBars: j['maxBars']! as int,
    moves: [
      for (final m in j['moves']! as List)
        Move.fromJson((m as Map).cast<String, Object?>()),
    ],
    label: j['label'] as String? ?? '',
  );
}

/// Gauge state of a fighter: filling (or full) / casting a move.
enum Phase { charging, casting }

/// Runtime state of one side.
class Fighter {
  Fighter(V3Spec s, this.setup)
    : stats = List.of(setup.stats),
      maxHp = maxHpOf(s, setup.stats),
      hp = maxHpOf(s, setup.stats),
      gaugePerBar = s.gaugeMax,
      cooldowns = List.filled(setup.moves.length, 0);

  final FighterSetup setup;
  final List<int> stats;
  final int maxHp;
  int hp;

  /// Gauge units of one bar ([V3Spec.gaugeMax]).
  final int gaugePerBar;

  /// 0..maxBars·gaugePerBar. Stops filling at the cap and while casting.
  int gauge = 0;
  Phase phase = Phase.charging;

  /// Ticks this fighter has had at least one full bar without acting
  /// (reset when it acts). The AI's "thinking time" reads it.
  int waitTicks = 0;
  int castSlot = -1;
  int castLeft = 0;

  /// Pre-selected / submitted move (さきどり): used on the first tick it
  /// is usable (enough bars, no cooldown), then cleared.
  int? queued;

  /// The AI's chosen next move while it saves bars for it (おまかせ / CPU
  /// controllers only; cleared when the fighter acts). Not in [stateHash].
  int? aiPlan;
  final List<int> cooldowns;
  final List<int> stages = List.filled(10, 0);
  final List<int> stageTicks = List.filled(10, 0);
  int poisonTicks = 0;
  int paralyzeTicks = 0;
  int shieldPct = 0;
  int shieldTicks = 0;
  int healUses = 0;
  int actions = 0;

  List<Move> get moves => setup.moves;
  Attr get attr => setup.attr;
  int get maxBars => setup.maxBars;

  /// Full bars right now.
  int get bars => gauge ~/ gaugePerBar;

  /// Bars a move of [slot] costs (0 for an invalid slot).
  int costOf(int slot) =>
      slot >= 0 && slot < moves.length ? moves[slot].bars : 0;

  /// [slot] can ever be used (valid, and its cost fits the max bars):
  /// what さきどり may queue.
  bool canQueue(int slot) =>
      slot >= 0 && slot < moves.length && moves[slot].bars <= maxBars;

  /// [slot] can be used right now: enough bars and no cooldown (the
  /// caller checks that the fighter is not casting).
  bool usable(int slot) =>
      canQueue(slot) &&
      cooldowns[slot] == 0 &&
      gauge >= moves[slot].bars * gaugePerBar;

  /// Not on cooldown and affordable within the max bars (what the AI may
  /// plan to save for).
  bool eligible(int slot) => canQueue(slot) && cooldowns[slot] == 0;

  Map<String, Object?> snapshot() => {
    'hp': hp,
    'gauge': gauge,
    'phase': phase.name,
    'waitTicks': waitTicks,
    'castSlot': castSlot,
    'castLeft': castLeft,
    'queued': queued,
    'aiPlan': aiPlan,
    'cooldowns': List.of(cooldowns),
    'stages': List.of(stages),
    'stageTicks': List.of(stageTicks),
    'poisonTicks': poisonTicks,
    'paralyzeTicks': paralyzeTicks,
    'shieldPct': shieldPct,
    'shieldTicks': shieldTicks,
    'healUses': healUses,
    'actions': actions,
  };

  void restore(Map<String, Object?> j) {
    List<int> li(String k) => (j[k]! as List).cast<int>();
    hp = j['hp']! as int;
    gauge = j['gauge']! as int;
    phase = Phase.values.byName(j['phase']! as String);
    waitTicks = j['waitTicks']! as int;
    castSlot = j['castSlot']! as int;
    castLeft = j['castLeft']! as int;
    queued = j['queued'] as int?;
    aiPlan = j['aiPlan'] as int?;
    cooldowns.setAll(0, li('cooldowns'));
    stages.setAll(0, li('stages'));
    stageTicks.setAll(0, li('stageTicks'));
    poisonTicks = j['poisonTicks']! as int;
    paralyzeTicks = j['paralyzeTicks']! as int;
    shieldPct = j['shieldPct']! as int;
    shieldTicks = j['shieldTicks']! as int;
    healUses = j['healUses']! as int;
    actions = j['actions']! as int;
  }
}

/// Event types (docs/BATTLE_V3.md §Events). Data keys per type:
///
/// | type | data |
/// |---|---|
/// | bar | side, bars (a bar became full; bars = full bars now) |
/// | inputIgnored | side, slot (queued input that can never be used) |
/// | select | side, slot, cost (bars spent), cast |
/// | moveStart | side, slot, template, attr |
/// | effective | side, target, pct (150 / 75: triangle, once per move) |
/// | hit | side, target, n, amount, hp, crit (0/1), pct |
/// | miss | side, target, n |
/// | dot | target, amount, hp (poison tick) |
/// | heal | side, amount, hp, source (move / drain) |
/// | stage | side, stat, stage, ticks |
/// | status | target, status (poison / paralyze), ticks |
/// | statusFail | target, status |
/// | shield | side, pct, ticks |
/// | expire | side, kind (poison / paralyze / shield / STR …) |
/// | heatUp | (none) — first tick of the damage ramp |
/// | faint | side |
/// | end | winner, reason (ko / timeUp) |
class BattleEvent {
  const BattleEvent(this.tick, this.type, this.data);

  /// Tick (1-based; tick t happens at t × 100 ms).
  final int tick;
  final String type;

  /// int or String values only.
  final Map<String, Object> data;

  int? i(String k) => data[k] as int?;
  String? s(String k) => data[k] as String?;

  Map<String, Object?> toJson() => {'tick': tick, 'type': type, ...data};

  /// Canonical line `"<tick> <type> k=v,..."` with keys sorted (golden
  /// vectors hash these joined with '\n').
  String get line {
    final keys = data.keys.toList()..sort();
    return '$tick $type ${keys.map((k) => '$k=${data[k]}').join(',')}';
  }

  @override
  String toString() => line;
}

/// FNV-1a over the canonical event lines joined with '\n'.
int eventsHash(Iterable<BattleEvent> events) =>
    fnv1a32(events.map((e) => e.line).join('\n'));

/// Decides a move for a fighter that is not casting, or returns null to
/// keep filling (there is no decision timer: an idle fighter just stops at
/// its max bars). Called every tick unless a queued さきどり input is
/// waiting. AI controllers live in `ai.dart`.
typedef Controller = int? Function(Battle battle, int side);

class Battle {
  Battle(
    this.spec,
    FighterSetup a,
    FighterSetup b, {
    required this.seed,
    this.recordEvents = true,
  }) : fighters = [Fighter(spec, a), Fighter(spec, b)],
       rng = Mulberry32(deriveSeed(seed, 0)),
       aiRng = [
         Mulberry32(deriveSeed(seed, 1)),
         Mulberry32(deriveSeed(seed, 2)),
       ] {
    for (final f in fighters) {
      if (f.moves.isEmpty || f.moves.length > 4) {
        throw ArgumentError('a fighter needs 1..4 moves');
      }
      if (f.maxBars < spec.minBars || f.maxBars > spec.maxBars) {
        throw ArgumentError('maxBars must be ${spec.minBars}..${spec.maxBars}');
      }
      for (final m in f.moves) {
        if (m.bars < 1 || m.bars > f.maxBars) {
          throw ArgumentError('a move costs 1..maxBars bars');
        }
      }
    }
  }

  final V3Spec spec;
  final int seed;
  final List<Fighter> fighters;
  Mulberry32 rng;
  final List<Mulberry32> aiRng;

  /// When true every event is also appended to [events].
  final bool recordEvents;
  final List<BattleEvent> events = [];
  final List<BattleEvent> _tickEvents = [];
  int tick = 0;
  int? winner;
  String? endReason;

  bool get finished => winner != null;

  /// Submits a move for [side] (a tap / さきどり, any time): used on the
  /// first tick the fighter has enough bars and the move is off cooldown.
  /// A newer input replaces an older one. A move that can never be used
  /// (bad slot, cost above the max bars) is dropped with `inputIgnored`.
  /// Ignored when finished.
  void queueInput(int side, int slot) {
    if (!finished) fighters[side].queued = slot;
  }

  void clearInput(int side) => fighters[side].queued = null;

  void _ev(String type, Map<String, Object> data) {
    final e = BattleEvent(tick, type, data);
    _tickEvents.add(e);
    if (recordEvents) events.add(e);
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

  /// Relative rate: base·(100(x+y) + w(x−y)) / (100(x+y)).
  int rel(int base, int x, int y, int weightPct) {
    final sum = x + y;
    if (sum <= 0) return base;
    return base * (100 * sum + weightPct * (x - y)) ~/ (100 * sum);
  }

  /// Gauge fill per tick (one bar = [V3Spec.gaugeMax]).
  int fillRate(int side) {
    var r = rel(
      spec.gaugeFillPerTick,
      eff(side, Stat.agi),
      eff(1 - side, Stat.agi),
      spec.agiWeightPct,
    );
    if (fighters[side].paralyzeTicks > 0) r = r * spec.paralyzeFillPct ~/ 100;
    return r;
  }

  /// Damage ramp (%) at the current tick.
  int heatPct() => tick <= spec.heatUpStartTick
      ? 100
      : 100 +
            spec.heatUpPctPerSecond *
                ((tick - spec.heatUpStartTick) ~/ spec.tickHz);

  /// Runs to the end. Returns the winner (0 = a, 1 = b).
  int run([Controller? ca, Controller? cb]) {
    while (!finished) {
      step(a: ca, b: cb);
    }
    return winner!;
  }

  /// Advances one tick (100 ms) and returns its events. Order (normative):
  /// 1 timers & poison (a, b) · 2 gauges fill (a, b; not while casting, up
  /// to maxBars) · 3 decisions (a, b; casting counts down; else the queued
  /// input when usable, else — when nothing is queued — the controller) ·
  /// 4 resolutions due this tick (a, b; when both resolve, one `nextInt(2)`
  /// = 1 swaps the order) · 5 the 3-minute cap (HP ratio).
  List<BattleEvent> step({Controller? a, Controller? b}) {
    _tickEvents.clear();
    if (finished) return const [];
    tick++;
    if (tick == spec.heatUpStartTick + 1) _ev('heatUp', const {});
    // 1. timers
    for (var i = 0; i < 2 && !finished; i++) {
      final f = fighters[i];
      for (var k = 0; k < f.cooldowns.length; k++) {
        if (f.cooldowns[k] > 0) f.cooldowns[k]--;
      }
      for (var k = 0; k < 10; k++) {
        if (f.stageTicks[k] > 0 && --f.stageTicks[k] == 0) {
          f.stages[k] = 0;
          _ev('expire', {'side': i, 'kind': Stat.values[k].code});
        }
      }
      if (f.shieldTicks > 0 && --f.shieldTicks == 0) {
        f.shieldPct = 0;
        _ev('expire', {'side': i, 'kind': 'shield'});
      }
      if (f.paralyzeTicks > 0 && --f.paralyzeTicks == 0) {
        _ev('expire', {'side': i, 'kind': 'paralyze'});
      }
      if (f.poisonTicks > 0) {
        f.poisonTicks--;
        if (f.poisonTicks % spec.tickHz == 0) {
          final d = f.maxHp * spec.poisonMillePerSecond ~/ 1000;
          _hurt(i, d < 1 ? 1 : d, 'dot', const {});
        }
        if (f.poisonTicks == 0 && !finished) {
          _ev('expire', {'side': i, 'kind': 'poison'});
        }
      }
    }
    if (finished) return List.of(_tickEvents);
    // 2. gauges
    for (var i = 0; i < 2; i++) {
      final f = fighters[i];
      if (f.phase != Phase.charging) continue;
      final cap = f.maxBars * spec.gaugeMax;
      if (f.gauge >= cap) continue;
      final before = f.gauge ~/ spec.gaugeMax;
      final g = f.gauge + fillRate(i);
      f.gauge = g > cap ? cap : g;
      final after = f.gauge ~/ spec.gaugeMax;
      if (after > before) _ev('bar', {'side': i, 'bars': after});
    }
    // 3. decisions
    final due = <int>[];
    for (var i = 0; i < 2; i++) {
      final f = fighters[i];
      if (f.phase == Phase.casting) {
        if (--f.castLeft <= 0) due.add(i);
        continue;
      }
      int? slot;
      final q = f.queued;
      if (q != null) {
        if (!f.canQueue(q)) {
          f.queued = null;
          _ev('inputIgnored', {'side': i, 'slot': q});
        } else if (f.usable(q)) {
          f.queued = null;
          slot = q;
        }
      }
      if (slot == null && f.queued == null) {
        final c = i == 0 ? a : b;
        final s = c?.call(this, i);
        if (s != null && f.usable(s)) slot = s;
      }
      if (slot == null) {
        f.waitTicks = f.gauge >= spec.gaugeMax ? f.waitTicks + 1 : 0;
        continue;
      }
      final m = f.moves[slot];
      f.gauge -= m.bars * spec.gaugeMax;
      f.castSlot = slot;
      f.waitTicks = 0;
      f.aiPlan = null;
      f.actions++;
      _ev('select', {
        'side': i,
        'slot': slot,
        'cost': m.bars,
        'cast': m.castTicks,
      });
      if (m.castTicks > 0) {
        f.phase = Phase.casting;
        f.castLeft = m.castTicks;
      } else {
        due.add(i);
      }
    }
    // 4. resolutions
    if (due.length == 2 && rng.nextInt(2) == 1) {
      due.setAll(0, [due[1], due[0]]);
    }
    for (final i in due) {
      if (finished) break;
      _resolve(i);
    }
    // 5. hard cap: higher HP ratio wins; an exact tie is a coin flip.
    if (!finished && tick >= spec.hardCapTick) {
      final fa = fighters[0];
      final fb = fighters[1];
      final l = fa.hp * fb.maxHp;
      final r = fb.hp * fa.maxHp;
      _end(l > r ? 0 : (r > l ? 1 : rng.nextInt(2)), 'timeUp');
    }
    return List.of(_tickEvents);
  }

  void _end(int w, String reason) {
    winner = w;
    endReason = reason;
    for (final f in fighters) {
      f.queued = null;
    }
    _ev('end', {'winner': w, 'reason': reason});
  }

  void _hurt(int side, int amount, String type, Map<String, Object> extra) {
    final f = fighters[side];
    f.hp = f.hp - amount < 0 ? 0 : f.hp - amount;
    _ev(type, {...extra, 'target': side, 'amount': amount, 'hp': f.hp});
    if (f.hp == 0 && !finished) {
      _ev('faint', {'side': side});
      _end(1 - side, 'ko');
    }
  }

  void _resolve(int i) {
    final f = fighters[i];
    final slot = f.castSlot;
    final m = f.moves[slot];
    f.phase = Phase.charging;
    f.castSlot = -1;
    f.cooldowns[slot] = m.cooldownTicks;
    _ev('moveStart', {
      'side': i,
      'slot': slot,
      'template': m.template,
      'attr': m.attr.name,
    });
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
        final fade = heat >= 200 ? 0 : 200 - heat; // heals fade in heat-up
        var amt = f.maxHp * m.healPct * scale * decay ~/ 1000000 * fade ~/ 100;
        if (f.hp + amt > f.maxHp) amt = f.maxHp - f.hp;
        f.hp += amt;
        _ev('heal', {'side': i, 'amount': amt, 'hp': f.hp, 'source': 'move'});
      case MoveKind.buff:
        _stage(i, m.stat, m.stages, m.durationTicks);
      case MoveKind.debuff:
        if (_hits(i, t, m.accuracy)) {
          _stage(t, m.stat, -m.stages, m.durationTicks);
        } else {
          _ev('miss', {'side': i, 'target': t, 'n': 0});
        }
      case MoveKind.status:
        if (_hits(i, t, m.accuracy)) {
          _tryStatus(i, t, m.status!, m.chance);
        } else {
          _ev('miss', {'side': i, 'target': t, 'n': 0});
        }
      case MoveKind.shield:
        f.shieldPct = m.shieldPct;
        f.shieldTicks = m.durationTicks;
        _ev('shield', {
          'side': i,
          'pct': m.shieldPct,
          'ticks': m.durationTicks,
        });
    }
  }

  void _stage(int side, Stat st, int delta, int ticks) {
    final f = fighters[side];
    final n = (f.stages[st.index] + delta).clamp(-spec.maxStage, spec.maxStage);
    f.stages[st.index] = n;
    f.stageTicks[st.index] = ticks;
    _ev('stage', {'side': side, 'stat': st.code, 'stage': n, 'ticks': ticks});
  }

  /// Hit chance (%) of [a] against [d] for a move of accuracy [acc]:
  /// acc + skew·(DEX_a − EVA_d)/(DEX_a + EVA_d), EVA = (AGI + LUK)/2,
  /// clamped to [hitMinPct, 100].
  int hitChance(int a, int d, int acc) {
    final dex = eff(a, Stat.dex);
    final eva = (eff(d, Stat.agi) + eff(d, Stat.luk)) ~/ 2;
    final sum = dex + eva;
    // acc >= 60 > hitSkewPct, so the numerator is always positive.
    var hit = (acc * sum + spec.hitSkewPct * (dex - eva)) ~/ sum;
    if (hit < spec.hitMinPct) hit = spec.hitMinPct;
    if (hit > 100) hit = 100;
    return hit;
  }

  /// Hit roll. Always draws nextInt(100).
  bool _hits(int a, int d, int acc) => rng.nextInt(100) < hitChance(a, d, acc);

  /// Crit chance (‰) of [a] against [d] with [critBonus].
  int critMille(int a, int d, int critBonus) {
    final la = eff(a, Stat.luk);
    final ld = eff(d, Stat.luk);
    final critNum =
        spec.critBaseMille * (la + ld) + spec.critLukMille * (la - ld);
    return (critNum <= 0 ? 0 : critNum ~/ (la + ld)) + critBonus * 10;
  }

  void _tryStatus(int a, int d, StatusKind k, int chance) {
    final luk = eff(a, Stat.luk);
    final vit = eff(d, Stat.vit);
    final p = rel(chance, luk, vit, spec.statusLukSkewPct);
    if (rng.nextInt(100) >= p) {
      _ev('statusFail', {'target': d, 'status': k.name});
      return;
    }
    final f = fighters[d];
    final ticks = k == StatusKind.poison
        ? spec.poisonTicks
        : spec.paralyzeTicks;
    if (k == StatusKind.poison) {
      f.poisonTicks = ticks;
    } else {
      f.paralyzeTicks = ticks;
    }
    _ev('status', {'target': d, 'status': k.name, 'ticks': ticks});
  }

  /// Triangle multiplier (%) of [m] against side [d] (after
  /// `typeStrengthPct`).
  int typePctAgainst(Move m, int d) =>
      spec.typePct(typeChart(m.attr, fighters[d].attr, spec));

  /// Damage of one hit before RNG, crit, shield and heat (used by the AI).
  int baseHitDamage(int a, int d, Move m) {
    final fa = m.atkFormula;
    var atk = (eff(a, fa.a) * fa.pa + eff(a, fa.b) * fa.pb) ~/ 100;
    if (atk < 1) atk = 1;
    final def = eff(d, m.kind == MoveKind.physical ? Stat.def : Stat.res);
    final perHit = m.power ~/ m.hits;
    final raw = perHit * 2 * atk * atk ~/ (atk + def) ~/ 100;
    return raw * spec.damageScalePct * typePctAgainst(m, d) ~/ 10000;
  }

  void _damageMove(int a, int d, Move m) {
    final pct = typePctAgainst(m, d);
    if (pct != 100) _ev('effective', {'side': a, 'target': d, 'pct': pct});
    var landed = 0;
    var total = 0;
    final tf = fighters[d];
    for (var h = 0; h < m.hits && !finished; h++) {
      final hit = _hits(a, d, m.accuracy);
      final crit = rng.nextInt(1000) < critMille(a, d, m.critBonus);
      final variance = spec.varianceMinPct + rng.nextInt(spec.varianceSpan);
      if (!hit) {
        _ev('miss', {'side': a, 'target': d, 'n': h});
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
      _hurt(d, dmg, 'hit', {
        'side': a,
        'n': h,
        'crit': crit ? 1 : 0,
        'pct': pct,
      });
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
          _stage(d, m.secondaryStat, -1, kDebuffSecondaryTicks);
        }
      case SecondaryType.drain:
        final f = fighters[a];
        var h = total * m.drainPct ~/ 100;
        if (f.hp + h > f.maxHp) h = f.maxHp - f.hp;
        f.hp += h;
        _ev('heal', {'side': a, 'amount': h, 'hp': f.hp, 'source': 'drain'});
    }
  }

  /// Serialisable state (server persistence / reconnect). Restore with
  /// [restore] on a battle built from the same setups and seed.
  Map<String, Object?> snapshot() => {
    'tick': tick,
    'rng': rng.state,
    'aiRng': [aiRng[0].state, aiRng[1].state],
    'winner': winner,
    'endReason': endReason,
    'fighters': [for (final f in fighters) f.snapshot()],
  };

  void restore(Map<String, Object?> j) {
    tick = j['tick']! as int;
    rng = Mulberry32(j['rng']! as int);
    final ai = (j['aiRng']! as List).cast<int>();
    aiRng[0] = Mulberry32(ai[0]);
    aiRng[1] = Mulberry32(ai[1]);
    winner = j['winner'] as int?;
    endReason = j['endReason'] as String?;
    final fs = j['fighters']! as List;
    for (var i = 0; i < 2; i++) {
      fighters[i].restore((fs[i] as Map).cast<String, Object?>());
    }
  }

  /// FNV-1a of the canonical state (periodic desync check online).
  int stateHash() {
    final parts = <String>['$tick', '${rng.state}'];
    for (final f in fighters) {
      parts.add(
        [
          f.hp,
          f.gauge,
          f.phase.index,
          f.waitTicks,
          f.castSlot,
          f.castLeft,
          ...f.cooldowns,
          ...f.stages,
          ...f.stageTicks,
          f.poisonTicks,
          f.paralyzeTicks,
          f.shieldPct,
          f.shieldTicks,
          f.healUses,
        ].join(','),
      );
    }
    return fnv1a32(parts.join('|'));
  }
}

/// Raw triangle multiplier (%) of a [move] attribute against [defender].
int typeChart(Attr move, Attr defender, V3Spec s) {
  if (move == Attr.none || defender == Attr.none) return 100;
  if (move.beats == defender) return s.typeAdvantagePct;
  if (defender.beats == move) return s.typeDisadvantagePct;
  return 100;
}
