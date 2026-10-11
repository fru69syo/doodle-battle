/// Golden vectors for every engine port (TS / C# / GDScript):
/// `shared/battle_spec_v3/golden_vectors.json` is generated from this file
/// (`dart run tool/v3_sim.dart golden`); the Dart and TS test suites replay
/// every vector from its JSON input alone. The first 12 genomes, 6 offline
/// sets, 10 validator cases and 6 battles keep the design team's inputs.
library;

import 'dart:convert';

import 'ai.dart';
import 'engine.dart';
import 'features.dart';
import 'genome.dart';
import 'loadout.dart';
import 'moves.dart';
import 'offline_moves.dart';
import 'progression.dart';
import 'rng.dart';
import 'sim.dart';
import 'spec.dart';
import 'stages.dart';
import 'validator.dart';
import '../rig_blob.dart';

/// NG words used by the golden validator cases (a stand-in for the real
/// list: the check is "contains any of these").
const List<String> kGoldenNgWords = ['ばか', 'しね'];

bool goldenNgCheck(String s) => kGoldenNgWords.any(s.contains);

Map<String, Object?> _genomeJson(V3Spec s, Genome g) => {
  'kid': g.kid,
  'isBloomer': g.isBloomer,
  'attribute': g.attr.name,
  'jitterPct': g.jitterPct,
  'budget': g.budget,
  'affinities': g.affinities,
  'base': g.base,
  'growthMille': g.growthMille,
  'rebirthBase': g.rebirthBase,
  'statsAt': {
    for (final l in [1, 10, 49, 50, 75, 100]) '$l': g.statsAt(l),
  },
  'maxHpAt': {
    for (final l in [1, 50, 100]) '$l': maxHpOf(s, g.statsAt(l)),
  },
  'moveFactorPct': {
    for (final l in [1, 49, 50]) '$l': g.moveFactorPct(l),
  },
};

/// Golden battle input → battle run to the end. `controllers[i]` is null
/// (no controller: only queued inputs and the 5 s timeout) or
/// `{"tier": name, "think": ticks}`; `inputs` are `[tick, side, slot]`
/// queued just before that tick is stepped.
Battle runGoldenBattle(V3Spec s, Map<String, Object?> input) {
  final a = FighterSetup.fromJson((input['a']! as Map).cast());
  final b = FighterSetup.fromJson((input['b']! as Map).cast());
  final battle = Battle(s, a, b, seed: input['seed']! as int);
  Controller? ctl(Object? j) {
    if (j == null) return null;
    final m = (j as Map).cast<String, Object?>();
    return aiController(
      thinkTicks: m['think']! as int,
      tier: AiTier.fromName(m['tier']! as String),
    );
  }

  final cs = input['controllers']! as List;
  final ca = ctl(cs[0]);
  final cb = ctl(cs[1]);
  final inputs = [
    for (final x in (input['inputs'] as List? ?? const []))
      (x as List).cast<int>(),
  ];
  while (!battle.finished) {
    for (final x in inputs) {
      if (x[0] == battle.tick + 1) battle.queueInput(x[1], x[2]);
    }
    battle.step(a: ca, b: cb);
  }
  return battle;
}

Map<String, Object?> _battleExpected(Battle b, {bool full = false}) => {
  'winner': b.winner,
  'endReason': b.endReason,
  'ticks': b.tick,
  'hp': [b.fighters[0].hp, b.fighters[1].hp],
  'maxHp': [b.fighters[0].maxHp, b.fighters[1].maxHp],
  'actions': [b.fighters[0].actions, b.fighters[1].actions],
  'eventCount': b.events.length,
  'eventsFnv1a': eventsHash(b.events),
  'stateHash': b.stateHash(),
  if (full) 'events': [for (final e in b.events) e.line],
};

Map<String, Object?> _validation(MoveValidation v, V3Spec s) => v.rejected
    ? {'rejected': true, 'reason': v.reason}
    : {
        'rejected': false,
        'move': v.move!.toJson(),
        'cost': moveCost(s, v.move!),
        'warnings': v.warnings,
      };

