// Generates shared/battle_spec/golden_vectors.json from the Dart engine.
//
//   cd app && dart run tool/gen_golden_vectors.dart
//
// Each battle vector declares what it must exercise (a predicate over its
// events); the generator searches seeds until the predicate holds, so a
// spec change that breaks a scenario's intent fails loudly here instead of
// silently producing a vector that no longer covers the case.
// Both the Dart and the TS test suites replay every vector.
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';

late BattleSpec spec;
final vectors = <Map<String, Object?>>[];

typedef Turns = List<(BattleAction, BattleAction)>;
typedef Pred = bool Function(List<List<BattleEvent>> events, BattleState end);

FighterSetup fs(
  ElementType e, {
  int level = 1,
  int hp = 90,
  int atk = 90,
  int def = 90,
  int spd = 90,
}) => FighterSetup(
  element: e,
  level: level,
  stats: Stats(hp: hp, atk: atk, def: def, spd: spd),
);

bool has(List<List<BattleEvent>> ev, bool Function(BattleEvent) f) =>
    ev.expand((t) => t).any(f);

void battle(
  String name,
  String description, {
  required FighterSetup a,
  required FighterSetup b,
  required Turns turns,
  BattleState Function(BattleState)? patch,
  Pred? require,
  bool stopAtEnd = true,
}) {
  final initial0 = initBattle(spec, a, b);
  final initial = patch == null ? initial0 : patch(initial0);
  for (var seed = 1; seed < 200000; seed++) {
    final rng = Mulberry32(seed);
    var state = initial;
    final events = <List<BattleEvent>>[];
    final used = <List<String>>[];
    for (final (x, y) in turns) {
      if (state.isOver && stopAtEnd) break;
      final r = resolveTurn(spec, state, x, y, rng);
      state = r.state;
      events.add(r.events);
      used.add([x.name, y.name]);
    }
    if (require != null && !require(events, state)) continue;
    vectors.add({
      'kind': 'battle',
      'name': name,
      'description': description,
      'seed': seed,
      'setup': {'a': a.toJson(), 'b': b.toJson()},
      'initialFromSetup': patch == null,
      'initial': initial.toJson(),
      'turns': used,
      'expected': {
        'events': [
          for (final t in events) [for (final e in t) e.toJson()],
        ],
        'final': state.toJson(),
        'rngState': rng.state,
      },
    });
    return;
  }
  throw StateError('no seed satisfies vector "$name"');
}

void aiVector(
  String name,
  BattleState state,
  Side side,
  AiTier tier, {
  BattleAction? expect,
}) {
  for (var seed = 1; seed < 100000; seed++) {
    final rng = Mulberry32(seed);
    final action = chooseCpuAction(spec, state, side, tier, rng);
    if (expect != null && action != expect) continue;
    vectors.add({
      'kind': 'ai',
      'name': name,
      'seed': seed,
      'state': state.toJson(),
      'side': side.name,
      'tier': tier.name,
      'expected': {'action': action.name, 'rngState': rng.state},
    });
    return;
  }
  throw StateError('no seed for ai vector "$name"');
}

void xpVector(
  String name, {
  required int level,
  required int xp,
  required bool isShobo,
  required bool won,
  int stagePct = 100,
  bool adBoost = false,
}) {
  final gained = xpForBattle(
    spec,
    won: won,
    isShobo: isShobo,
    stageXpMultiplierPct: stagePct,
    adBoost: adBoost,
  );
  final p = addXp(spec, level: level, xp: xp, gained: gained);
  vectors.add({
    'kind': 'xp',
    'name': name,
    'input': {
      'level': level,
      'xp': xp,
      'isShobo': isShobo,
      'won': won,
      'stageXpMultiplierPct': stagePct,
      'adBoost': adBoost,
    },
    'expected': {'xpGained': gained, ...p.toJson()},
  });
}

void statsVector(
  String name,
  Stats base,
  int level,
  Map<StatKind, int> seeds, {
  bool isShobo = false,
}) {
  vectors.add({
    'kind': 'stats',
    'name': name,
    'input': {
      'base': base.toJson(),
      'level': level,
      'seeds': {for (final e in seeds.entries) e.key.name: e.value},
      'isShobo': isShobo,
    },
    'expected': {
      'stats': statsAtLevel(
        spec,
        base,
        level,
        seeds,
        isShobo: isShobo,
      ).toJson(),
      'maxStats': maxStatsAtLevel(spec, base, level, isShobo: isShobo).toJson(),
      'specialPower': specialPowerAt(spec, level),
      'stage': stageAtLevel(spec, level).name,
    },
  });
}

