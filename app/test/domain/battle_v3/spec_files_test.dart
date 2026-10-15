// Engine v3 — the shared spec / golden files match the Dart engine, and
// every golden vector replays from its JSON input alone (the TS port runs
// the same vectors: shared/battle_engine_v3_ts/test/golden.test.ts).
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/golden.dart';
import 'package:doodle_battle/domain/battle_v3/spec_export.dart';
import 'package:doodle_battle/domain/rig_blob.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = '../shared/battle_spec_v3';

Object? _read(String f) => jsonDecode(File('$_dir/$f').readAsStringSync());
Object? _norm(Object? o) => jsonDecode(jsonEncode(o));
List<Map<String, Object?>> _list(Object? o) =>
    (o! as List).cast<Map<String, Object?>>();

void main() {
  const s = V3Spec();
  final g = (_read('golden_vectors.json')! as Map).cast<String, Object?>();

  test('battle_spec_v3.json is up to date', () {
    expect(
      _read('battle_spec_v3.json'),
      _norm(fullSpecJson(s)),
      reason: 'run: dart run tool/v3_sim.dart spec',
    );
  });

  test('golden_vectors.json is up to date', () {
    expect(
      g,
      _norm(goldenVectors(s)),
      reason: 'run: dart run tool/v3_sim.dart golden',
    );
  });

  test('at least 60 golden vectors', () {
    var n = 0;
    for (final e in g.entries) {
      if (e.key == 'conventions') continue;
      if (e.value is List) n += (e.value! as List).length;
      if (e.value is Map) n += (e.value! as Map).length;
    }
    expect(n, greaterThanOrEqualTo(60));
  });

  final genomes = <Genome>[];
  test('genomes replay from JSON', () {
    for (final v in _list(g['genomes'])) {
      final i = (v['input']! as Map).cast<String, Object?>();
      final gn = Genome.derive(
        s,
        features: FeatureVector.tryParse(i['features'])!,
        energy10: i['energy10']! as int,
        skill10: i['skill10']! as int,
        imageHash: i['imageHash']! as String,
        origin: i['origin'] as String?,
      );
      genomes.add(gn);
      final e = (v['expected']! as Map).cast<String, Object?>();
      expect(gn.base, e['base']);
      expect(gn.growthMille, e['growthMille']);
      expect(gn.rebirthBase, e['rebirthBase']);
      expect(gn.maxBars, e['maxBars']);
      expect(gn.attr.name, e['attribute']);
      for (final l in [1, 10, 49, 50, 75, 100]) {
        expect(gn.statsAt(l), (e['statsAt']! as Map)['$l']);
      }
    }
  });

  test('validator replays from JSON', () {
    for (final v in _list(g['validator'])) {
      final r = validateAiMove(
        s,
        (v['input']! as Map).cast<String, Object?>(),
        slot: v['slot']! as int,
        own: Attr.values.byName(v['own']! as String),
        moveFactorPct: v['moveFactorPct']! as int,
        maxBars: v['maxBars']! as int,
        ngCheck: goldenNgCheck,
      );
      final e = (v['expected']! as Map).cast<String, Object?>();
      expect(r.rejected, e['rejected']);
      if (!r.rejected) {
        expect(_norm(r.move!.toJson()), e['move']);
        expect(r.warnings, e['warnings']);
      }
    }
  });

  test('golden battles replay from JSON input only', () {
    for (final v in _list(g['battles'])) {
      final b = runGoldenBattle(s, (v['input']! as Map).cast());
      final e = (v['expected']! as Map).cast<String, Object?>();
      expect(b.winner, e['winner'], reason: '${(v['input']! as Map)['note']}');
      expect(b.tick, e['ticks']);
      expect([b.fighters[0].hp, b.fighters[1].hp], e['hp']);
      expect(eventsHash(b.events), e['eventsFnv1a']);
      expect(b.stateHash(), e['stateHash']);
      if (e['events'] != null) {
        expect(b.events.map((x) => x.line).toList(), e['events']);
      }
    }
  });

  test('rig vectors', () {
    for (final v in _list(g['rig'])) {
      expect(rigProblem(v['input']), v['problem'], reason: '${v['note']}');
    }
  });
}