/// Every golden vector, as JSON.
Map<String, Object?> goldenVectors(V3Spec s) {
  final r = Mulberry32(20261010);
  final genomes = <Map<String, Object?>>[];
  final gs = <Genome>[];
  void addGenome(
    FeatureVector f,
    int e10,
    int s10,
    String hash,
    String? origin,
  ) {
    final g = Genome.derive(
      s,
      features: f,
      energy10: e10,
      skill10: s10,
      imageHash: hash,
      origin: origin,
    );
    gs.add(g);
    genomes.add({
      'input': {
        'features': f.values,
        'energy10': e10,
        'skill10': s10,
        'imageHash': hash,
        'origin': origin,
      },
      'expected': _genomeJson(s, g),
    });
  }

  // 0..11: the design team's inputs.
  for (var i = 0; i < 12; i++) {
    final f = randomFeatures(r);
    final e10 = 300 + r.nextInt(700);
    final s10 = i % 4 == 3 ? 760 + r.nextInt(240) : r.nextInt(500);
    final hash = r.nextUint32().toRadixString(16).padLeft(8, '0') + 'c' * 56;
    addGenome(f, e10, s10, hash, i == 5 ? 'ai_generated' : null);
  }
  // 12..17: on-device trust verdicts, extremes, a non-hex hash, defaults.
  for (final origin in ['digital', 'printed', 'screen']) {
    final f = randomFeatures(r);
    final hash = r.nextUint32().toRadixString(16).padLeft(8, '0') + 'd' * 56;
    addGenome(f, 700, 300, hash, origin);
  }
  addGenome(randomFeatures(r), 1000, 0, 'not-a-hex-hash', null);
  addGenome(const FeatureVector({}), 0, 1000, '00000000', null);
  addGenome(
    const FeatureVector({
      'roundness': 1000,
      'silhouetteCoverage': 1000,
      'inkCoverage': 1000,
      'solidity': 1000,
      'spikiness': 1000,
      'redShare': 1000,
      'lineThickness': 600,
      'darkness': 1000,
      'colorUnits': 30,
      'balancedHueCount': 12,
      'detailDensity': 1000,
      'convexityDefects': 50,
      'elongation': 1000,
      'symmetry': 1000,
    }),
    750,
    750,
    'ffffffff',
    null,
  );

  final offline = <Map<String, Object?>>[
    for (var i = 0; i < 6; i++)
      {
        'genomeIndex': i,
        'moveFactorPct': gs[i].moveFactorPct(1),
        'stream': 12,
        'attribute': null,
        'expected': [
          for (final m in generateOfflineMoves(
            s,
            gs[i],
            moveFactorPct: gs[i].moveFactorPct(1),
          ))
            {...m.toJson(), 'cost': moveCost(s, m)},
        ],
      },
    // Rebirth sets (stream 14) and an attribute override.
    for (final (i, stream, attr) in [
      (3, 14, null),
      (5, 14, null),
      (8, 12, Attr.choki),
    ])
      {
        'genomeIndex': i,
        'moveFactorPct': gs[i].moveFactorPct(stream == 14 ? 50 : 1),
        'stream': stream,
        'attribute': attr?.name,
        'expected': [
          for (final m in generateOfflineMoves(
            s,
            gs[i],
            moveFactorPct: gs[i].moveFactorPct(stream == 14 ? 50 : 1),
            stream: stream,
            attr: attr,
          ))
            {...m.toJson(), 'cost': moveCost(s, m)},
        ],
      },
  ];

  final validator = [
    for (final (slot, own, factor, input) in _validatorCases)
      {
        'slot': slot,
        'own': own.name,
        'moveFactorPct': factor,
        'input': input,
        'expected': _validation(
          validateAiMove(
            s,
            input,
            slot: slot,
            own: own,
            moveFactorPct: factor,
            ngCheck: goldenNgCheck,
          ),
          s,
        ),
      },
  ];

  final validatorSets = [
    for (final (own, factor, input) in _validatorSetCases)
      {
        'own': own.name,
        'moveFactorPct': factor,
        'input': input,
        'expected': [
          for (final v in validateAiMoveSet(
            s,
            input,
            own: own,
            moveFactorPct: factor,
            ngCheck: goldenNgCheck,
          ))
            _validation(v.result, s),
        ],
      },
  ];

  // Battles. 0..5: the design team's pairs (ふつう AI, think ticks).
  final battles = <Map<String, Object?>>[];
  void addBattle(
    FighterSetup a,
    FighterSetup b,
    int seed,
    List<Map<String, Object?>?> controllers, {
    List<List<int>> inputs = const [],
    String note = '',
    bool full = false,
  }) {
    final input = {
      'note': note,
      'seed': seed,
      'a': a.toJson(),
      'b': b.toJson(),
      'controllers': controllers,
      'inputs': inputs,
    };
    final battle = runGoldenBattle(
      s,
      (jsonDecode(jsonEncode(input)) as Map).cast(),
    );
    battles.add({
      'input': input,
      'expected': _battleExpected(battle, full: full),
    });
  }

  Map<String, Object?> ai(String tier, int think) => {
    'tier': tier,
    'think': think,
  };
  final levels = [1, 10, 50, 100, 30, 75];
  for (var i = 0; i < 6; i++) {
    final lv = levels[i];
    addBattle(
      setupAt(s, gs[i * 2], lv),
      setupAt(s, gs[i * 2 + 1], lv),
      1000 + i,
      [ai('normal', i == 2 ? 0 : 10), ai('normal', i == 3 ? 60 : 10)],
      note: 'design pair $i, Lv$lv',
      full: i < 2,
    );
  }
  // 6..: tiers, さきどり, timeouts, rated sync, family, heat-up.
  addBattle(setupAt(s, gs[0], 20), setupAt(s, gs[2], 20), 2001, [
    ai('strong', 4),
    ai('normal', 10),
  ], note: 'つよい vs ふつう');
  addBattle(setupAt(s, gs[4], 5), setupAt(s, gs[6], 5), 2002, [
    ai('weak', 10),
    ai('normal', 10),
  ], note: 'よわい vs ふつう');
  addBattle(
    setupAt(s, gs[8], 12),
    setupAt(s, gs[9], 12),
    2003,
    [null, ai('normal', 10)],
    inputs: [
      for (var t = 1; t < 1800; t += 23) [t, 0, (t ~/ 23) % 3],
      [5, 0, 7],
    ],
    note: 'さきどり: scripted taps (some invalid) + timeouts',
    full: true,
  );
  addBattle(setupAt(s, gs[10], 40), setupAt(s, gs[1], 40), 2004, [
    null,
    null,
  ], note: 'no input at all: every move is the 5 s おまかせ');
  addBattle(
    ratedSetup(s, gs[3], actualLevel: 20),
    ratedSetup(s, gs[0], actualLevel: 7),
    2005,
    [ai('normal', 10), ai('normal', 10)],
    note: 'rated sync: pre-rebirth bloomer vs Lv7 kid (both at Lv50)',
  );
  addBattle(
    ratedSetup(s, gs[7], actualLevel: 60),
    ratedSetup(s, gs[2], actualLevel: 50),
    2006,
    [ai('normal', 10), ai('normal', 10)],
    note: 'rated sync: reborn bloomer vs Lv50 kid',
  );
  addBattle(
    familySetup(s, gs[11], actualLevel: 30, battleLevel: 60),
    familySetup(s, gs[4], actualLevel: 50, battleLevel: 50),
    2007,
    [ai('normal', 10), ai('strong', 4)],
    note: 'family: bloomer boosted past Lv50 keeps its pre-rebirth form',
  );
  // Weak attackers with lots of HP: heat-up ramp, fading heals, time-up.
  FighterSetup tank(Genome g) {
    final f = setupAt(s, g, 100);
    final st = List.of(f.stats);
    st[Stat.str.index] = 3;
    st[Stat.intl.index] = 3;
    st[Stat.def.index] = 900;
    st[Stat.res.index] = 900;
    return f.withStats(st);
  }

  addBattle(tank(gs[16]), tank(gs[15]), 2008, [
    ai('normal', 10),
    ai('normal', 10),
  ], note: 'tanks: heat-up ramp and the 3-minute cap (HP ratio)');
  addBattle(
    setupAt(s, gs[12], 50, powerPct: 93),
    setupAt(s, gs[13], 50),
    2009,
    [ai('normal', 0), ai('strong', 4)],
    note: 'stage-style CPU power 93 %',
  );

  final ratedGenomes = [0, 3, 7, 11];
  return {
    'specVersion': s.specVersion,
    'generatedBy': 'app/tool/v3_sim.dart golden (Dart engine v3)',
    'conventions': {
      'eventLine': '"<tick> <type> <k=v,...>" with keys sorted (ASCII)',
      'eventsFnv1a': "fnv1a32 of the event lines joined with '\\n'",
      'controllers':
          'null = no controller (queued inputs + 5 s timeout only); '
          '{tier, think}: when ready, null until readyTicks >= think, then '
          'chooseMove(tier) on the side AI stream; the timeout auto-pick is '
          'chooseMove(normal) on the same stream',
      'inputs':
          '[tick, side, slot]: queueInput(side, slot) just before stepping '
          'that tick (invalid inputs are ignored when used)',
      'setupAt':
          'stats = statsAt(level) * powerPct / 100; moves = offline '
          'generator (stream 12, or 14 after a bloomer rebirth) with '
          'moveFactorPct(level), filtered by slotUnlockLevels',
      'ngCheck': 'contains any of $kGoldenNgWords',
    },
    'deriveSeed': [
      for (final st in [10, 11, 12, 13, 14])
        {'seed': 0xC0FFEE, 'stream': st, 'expected': deriveSeed(0xC0FFEE, st)},
    ],
    'genomes': genomes,
    'offlineMoves': offline,
    'validator': validator,
    'validatorSets': validatorSets,
    'battles': battles,
    'moveCost': [
      for (final m in generateOfflineMoves(s, gs[0], moveFactorPct: 110))
        {
          'move': m.toJson(),
          'value': moveValue(m),
          'discount': moveDiscount(s, m),
          'cost': moveCost(s, m),
        },
    ],
    'ratedSetups': [
      for (final i in ratedGenomes)
        for (final lv in [5, 49, 50, 80])
          {
            'genomeIndex': i,
            'actualLevel': lv,
            'expected': ratedSetup(s, gs[i], actualLevel: lv).toJson(),
          },
    ],
    'xp': [
      for (final c in [
        (true, 1, 1, false, false, false),
        (false, 30, 30, false, false, false),
        (true, 10, 35, false, false, false),
        (true, 10, 45, false, true, false),
        (true, 50, 50, true, true, false),
        (true, 5, 40, false, false, true),
        (false, 100, 100, false, true, false),
        (true, 3, 30, true, false, false),
      ])
        {
          'win': c.$1,
          'stage': c.$2,
          'level': c.$3,
          'firstClear': c.$4,
          'adBoost': c.$5,
          'hiddenBloomer': c.$6,
          'expected': xpSinglePlayer(
            win: c.$1,
            stage: c.$2,
            level: c.$3,
            firstClear: c.$4,
            adBoost: c.$5,
            hiddenBloomer: c.$6,
          ),
        },
    ],
    'xpOnline': [
      for (final c in [
        (true, 1, true, false),
        (false, 50, true, false),
        (true, 100, false, false),
        (true, 20, true, true),
      ])
        {
          'win': c.$1,
          'level': c.$2,
          'eligible': c.$3,
          'hiddenBloomerBonus': c.$4,
          'expected': xpOnline(
            win: c.$1,
            level: c.$2,
            eligible: c.$3,
            hiddenBloomerBonus: c.$4,
          ),
        },
    ],
    'applyXp': [
      for (final c in [
        (1, 0, 79, false),
        (1, 0, 5000, false),
        (9, 300, 400, false),
        (48, 100, 9000, true),
        (99, 9000, 100000, false),
      ])
        () {
          final p = applyXp(
            s,
            level: c.$1,
            xp: c.$2,
            gained: c.$3,
            isBloomer: c.$4,
          );
          return {
            'level': c.$1,
            'xp': c.$2,
            'gained': c.$3,
            'isBloomer': c.$4,
            'expected': {
              'level': p.level,
              'xp': p.xp,
              'newSlots': p.newSlots,
              'evolutions': p.evolutions,
              'rebirth': p.rebirth,
            },
          };
        }(),
    ],
    'xpToNext': {
      for (final l in [1, 9, 10, 49, 50, 99]) '$l': xpToNext(s, l),
    },
    'elo': [
      for (final c in [
        (1000, 1000, true, 48),
        (1000, 1200, true, 24),
        (1400, 1000, false, 24),
        (610, 900, false, 48),
        (1000, 2000, true, 12),
        (1234, 1180, false, 24),
      ])
        {
          'ratingA': c.$1,
          'ratingB': c.$2,
          'aWon': c.$3,
          'k': c.$4,
          'expectedMille': eloExpectedMille(c.$1, c.$2),
          'delta': eloDelta(c.$1, c.$2, c.$3, c.$4),
        },
    ],
    'stagesFnv1a': fnv1a32(jsonEncode([for (final x in stageTable()) x])),
    'rig': [
      for (final (note, rig) in _rigCases)
        {'note': note, 'input': rig, 'problem': rigProblem(rig)},
    ],
  };
}

