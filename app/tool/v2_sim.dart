// PROTOTYPE v2 balance simulator (docs/GAME_DESIGN_V2.md §10).
//   cd app && dart run tool/v2_sim.dart [battles]        scenario table
//   dart run tool/v2_sim.dart stages [battles]           stage win curve
//   dart run tool/v2_sim.dart xp                          XP / level table
//   dart run tool/v2_sim.dart spec                        writes battle_spec_v3.json
//   dart run tool/v2_sim.dart golden                      writes golden_vectors.json
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle_v2/battle_v2.dart';
import 'package:doodle_battle/domain/battle_v2/golden_v2.dart';
import 'package:doodle_battle/domain/battle_v2/sim_v2.dart';
import 'package:doodle_battle/domain/battle_v2/spec_export.dart';

String _pretty(Object o) =>
    '${const JsonEncoder.withIndent('  ').convert(o)}\n';

void main(List<String> args) {
  const s = V2Spec();
  final cmd = args.isEmpty ? 'scenarios' : args.first;
  int nArg(int i, int d) => args.length > i ? int.parse(args[i]) : d;
  switch (cmd) {
    case 'spec':
      File('../shared/battle_spec_v3/battle_spec_v3.json')
          .writeAsStringSync(_pretty(fullSpecJson(s)));
      stdout.writeln('wrote shared/battle_spec_v3/battle_spec_v3.json');
    case 'golden':
      File('../shared/battle_spec_v3/golden_vectors.json')
          .writeAsStringSync(_pretty(goldenVectors(s)));
      stdout.writeln('wrote shared/battle_spec_v3/golden_vectors.json');
    case 'xp':
      var battles = 0.0;
      var bloomerBattles = 0.0;
      for (var l = 1; l < s.maxLevel; l++) {
        final need = xpToNext(s, l);
        // normal kid at Lv l plays stage l and wins ~70 %
        final per =
            0.7 * xpSinglePlayer(win: true, stage: l, level: l) +
            0.3 * xpSinglePlayer(win: false, stage: l, level: l);
        battles += need / per;
        if (l < s.rebirthLevel) {
          // hidden bloomer: as strong as a normal Lv ~(l/4) → plays that stage
          final st = l ~/ 4 < 1 ? 1 : l ~/ 4;
          final bp =
              0.7 *
                  xpSinglePlayer(
                    win: true,
                    stage: st,
                    level: l,
                    hiddenBloomer: true,
                  ) +
              0.3 *
                  xpSinglePlayer(
                    win: false,
                    stage: st,
                    level: l,
                    hiddenBloomer: true,
                  );
          bloomerBattles += need / bp;
        }
        if (l % 5 == 0 || l < 5 || l == 99) {
          stdout.writeln(
            'Lv$l→${l + 1}: need $need, total to ${l + 1}: '
            '${totalXpTo(s, l + 1)}, ~${battles.toStringAsFixed(0)} battles'
            '${l < s.rebirthLevel ? ' (hidden bloomer ~${bloomerBattles.toStringAsFixed(0)})' : ''}',
          );
        }
      }
    case 'stages':
      final n = nArg(1, 1000);
      final from = nArg(2, 1);
      final to = nArg(3, 100);
      for (final st in stageTable()) {
        if (st.stage >= from && st.stage <= to) {
          stdout.writeln(simulateStage(s, st, n: n));
        }
      }
    default:
      final n = nArg(cmd == 'scenarios' ? 1 : 0, 4000);
      for (final r in standardScenarios(s, n: n)) {
        stdout.writeln(r);
      }
  }
}
