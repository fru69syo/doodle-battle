// PROTOTYPE v2 tests — the shared spec / golden files match the Dart
// reference, and golden battles replay from their JSON input alone.
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle_v2/battle_v2.dart';
import 'package:doodle_battle/domain/battle_v2/golden_v2.dart';
import 'package:doodle_battle/domain/battle_v2/spec_export.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = '../shared/battle_spec_v3';

Object? _read(String f) => jsonDecode(File('$_dir/$f').readAsStringSync());
Object? _norm(Object? o) => jsonDecode(jsonEncode(o));

void main() {
  const s = V2Spec();

  test('battle_spec_v3.json is up to date', () {
    expect(
      _read('battle_spec_v3.json'),
      _norm(fullSpecJson(s)),
      reason: 'run: dart run tool/v2_sim.dart spec',
    );
  });

  test('golden_vectors.json is up to date', () {
    expect(
      _read('golden_vectors.json'),
      _norm(goldenVectors(s)),
      reason: 'run: dart run tool/v2_sim.dart golden',
    );
  });

  test('golden battles replay from JSON input only', () {
    final g = (_read('golden_vectors.json')! as Map).cast<String, Object?>();
    for (final v in (g['battles']! as List).cast<Map<String, Object?>>()) {
      final input = (v['input']! as Map).cast<String, Object?>();
      FighterSetupV2 side(String k) {
        final j = (input[k]! as Map).cast<String, Object?>();
        return FighterSetupV2(
          stats: (j['stats']! as List).cast<int>(),
          attr: Attr.values.byName(j['attribute']! as String),
          moves: [
            for (final m in (j['moves']! as List))
              MoveV2.fromJson((m as Map).cast<String, Object?>()),
          ],
        );
      }

      final think = (input['thinkTicks']! as List).cast<int>();
      final b = newBattle(
        s,
        side('a'),
        side('b'),
        seed: input['seed']! as int,
        recordEvents: true,
      );
      b.run(
        aiController(thinkTicks: think[0]),
        aiController(thinkTicks: think[1]),
      );
      final e = (v['expected']! as Map).cast<String, Object?>();
      expect(b.winner, e['winner']);
      expect(b.tick, e['ticks']);
      expect(eventsHash(b.events), e['eventsFnv1a']);
    }
  });
}