const _strike = {
  'template': 'strike',
  'attribute': 'gu',
  'name': 'ごつごつパンチ',
  'flavor': 'ぐーで ごつん！',
  'vfx': 'punch',
  'colour': 'red',
  'atkFormula': 'STR80_AGI20',
  'power': 100,
  'hits': 1,
  'accuracy': 100,
  'critBonus': 0,
  'spCost': 0,
  'castTicks': 0,
  'cooldownTicks': 0,
};

final List<(int, Attr, int, Map<String, Object?>)> _validatorCases = [
  (0, Attr.gu, 100, _strike),
  (
    0,
    Attr.gu,
    100,
    {
      'template': 'strike',
      'attribute': 'pa',
      'name': 'すごいパンチ',
      'vfx': 'laser',
      'colour': 'gold',
      'atkFormula': 'INT80_DEX20',
      'power': 999,
      'hits': 1,
      'accuracy': 100,
      'spCost': 30,
      'castTicks': 30,
      'cooldownTicks': 50,
    },
  ),
  (
    1,
    Attr.choki,
    100,
    {
      'template': 'heal',
      'attribute': 'pa',
      'name': 'おひるね',
      'flavor': 'すやすや げんき',
      'vfx': 'hearts',
      'colour': 'pink',
      'healPct': 40,
      'spCost': 20,
      'castTicks': 0,
      'cooldownTicks': 100,
    },
  ),
  (
    1,
    Attr.pa,
    100,
    {
      'template': 'blast',
      'attribute': 'pa',
      'name': 'ふわふわビーム',
      'vfx': 'beam',
      'colour': 'green',
      'atkFormula': 'INT70_RES30',
      'power': 140,
      'hits': 1,
      'accuracy': 90,
      'spCost': 20,
      'castTicks': 6,
      'cooldownTicks': 40,
      'secondary': {'type': 'paralyze', 'chance': 80},
    },
  ),
  (
    2,
    Attr.gu,
    100,
    {
      'template': 'power_up',
      'name': 'きあい',
      'vfx': 'glow',
      'colour': 'orange',
      'stat': 'AGI',
      'stages': 2,
      'durationTicks': 120,
      'spCost': 0,
      'castTicks': 0,
      'cooldownTicks': 0,
    },
  ),
  (2, Attr.gu, 100, {'template': 'fireball', 'name': 'ファイア', 'power': 100}),
  (
    3,
    Attr.choki,
    100,
    {
      'template': 'barrage',
      'attribute': 'choki',
      'name': 'Super Beam',
      'power': 200,
      'hits': 3,
    },
  ),
  (
    3,
    Attr.choki,
    100,
    {
      'template': 'barrage',
      'attribute': 'choki',
      'name': 'シャキーンスター',
      'flavor': 'ほしが いっぱい！',
      'vfx': 'stars',
      'colour': 'yellow',
      'atkFormula': 'INT60_LUK40',
      'power': 200,
      'hits': 3,
      'accuracy': 95,
      'critBonus': 20,
      'spCost': 50,
      'castTicks': 15,
      'cooldownTicks': 120,
      'secondary': {'type': 'drain', 'drainPct': 50},
    },
  ),
  (
    1,
    Attr.gu,
    100,
    {
      'template': 'poison',
      'attribute': 'choki',
      'name': 'ねばねば',
      'vfx': 'bubbles',
      'colour': 'purple',
      'chance': 100,
      'accuracy': 100,
      'spCost': 0,
      'castTicks': 0,
      'cooldownTicks': 0,
    },
  ),
  (
    2,
    Attr.pa,
    100,
    {
      'template': 'barrier',
      'name': 'まもりバリア',
      'vfx': 'shield',
      'colour': 'cyan',
      'shieldPct': 60,
      'durationTicks': 60,
      'spCost': 10,
      'castTicks': 0,
      'cooldownTicks': 40,
    },
  ),
  // 10..: production edge cases.
  (0, Attr.pa, 70, {..._strike, 'attribute': 'pa', 'power': 120}),
  (
    2,
    Attr.gu,
    105,
    {
      ..._strike,
      'template': 'combo',
      'hits': 2.7,
      'power': 150.9,
      'accuracy': '90',
      'critBonus': true,
      'spCost': 1e12,
      'castTicks': -4,
      'cooldownTicks': 30,
    },
  ),
  (2, Attr.gu, 100, {..._strike, 'atkFormula': 42, 'vfx': null}),
  (
    1,
    Attr.gu,
    100,
    {
      ..._strike,
      'attribute': 'choki',
      'secondary': {'type': 'debuff', 'chance': 99, 'stat': 'HP'},
    },
  ),
  (
    1,
    Attr.gu,
    100,
    {
      ..._strike,
      'attribute': 'choki',
      'secondary': {'type': 'debuff', 'chance': 5, 'stat': 'DEF'},
    },
  ),
  (2, Attr.gu, 100, {..._strike, 'name': 'ばかパンチ'}),
  (2, Attr.gu, 100, {..._strike, 'flavor': 'しねしね'}),
  (
    2,
    Attr.choki,
    100,
    {
      'template': 'weaken',
      'name': 'にらめっこ',
      'vfx': 'glow',
      'colour': 'purple',
      'stat': 'RES',
      'stages': 2,
      'durationTicks': 120,
      'accuracy': 100,
      'spCost': 0,
      'castTicks': 0,
      'cooldownTicks': 0,
    },
  ),
  (2, Attr.choki, 100, {'template': 'weaken', 'name': 'にらめっこ', 'stat': 'HP'}),
  (
    1,
    Attr.choki,
    100,
    {
      'template': 'paralyze',
      'attribute': 'gu',
      'name': 'ビリビリ',
      'chance': 100,
      'accuracy': 100,
    },
  ),
  (
    2,
    Attr.pa,
    100,
    {
      'template': 'heal',
      'name': 'げんき',
      'healPct': 40,
      'spCost': 0,
      'castTicks': 0,
      'cooldownTicks': 60,
    },
  ),
  (
    0,
    Attr.choki,
    95,
    {
      'template': 'barrier',
      'name': 'まもり',
      'shieldPct': 60,
      'durationTicks': 60,
    },
  ),
];

