import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main(List<String> args) {
  final n = int.parse(args[0]);
  final bb = args[1].split(',').map(int.parse).toList();
  final s = V3Spec(barBudgets: bb);
  for (final lv in [5, 20, 50]) {
    print(runScenario(s, 'strong vs normal Lv$lv', n, (r) => (setupAt(s, randomKid(s, r), lv), setupAt(s, randomKid(s, r), lv)), tierA: AiTier.strong));
    print(runScenario(s, 'strong0 vs normal Lv$lv (think 10)', n, (r) => (setupAt(s, randomKid(s, r), lv), setupAt(s, randomKid(s, r), lv)), tierA: AiTier.strong, thinkTicksA: 10));
    print(runScenario(s, 'normal(think4) vs normal Lv$lv', n, (r) => (setupAt(s, randomKid(s, r), lv), setupAt(s, randomKid(s, r), lv)), thinkTicksA: 4));
  }
}
