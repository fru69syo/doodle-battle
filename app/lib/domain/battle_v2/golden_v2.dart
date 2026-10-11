/// PROTOTYPE — golden vectors for engine ports (TS / C# / GDScript).
/// `shared/battle_spec_v3/golden_vectors.json` is generated from this file
/// (`dart run tool/v2_sim.dart golden`); a test checks the committed copy.
library;

import '../battle/rng.dart';
import 'ai_v2.dart';
import 'atb_engine.dart';
import 'moves_v2.dart';
import 'progression_v2.dart';
import 'sim_v2.dart';
import 'stats_v2.dart';
import 'v2_spec.dart';

/// Canonical event line: `tick type k=v,k=v` with keys sorted.
String eventLine(BattleEventV2 e) {
  final keys = e.data.keys.toList()..sort();
  return '${e.tick} ${e.type} ${keys.map((k) => '$k=${e.data[k]}').join(',')}';
}

/// FNV-1a over the canonical lines joined with '\n'.
int eventsHash(List<BattleEventV2> events) =>
    fnv1a32(events.map(eventLine).join('\n'));

Map<String, Object?> _genomeJson(V2Spec s, Genome g) => {
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

Map<String, Object?> goldenVectors(V2Spec s) {
  final r = Mulberry32(20261010);
  final genomes = <Map<String, Object?>>[];
  final gs = <Genome>[];
  for (var i = 0; i < 12; i++) {
    final f = randomFeatures(r);
    final e10 = 300 + r.nextInt(700);
    final s10 = i % 4 == 3 ? 760 + r.nextInt(240) : r.nextInt(500);
    final hash = r.nextUint32().toRadixString(16).padLeft(8, '0') + 'c' * 56;
    final origin = i == 5 ? 'ai_generated' : null;
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

  final offline = [
    for (final g in gs.take(6))
      {
        'genomeIndex': gs.indexOf(g),
        'moveFactorPct': g.moveFactorPct(1),
        'expected': [
          for (final m in generateOfflineMoves(
            s,
            g,
            moveFactorPct: g.moveFactorPct(1),
          ))
            {...m.toJson(), 'cost': moveCost(s, m)},
        ],
      },
  ];

  final aiInputs = <(int, Attr, Map<String, Object?>)>[
    (
      0,
      Attr.gu,
      {
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
      },
    ),
    (
      0,
      Attr.gu,
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
    (2, Attr.gu, {'template': 'fireball', 'name': 'ファイア', 'power': 100}),
    (
      3,
      Attr.choki,
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
  ];
  final validator = [
    for (final (slot, own, input) in aiInputs)
      () {
        final v = validateAiMove(
          s,
          input,
          slot: slot,
          own: own,
          moveFactorPct: 100,
        );
        return {
          'slot': slot,
          'own': own.name,
          'moveFactorPct': 100,
          'input': input,
          'expected': v.rejected
              ? {'rejected': true, 'reason': v.reason}
              : {
                  'rejected': false,
                  'move': v.move!.toJson(),
                  'cost': moveCost(s, v.move!),
                  'warnings': v.warnings,
                },
        };
      }(),
  ];

  final battles = <Map<String, Object?>>[];
  final levels = [1, 10, 50, 100, 30, 75];
  for (var i = 0; i < 6; i++) {
    final ga = gs[i * 2];
    final gb = gs[i * 2 + 1];
    final lv = levels[i];
    final a = setupAt(s, ga, lv);
    final b = setupAt(s, gb, lv);
    final seed = 1000 + i;
    final thinkA = i == 2 ? 0 : 10;
    final thinkB = i == 3 ? 60 : 10; // 60 > decisionTicks → timeout auto-picks
    final battle = newBattle(s, a, b, seed: seed, recordEvents: true);
    battle.run(
      aiController(thinkTicks: thinkA),
      aiController(thinkTicks: thinkB),
    );
    battles.add({
      'input': {
        'seed': seed,
        'a': _setupJson(a),
        'b': _setupJson(b),
        'thinkTicks': [thinkA, thinkB],
        'aiTier': 'normal',
      },
      'expected': {
        'winner': battle.winner,
        'endReason': battle.endReason,
        'ticks': battle.tick,
        'hp': [battle.fighters[0].hp, battle.fighters[1].hp],
        'maxHp': [battle.fighters[0].maxHp, battle.fighters[1].maxHp],
        'eventCount': battle.events.length,
        'eventsFnv1a': battle.events.isEmpty ? 0 : eventsHash(battle.events),
        if (i < 2) 'events': battle.events.map(eventLine).toList(),
      },
    });
  }

  return {
    'specVersion': s.specVersion,
    'generatedBy': 'app/tool/v2_sim.dart golden (Dart reference prototype)',
    'conventions': {
      'eventLine': '"<tick> <type> <k=v,...>" with keys sorted (ASCII)',
      'eventsFnv1a': "fnv1a32 of the event lines joined with '\\n'",
      'controller':
          'AI controller: when ready, returns null until readyTicks >= '
          'thinkTicks, then chooseMove(normal) with the side AI stream; '
          'timeout auto-pick = chooseMove(normal) on the same stream',
      'setupAt':
          'stats = statsAt(level); moves = offline generator '
          '(stream 12, or 14 after a bloomer rebirth) with '
          'moveFactorPct(level), filtered by slotUnlockLevels',
    },
    'deriveSeed': [
      for (final st in [10, 11, 12, 13, 14])
        {'seed': 0xC0FFEE, 'stream': st, 'expected': deriveSeed(0xC0FFEE, st)},
    ],
    'genomes': genomes,
    'offlineMoves': offline,
    'validator': validator,
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
    'xp': [
      for (final c in [
        (true, 1, 1, false, false, false),
        (false, 30, 30, false, false, false),
        (true, 10, 35, false, false, false),
        (true, 10, 45, false, true, false),
        (true, 50, 50, true, true, false),
        (true, 5, 40, false, false, true),
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
  };
}

Map<String, Object?> _setupJson(FighterSetupV2 f) => {
  'stats': f.stats,
  'attribute': f.attr.name,
  'moves': [for (final m in f.moves) m.toJson()],
};