final List<(Attr, int, Object?)> _validatorSetCases = [
  (
    Attr.gu,
    100,
    {
      'moves': [
        _strike,
        {..._strike, 'attribute': 'choki', 'name': 'ごつごつパンチ'},
        {..._strike, 'name': 'ばかキック'},
        'not a move',
      ],
    },
  ),
  (
    Attr.pa,
    70,
    {
      'moves': [
        {..._strike, 'template': 'blast', 'atkFormula': 'INT80_DEX20'},
      ],
    },
  ),
  (Attr.choki, 100, 'garbage'),
];

List<num> _p(num x, num y) => [x, y];

final List<(String, Object?)> _rigCases = [
  (
    'valid',
    {
      'v': 1,
      'width': 300,
      'height': 400.5,
      'root': _p(150, 300),
      'chest': _p(150, 200.5),
      'limbs': [
        {
          'kind': 'head',
          'base': _p(150, 150),
          'mid': _p(150, 100),
          'tip': _p(150, 50),
        },
        {
          'kind': 'arm',
          'base': _p(120, 200),
          'mid': _p(80, 220),
          'tip': _p(40, 260),
          'edited': true,
        },
      ],
      'source': 'edited',
      'futureKey': 'kept',
    },
  ),
  ('not an object', [1, 2]),
  ('unknown version', {'v': 2}),
  (
    'point out of range',
    {
      'v': 1,
      'width': 100,
      'height': 100,
      'root': _p(50, 50),
      'chest': _p(50, 900),
      'limbs': <Object?>[],
    },
  ),
  (
    'bad limb kind',
    {
      'v': 1,
      'width': 100,
      'height': 100,
      'root': _p(50, 50),
      'chest': _p(50, 40),
      'limbs': [
        {'kind': 'wing', 'base': _p(1, 1), 'mid': _p(2, 2), 'tip': _p(3, 3)},
      ],
    },
  ),
  (
    'too many limbs',
    {
      'v': 1,
      'width': 100,
      'height': 100,
      'root': _p(50, 50),
      'chest': _p(50, 40),
      'limbs': [
        for (var i = 0; i < 13; i++)
          {'kind': 'extra', 'base': _p(1, 1), 'mid': _p(2, 2), 'tip': _p(3, 3)},
      ],
    },
  ),
  (
    'too large',
    {
      'v': 1,
      'width': 100,
      'height': 100,
      'root': _p(50, 50),
      'chest': _p(50, 40),
      'limbs': <Object?>[],
      'note': 'x' * 5000,
    },
  ),
];
