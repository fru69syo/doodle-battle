import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main() {
  const s = V3Spec();
  for (final lv in [20, 50]) {
    print(
      runScenario(s, 'SP55 stats, 2 bars vs SP25 2 bars Lv$lv', 400, (r) {
        final g = randomKid(s, r);
        final a = withLv1Sp(s, g, lv, 55);
        final b = withLv1Sp(s, g, lv, 25);
        return (setupAt(s, g, lv, maxBars: 2).withStats(a.stats), b);
      }),
    );
    print(
      runScenario(s, 'stats x0.93 all Lv$lv', 400, (r) {
        final g = randomKid(s, r);
        final f = setupAt(s, g, lv);
        return (f.withStats([for (final x in f.stats) x * 93 ~/ 100]), f);
      }),
    );
  }
}
