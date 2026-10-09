// Monte Carlo balance report for the battle spec.
//   cd app && dart run tool/balance_sim.dart [battlesPerScenario]
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle/balance_sim.dart';
import 'package:doodle_battle/domain/battle/battle_spec.dart';
import 'package:doodle_battle/domain/battle/cpu_roster.dart';

void main(List<String> args) {
  final n = args.isEmpty ? 10000 : int.parse(args.first);
  final spec = BattleSpec.fromJsonString(
    File('../shared/battle_spec/battle_spec.json').readAsStringSync(),
  );
  for (final r in standardScenarios(spec, n: n)) {
    stdout.writeln(r);
  }
  final roster = CpuRoster.fromManifestJson(
    (jsonDecode(File('assets/cpu/manifest.json').readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );
  stdout.writeln('--- CPU stages: player (kid, same level, seeds spent) ---');
  for (final st in spec.cpu.stages) {
    stdout.writeln(simulateStage(spec, roster, st, n: n ~/ 4));
  }
}
