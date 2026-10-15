import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main(List<String> args) {
  final n = int.parse(args[0]);
  for (final p in args.skip(1).map(int.parse)) {
    final bb = [
      for (var k = 1; k <= 5; k++) 100 * k * (100 + p * (k - 1)) ~/ 100,
    ];
    final s = V3Spec(barBudgets: bb);
    print('--- premium $p% $bb');
    for (final lv in [1, 20, 50, 100]) {
      print(
        runScenario(s, '5 vs 2 diff drawings Lv$lv', n, (r) {
          return (
            withLv1Sp(s, randomKid(s, r), lv, 55),
            withLv1Sp(s, randomKid(s, r), lv, 25),
          );
        }),
      );
    }
    print(
      runScenario(
        s,
        '5 vs 2 diff strong Lv20',
        n,
        (r) {
          return (
            withLv1Sp(s, randomKid(s, r), 20, 55),
            withLv1Sp(s, randomKid(s, r), 20, 25),
          );
        },
        tierA: AiTier.strong,
        tierB: AiTier.strong,
      ),
    );
    print(
      runScenario(
        s,
        'kid vs kid Lv20',
        n,
        (r) =>
            (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
      ),
    );
    print(
      runScenario(
        s,
        'kid vs kid Lv50',
        n,
        (r) =>
            (setupAt(s, randomKid(s, r), 50), setupAt(s, randomKid(s, r), 50)),
      ),
    );
  }
}
