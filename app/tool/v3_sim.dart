// Battle v3 balance simulator on the production engine (docs/BATTLE_V3.md).
//   cd app && dart run tool/v3_sim.dart [battles]        scenario table
//   dart run tool/v3_sim.dart stages [battles] [from] [to]  stage win curve
//                                                         (bundled CPU doodles)
//   dart run tool/v3_sim.dart xp                          XP / level table
//   dart run tool/v3_sim.dart spec                        writes battle_spec_v3.json
//   dart run tool/v3_sim.dart golden                      writes golden_vectors.json
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/golden.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';
import 'package:doodle_battle/domain/battle_v3/spec_export.dart';
import 'package:doodle_battle/domain/cpu_roster_v2.dart';

String _pretty(Object o) =>
    '${const JsonEncoder.withIndent('  ').convert(o)}\n';

void main(List<String> args) {
  const s = V3Spec();
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
      final roster = CpuRosterV2.fromManifestJson(
        (jsonDecode(File(kCpuManifestV2Path).readAsStringSync()) as Map)
            .cast<String, Object?>(),
      );
      final cpu = {for (final c in roster.characters) c.id: c.genome(s)};
      final byPos = List<double>.filled(10, 0);
      final worlds = <int, List<int>>{};
      var sumSec = 0.0;
      var count = 0;
      for (final st in stageTable()) {
        if (st.stage >= from && st.stage <= to) {
          final r = simulateStage(s, st, n: n, cpuGenomes: cpu);
          stdout.writeln(r);
          byPos[st.position - 1] += r.winRateA;
          (worlds[st.world] ??= []).add((r.winRateA * 100).round());
          sumSec += r.avgSeconds;
          count++;
        }
      }
      stdout.writeln(
        '\n| world | ${[for (var p = 1; p <= 10; p++) p].join(' | ')} |',
      );
      for (final e in worlds.entries) {
        stdout.writeln('| ${e.key} | ${e.value.join(' | ')} |');
      }
      if (count == 100) {
        stdout.writeln(
          '| avg | ${[for (final v in byPos) (v * 10).round()].join(' | ')} |',
        );
      }
      stdout.writeln('avg length ${(sumSec / count).toStringAsFixed(1)} s');
    default:
      final n = nArg(cmd == 'scenarios' ? 1 : 0, 4000);
      for (final r in standardScenarios(s, n: n)) {
        stdout.writeln(r);
      }
  }
}
