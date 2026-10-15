import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main() {
  const s = V3Spec();
  for (final lv in [1, 10, 20, 50, 100]) {
    print(
      runScenario(s, '5 vs 2 bars diff drawings Lv$lv', 1000, (r) {
        return (
          withLv1Sp(s, randomKid(s, r), lv, 55),
          withLv1Sp(s, randomKid(s, r), lv, 25),
        );
      }),
    );
    print(
      runScenario(
        s,
        '5 vs 2 bars diff drawings strong Lv$lv',
        1000,
        (r) {
          return (
            withLv1Sp(s, randomKid(s, r), lv, 55),
            withLv1Sp(s, randomKid(s, r), lv, 25),
          );
        },
        tierA: AiTier.strong,
        tierB: AiTier.strong,
      ),
    );
  }
}