void main() {
  final specFile = File('../shared/battle_spec/battle_spec.json');
  spec = BattleSpec.fromJsonString(specFile.readAsStringSync());
  const t = BattleAction.tackle;
  const el = BattleAction.element;
  const g = BattleAction.guard;
  const sp = BattleAction.special;
  const to = BattleAction.timeout;

  // ---- PRNG / hashing -----------------------------------------------------
  for (final seed in [0, 1, 42, 0xDEADBEEF, 0xFFFFFFFF]) {
    final r = Mulberry32(seed);
    final u = [for (var i = 0; i < 8; i++) r.nextUint32()];
    final r2 = Mulberry32(seed);
    final ints = [
      for (final n in [2, 6, 100, 16, 1000, 7]) r2.nextInt(n),
    ];
    vectors.add({
      'kind': 'rng',
      'name': 'mulberry32 seed $seed',
      'input': {
        'seed': seed,
        'intBounds': [2, 6, 100, 16, 1000, 7],
      },
      'expected': {
        'uint32': u,
        'ints': ints,
        'stateAfterInts': r2.state,
        'deriveSeed': [for (var s = 0; s < 3; s++) deriveSeed(seed, s)],
      },
    });
  }
  for (final s in ['', 'match_abc123', 'らくがきバトル', '🎨doodle']) {
    vectors.add({
      'kind': 'fnv',
      'name': 'fnv1a32 "$s"',
      'input': s,
      'expected': fnv1a32(s),
    });
  }

  // ---- Damage formula -----------------------------------------------------
  for (final (name, input) in [
    ('neutral tackle', (40, 90, 90, 100, false, 100, 100)),
    ('super element min variance', (60, 120, 70, 150, false, 75, 100)),
    ('weak element crit', (60, 70, 120, 75, true, 88, 100)),
    ('special guarded', (140, 200, 50, 100, false, 100, 50)),
    ('min damage clamp', (40, 1, 999, 75, false, 75, 50)),
    ('huge stats', (140, 700, 1, 150, true, 100, 100)),
  ]) {
    final (power, atk, def, typePct, crit, variancePct, guardTakenPct) = input;
    vectors.add({
      'kind': 'damage',
      'name': name,
      'input': {
        'power': power,
        'atk': atk,
        'def': def,
        'typePct': typePct,
        'crit': crit,
        'variancePct': variancePct,
        'guardTakenPct': guardTakenPct,
      },
      'expected': computeDamage(
        spec,
        power: power,
        atk: atk,
        def: def,
        typePct: typePct,
        crit: crit,
        variancePct: variancePct,
        guardTakenPct: guardTakenPct,
      ),
    });
  }

  // ---- Type matchups: every unordered pair, both use ぞくせいわざ and hit --
  final els = ElementType.values;
  for (var i = 0; i < els.length; i++) {
    for (var j = i; j < els.length; j++) {
      final x = els[i], y = els[j];
      battle(
        'type ${x.name} vs ${y.name}',
        'Both use element; both hit; checks the type multiplier both ways.',
        a: fs(x, spd: 95),
        b: fs(y, spd: 85),
        turns: [(el, el)],
        require: (ev, _) =>
            ev[0].whereType<DamageEvent>().length == 2 &&
            !has(ev, (e) => e is CritEvent),
      );
    }
  }

  // ---- Speed order ----------------------------------------------------------
  battle(
    'speed a faster',
    'a (spd 120) acts before b (spd 60).',
    a: fs(ElementType.fire, spd: 120),
    b: fs(ElementType.water, spd: 60),
    turns: [(t, t)],
  );
  battle(
    'speed b faster',
    'b (spd 120) acts before a (spd 60).',
    a: fs(ElementType.fire, spd: 60),
    b: fs(ElementType.water, spd: 120),
    turns: [(t, t)],
  );
  battle(
    'speed tie -> a first',
    'Equal speed; rng tie roll picks a.',
    a: fs(ElementType.leaf),
    b: fs(ElementType.leaf),
    turns: [(t, t)],
    require: (ev, _) => (ev[0][1] as MoveEvent).side == Side.a,
  );
  battle(
    'speed tie -> b first',
    'Equal speed; rng tie roll picks b.',
    a: fs(ElementType.leaf),
    b: fs(ElementType.leaf),
    turns: [(t, t)],
    require: (ev, _) => (ev[0][1] as MoveEvent).side == Side.b,
  );

  // ---- Accuracy / crit ----------------------------------------------------
  battle(
    'element miss',
    'a uses element (90% acc) and misses; gets onMiss gauge.',
    a: fs(ElementType.thunder, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(el, t)],
    require: (ev, _) => has(ev, (e) => e is MissEvent && e.side == Side.a),
  );
  battle(
    'both miss',
    'Both element moves miss.',
    a: fs(ElementType.fire, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(el, el)],
    require: (ev, _) => ev[0].whereType<MissEvent>().length == 2,
  );
  battle(
    'crit',
    'a lands a critical tackle.',
    a: fs(ElementType.fire, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(t, t)],
    require: (ev, _) => has(ev, (e) => e is CritEvent && e.side == Side.a),
  );
  battle(
    'super effective crit',
    'Critical hit on a super-effective element move.',
    a: fs(ElementType.water, spd: 100),
    b: fs(ElementType.fire, spd: 80),
    turns: [(el, g)],
    require: (ev, _) => has(ev, (e) => e is CritEvent),
  );

  // ---- Guard --------------------------------------------------------------
  battle(
    'guard halves tackle',
    'b guards (50% taken) against a tackle.',
    a: fs(ElementType.fire, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(t, g)],
    require: (ev, _) => !has(ev, (e) => e is CritEvent),
  );
  battle(
    'consecutive guard diminishes',
    'b guards 4 turns in a row: 50/75/100/100% taken.',
    a: fs(ElementType.leaf, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(t, g), (t, g), (t, g), (t, g)],
    require: (ev, _) => !has(ev, (e) => e is CritEvent),
  );
  battle(
    'guard streak reset',
    'Guard, attack, guard: streak restarts at 50%.',
    a: fs(ElementType.leaf, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(t, g), (t, t), (t, g)],
  );
  battle(
    'both guard',
    'Both guard: no damage, only gauge from guarding.',
    a: fs(ElementType.fire),
    b: fs(ElementType.water),
    turns: [(g, g), (g, g)],
  );
  battle(
    'slower guard still applies first',
    'b is slower but its guard protects it from the faster a.',
    a: fs(ElementType.fire, spd: 150),
    b: fs(ElementType.leaf, spd: 10),
    turns: [(el, g)],
    require: (ev, _) => has(ev, (e) => e is DamageEvent && e.guarded),
  );

  // ---- Special gauge --------------------------------------------------------
  battle(
    'special ready',
    'a starts with a full gauge and uses ひっさつ.',
    a: fs(ElementType.rainbow, spd: 100),
    b: fs(ElementType.shadow, spd: 80),
    turns: [(sp, t)],
    patch: (s) => s.withFighter(Side.a, s.a.copyWith(gauge: 100)),
  );
  battle(
    'special not ready falls back to tackle',
    'a chooses ひっさつ with gauge 40 -> たいあたり.',
    a: fs(ElementType.fire, spd: 100),
    b: fs(ElementType.leaf, spd: 80),
    turns: [(sp, t)],
    patch: (s) => s.withFighter(Side.a, s.a.copyWith(gauge: 40)),
  );
  battle(
    'gauge builds then special',
    'Gauge accumulates from hits; a uses ひっさつ once full.',
    a: fs(ElementType.thunder, hp: 200, spd: 100),
    b: fs(ElementType.thunder, hp: 200, spd: 80),
    turns: [(t, t), (t, t), (t, t), (t, t), (sp, t), (t, t)],
    require: (ev, _) =>
        has(ev, (e) => e is MoveEvent && e.move == BattleAction.special),
  );
  battle(
    'special vs guard',
    'ひっさつ into まもる.',
    a: fs(ElementType.water, spd: 100),
    b: fs(ElementType.fire, spd: 80),
    turns: [(sp, g)],
    patch: (s) => s.withFighter(Side.a, s.a.copyWith(gauge: 100)),
  );
  battle(
    'densetsu special power',
    'Lv20 fighter: ひっさつ power 120 + 20.',
    a: fs(ElementType.leaf, level: 20, spd: 100),
    b: fs(ElementType.fire, level: 20, spd: 80),
    turns: [(sp, t)],
    patch: (s) => s.withFighter(Side.a, s.a.copyWith(gauge: 100)),
  );
  battle(
    'gauge caps at max',
    'Defender near full gauge gets clamped to max.',
    a: fs(ElementType.fire, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(t, t)],
    patch: (s) => s.withFighter(Side.b, s.b.copyWith(gauge: 95)),
  );

  // ---- Faint ----------------------------------------------------------------
  battle(
    'faint mid-turn: second actor does not act',
    'Faster a KOs b; b\'s attack is skipped.',
    a: fs(ElementType.fire, spd: 120),
    b: fs(ElementType.leaf, spd: 60),
    turns: [(el, sp)],
    patch: (s) => s.withFighter(Side.b, s.b.copyWith(hp: 20, gauge: 100)),
    require: (ev, end) => end.winner == Side.a,
  );
  battle(
    'slower side wins by KO',
    'Faster a misses/doesn\'t KO; slower b KOs a.',
    a: fs(ElementType.fire, spd: 120),
    b: fs(ElementType.water, spd: 60),
    turns: [(t, el)],
    patch: (s) => s.withFighter(Side.a, s.a.copyWith(hp: 10)),
    require: (ev, end) => end.winner == Side.b,
  );
  battle(
    'min damage',
    'Tiny atk vs huge def still deals minDamage.',
    a: fs(ElementType.fire, atk: 1, spd: 100),
    b: fs(ElementType.water, def: 999, spd: 80),
    turns: [(el, g)],
    require: (ev, _) => has(ev, (e) => e is DamageEvent),
  );

  // ---- Turn cap -------------------------------------------------------------
  battle(
    'turn cap: higher HP% wins',
    'Last turn; b has the higher HP ratio.',
    a: fs(ElementType.fire, hp: 100),
    b: fs(ElementType.water, hp: 50),
    turns: [(g, g)],
    patch: (s) => BattleState(
      a: s.a.copyWith(hp: 120), // 40%
      b: s.b.copyWith(hp: 90), // 60%
      turn: spec.turnCap - 1,
    ),
  );
  battle(
    'turn cap: exact HP% tie -> rng',
    'Equal HP ratios; rng decides.',
    a: fs(ElementType.fire, hp: 100),
    b: fs(ElementType.water, hp: 50),
    turns: [(g, g)],
    patch: (s) => BattleState(
      a: s.a.copyWith(hp: 150),
      b: s.b.copyWith(hp: 75),
      turn: spec.turnCap - 1,
    ),
    require: (ev, end) => end.winner == Side.b,
  );
  battle(
    'turn cap: KO on last turn beats cap',
    'A KO on the final turn ends by ko.',
    a: fs(ElementType.fire, spd: 100),
    b: fs(ElementType.leaf, spd: 80),
    turns: [(el, t)],
    patch: (s) =>
        BattleState(a: s.a, b: s.b.copyWith(hp: 5), turn: spec.turnCap - 1),
    require: (ev, end) => end.endReason == EndReason.ko,
  );

  // ---- Timeouts -------------------------------------------------------------
  battle(
    'timeout a',
    'a times out -> たいあたり.',
    a: fs(ElementType.fire, spd: 100),
    b: fs(ElementType.water, spd: 80),
    turns: [(to, el)],
  );
  battle(
    'timeout both',
    'Both time out.',
    a: fs(ElementType.shadow),
    b: fs(ElementType.rainbow),
    turns: [(to, to)],
  );

  // ---- Full battles driven by the AI (actions recorded) -----------------------
  for (final (i, (ea, eb, ta, tb, la, lb)) in [
    (ElementType.fire, ElementType.leaf, AiTier.normal, AiTier.normal, 1, 1),
    (ElementType.water, ElementType.thunder, AiTier.strong, AiTier.weak, 5, 5),
    (ElementType.shadow, ElementType.rainbow, AiTier.weak, AiTier.weak, 1, 1),
    (ElementType.leaf, ElementType.leaf, AiTier.strong, AiTier.normal, 12, 10),
    (
      ElementType.rainbow,
      ElementType.fire,
      AiTier.strong,
      AiTier.strong,
      22,
      21,
    ),
  ].indexed) {
    final setupA = FighterSetup(
      element: ea,
      level: la,
      stats: statsAtLevel(
        spec,
        Stats(hp: 80 + i * 7, atk: 95 - i * 3, def: 85, spd: 90 + i),
        la,
        const {},
        isShobo: false,
      ),
    );
    final setupB = FighterSetup(
      element: eb,
      level: lb,
      stats: statsAtLevel(
        spec,
        Stats(hp: 95, atk: 80 + i * 4, def: 90 - i * 2, spd: 88),
        lb,
        const {},
        isShobo: false,
      ),
    );
    // Record the AI's choices with dedicated streams, then store them as a
    // plain action list (the vector replays actions only).
    final matchSeed = 1000 + i;
    final rng = Mulberry32(deriveSeed(matchSeed, 0));
    final aiA = Mulberry32(deriveSeed(matchSeed, 1));
    final aiB = Mulberry32(deriveSeed(matchSeed, 2));
    var s = initBattle(spec, setupA, setupB);
    final turns = <(BattleAction, BattleAction)>[];
    while (!s.isOver) {
      final x = chooseCpuAction(spec, s, Side.a, ta, aiA);
      final y = chooseCpuAction(spec, s, Side.b, tb, aiB);
      turns.add((x, y));
      s = resolveTurn(spec, s, x, y, rng).state;
    }
    battle(
      'full battle #${i + 1} (${ta.name} vs ${tb.name})',
      'Complete battle with AI-chosen actions until the end.',
      a: setupA,
      b: setupB,
      turns: turns,
      require: (ev, end) => end.isOver,
    );
  }

  // ---- Fuzz: random stats / levels / actions (incl. timeouts) ---------------
  final fuzz = Mulberry32(0xF00D);
  for (var i = 0; i < 12; i++) {
    FighterSetup rnd() => FighterSetup(
      element: ElementType.values[fuzz.nextInt(6)],
      level: 1 + fuzz.nextInt(30),
      stats: Stats(
        hp: 1 + fuzz.nextInt(250),
        atk: 1 + fuzz.nextInt(250),
        def: 1 + fuzz.nextInt(250),
        spd: 1 + fuzz.nextInt(250),
      ),
    );
    final fa = rnd();
    final fb = rnd();
    final turns = [
      for (var k = 0; k < 40; k++)
        (
          BattleAction.values[fuzz.nextInt(5)],
          BattleAction.values[fuzz.nextInt(5)],
        ),
    ];
    battle(
      'fuzz #${i + 1}',
      'Random stats, levels and actions until the end.',
      a: fa,
      b: fb,
      turns: turns,
      require: (ev, end) => end.isOver,
    );
  }

  // ---- AI decisions ---------------------------------------------------------
  final base = initBattle(
    spec,
    fs(ElementType.fire, spd: 100),
    fs(ElementType.leaf, spd: 80),
  );
  aiVector('weak picks randomly', base, Side.a, AiTier.weak);
  aiVector(
    'weak may use special when ready',
    base.withFighter(Side.a, base.a.copyWith(gauge: 100)),
    Side.a,
    AiTier.weak,
    expect: BattleAction.special,
  );
  aiVector(
    'normal uses element when advantaged',
    base,
    Side.a,
    AiTier.normal,
    expect: BattleAction.element,
  );
  aiVector(
    'normal tackles when disadvantaged',
    base,
    Side.b,
    AiTier.normal,
    expect: BattleAction.tackle,
  );
  aiVector(
    'normal sometimes guards',
    base,
    Side.a,
    AiTier.normal,
    expect: BattleAction.guard,
  );
  aiVector(
    'normal specials when ready',
    base.withFighter(Side.a, base.a.copyWith(gauge: 100)),
    Side.a,
    AiTier.normal,
  );
  aiVector(
    'strong finishes with tackle',
    base.withFighter(Side.b, base.b.copyWith(hp: 5)),
    Side.a,
    AiTier.strong,
  );
  aiVector(
    'strong braces for lethal special',
    BattleState(a: base.a.copyWith(hp: 60), b: base.b.copyWith(gauge: 100)),
    Side.a,
    AiTier.strong,
    expect: BattleAction.guard,
  );
  aiVector(
    'strong holds special vs habitual guarder',
    BattleState(
      a: base.a.copyWith(gauge: 100),
      b: base.b.copyWith(
        usage: const MoveUsage(guard: 3, tackle: 1),
        guardStreak: 0,
      ),
    ),
    Side.a,
    AiTier.strong,
  );
  aiVector(
    'strong uses special vs non-guarder',
    base.withFighter(Side.a, base.a.copyWith(gauge: 100)),
    Side.a,
    AiTier.strong,
  );

  // ---- XP & levelling -------------------------------------------------------
  xpVector('win Lv1', level: 1, xp: 0, isShobo: false, won: true);
  xpVector('lose Lv1', level: 1, xp: 0, isShobo: false, won: false);
  xpVector('shobo win +50%', level: 3, xp: 10, isShobo: true, won: true);
  xpVector('shobo lose +50%', level: 3, xp: 10, isShobo: true, won: false);
  xpVector(
    'ad boost x2',
    level: 2,
    xp: 0,
    isShobo: false,
    won: true,
    adBoost: true,
  );
  xpVector(
    'multi level-up',
    level: 1,
    xp: 70,
    isShobo: true,
    won: true,
    stagePct: 245,
    adBoost: true,
  );
  xpVector('evolve to kagayaki', level: 9, xp: 200, isShobo: false, won: true);
  xpVector(
    'evolve to densetsu',
    level: 19,
    xp: 500,
    isShobo: false,
    won: true,
    stagePct: 200,
  );
  xpVector(
    'reach max level, leftover discarded',
    level: 29,
    xp: 700,
    isShobo: true,
    won: true,
    stagePct: 245,
    adBoost: true,
  );
  xpVector('already max level', level: 30, xp: 0, isShobo: false, won: true);
  xpVector(
    'stage multiplier floor',
    level: 5,
    xp: 3,
    isShobo: true,
    won: false,
    stagePct: 135,
  );

  // ---- Stats growth ---------------------------------------------------------
  const b0 = Stats(hp: 90, atk: 75, def: 60, spd: 33);
  statsVector('Lv1 no seeds', b0, 1, const {});
  statsVector('Lv10 with seeds', b0, 10, const {
    StatKind.atk: 5,
    StatKind.hp: 4,
  });
  statsVector('Lv20 densetsu', b0, 20, const {StatKind.spd: 19});
  statsVector(
    'Lv30 max',
    const Stats(hp: 1, atk: 2, def: 220, spd: 31),
    30,
    const {StatKind.def: 29},
  );
  const shoboBase = Stats(hp: 31, atk: 33, def: 30, spd: 32);
  statsVector('shobo Lv1', shoboBase, 1, const {}, isShobo: true);
  statsVector('shobo Lv15 with seeds', shoboBase, 15, const {
    StatKind.atk: 7,
    StatKind.spd: 7,
  }, isShobo: true);
  statsVector('shobo Lv30', shoboBase, 30, const {
    StatKind.hp: 29,
  }, isShobo: true);

  // しょぼ Lv30 vs normal Lv15: a full battle with growth-scaled stats.
  {
    final a = FighterSetup(
      element: ElementType.leaf,
      level: 30,
      stats: statsAtLevel(spec, shoboBase, 30, const {
        StatKind.atk: 29,
      }, isShobo: true),
    );
    final b = FighterSetup(
      element: ElementType.water,
      level: 15,
      stats: statsAtLevel(
        spec,
        const Stats(hp: 95, atk: 90, def: 85, spd: 90),
        15,
        const {StatKind.hp: 14},
        isShobo: false,
      ),
    );
    final rng = Mulberry32(deriveSeed(77, 0));
    final ai = [Mulberry32(deriveSeed(77, 1)), Mulberry32(deriveSeed(77, 2))];
    var st = initBattle(spec, a, b);
    final turns = <(BattleAction, BattleAction)>[];
    while (!st.isOver) {
      final x = chooseCpuAction(spec, st, Side.a, AiTier.normal, ai[0]);
      final y = chooseCpuAction(spec, st, Side.b, AiTier.normal, ai[1]);
      turns.add((x, y));
      st = resolveTurn(spec, st, x, y, rng).state;
    }
    battle(
      'shobo Lv30 vs normal Lv15',
      'Grown しょぼキャラ vs a mid-level kid.',
      a: a,
      b: b,
      turns: turns,
      require: (ev, end) => end.isOver,
    );
  }

  final out = const JsonEncoder.withIndent(' ').convert({
    'specVersion': spec.specVersion,
    'generatedBy': 'app/tool/gen_golden_vectors.dart',
    'count': vectors.length,
    'vectors': vectors,
  });
  File('../shared/battle_spec/golden_vectors.json').writeAsStringSync('$out\n');
  stdout.writeln('wrote ${vectors.length} vectors');
}
