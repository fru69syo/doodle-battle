import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '_support.dart';

Map<String, Object?> _m(Object? o) => (o! as Map).cast<String, Object?>();

void main() {
  final spec = loadSpecFromFile();
  final golden = readJson(goldenPath);
  final vectors = [for (final v in golden['vectors']! as List) _m(v)];

  test('golden file matches spec version and has >= 40 vectors', () {
    expect(golden['specVersion'], spec.specVersion);
    expect(vectors.length, greaterThanOrEqualTo(40));
    expect(
      vectors.where((v) => v['kind'] == 'battle').length,
      greaterThanOrEqualTo(40),
    );
  });

  for (final v in vectors) {
    final kind = v['kind']! as String;
    final name = v['name']! as String;
    test('[$kind] $name', () {
      switch (kind) {
        case 'rng':
          final input = _m(v['input']);
          final exp = _m(v['expected']);
          final seed = input['seed']! as int;
          final r = Mulberry32(seed);
          expect([for (var i = 0; i < 8; i++) r.nextUint32()], exp['uint32']);
          final r2 = Mulberry32(seed);
          expect([
            for (final n in input['intBounds']! as List) r2.nextInt(n as int),
          ], exp['ints']);
          expect(r2.state, exp['stateAfterInts']);
          expect([
            for (var s = 0; s < 3; s++) deriveSeed(seed, s),
          ], exp['deriveSeed']);
        case 'fnv':
          expect(fnv1a32(v['input']! as String), v['expected']);
        case 'damage':
          final i = _m(v['input']);
          expect(
            computeDamage(
              spec,
              power: i['power']! as int,
              atk: i['atk']! as int,
              def: i['def']! as int,
              typePct: i['typePct']! as int,
              crit: i['crit']! as bool,
              variancePct: i['variancePct']! as int,
              guardTakenPct: i['guardTakenPct']! as int,
            ),
            v['expected'],
          );
        case 'battle':
          final setup = _m(v['setup']);
          final initial = BattleState.fromJson(_m(v['initial']));
          expect(
            initial.toJson(),
            v['initial'],
            reason: 'state JSON round trip',
          );
          if (v['initialFromSetup']! as bool) {
            final fromSetup = initBattle(
              spec,
              FighterSetup.fromJson(_m(setup['a'])),
              FighterSetup.fromJson(_m(setup['b'])),
            );
            expect(fromSetup.toJson(), v['initial']);
          }
          final exp = _m(v['expected']);
          final expEvents = exp['events']! as List;
          final rng = Mulberry32(v['seed']! as int);
          var state = initial;
          final turns = v['turns']! as List;
          for (var i = 0; i < turns.length; i++) {
            final pair = turns[i] as List;
            final r = resolveTurn(
              spec,
              state,
              BattleAction.values.byName(pair[0] as String),
              BattleAction.values.byName(pair[1] as String),
              rng,
            );
            expect(
              [for (final e in r.events) e.toJson()],
              expEvents[i],
              reason: 'events of turn ${i + 1}',
            );
            // Events survive a JSON round trip.
            expect([
              for (final e in r.events) BattleEvent.fromJson(e.toJson()),
            ], r.events);
            state = r.state;
          }
          expect(state.toJson(), exp['final']);
          expect(rng.state, exp['rngState']);
        case 'ai':
          final state = BattleState.fromJson(_m(v['state']));
          final rng = Mulberry32(v['seed']! as int);
          final action = chooseCpuAction(
            spec,
            state,
            Side.values.byName(v['side']! as String),
            AiTier.values.byName(v['tier']! as String),
            rng,
          );
          final exp = _m(v['expected']);
          expect(action.name, exp['action']);
          expect(rng.state, exp['rngState']);
        case 'xp':
          final i = _m(v['input']);
          final gained = xpForBattle(
            spec,
            won: i['won']! as bool,
            isShobo: i['isShobo']! as bool,
            stageXpMultiplierPct: i['stageXpMultiplierPct']! as int,
            adBoost: i['adBoost']! as bool,
          );
          final p = addXp(
            spec,
            level: i['level']! as int,
            xp: i['xp']! as int,
            gained: gained,
          );
          expect({'xpGained': gained, ...p.toJson()}, v['expected']);
        case 'stats':
          final i = _m(v['input']);
          final base = Stats.fromJson(_m(i['base']));
          final level = i['level']! as int;
          final seeds = {
            for (final e in _m(i['seeds']).entries)
              StatKind.values.byName(e.key): e.value! as int,
          };
          final exp = _m(v['expected']);
          final shobo = i['isShobo']! as bool;
          expect(
            statsAtLevel(spec, base, level, seeds, isShobo: shobo).toJson(),
            exp['stats'],
          );
          expect(
            maxStatsAtLevel(spec, base, level, isShobo: shobo).toJson(),
            exp['maxStats'],
          );
          expect(specialPowerAt(spec, level), exp['specialPower']);
          expect(stageAtLevel(spec, level).name, exp['stage']);
        default:
          fail('unknown vector kind $kind');
      }
    });
  }
}
