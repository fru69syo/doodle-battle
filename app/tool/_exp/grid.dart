import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main(List<String> args) {
  final n = int.parse(args[0]);
  final bb = args[1].split(',').map(int.parse).toList();
  final s = V3Spec(barBudgets: bb);
  void run(
    String name,
    PairMaker m, {
    AiTier ta = AiTier.normal,
    AiTier tb = AiTier.normal,
    Controller? ca,
  }) {
    final x = runScenario(s, name, n, m, tierA: ta, tierB: tb, controllerA: ca);
    print(
      '${name.padRight(28)} ${(x.winRateA * 100).toStringAsFixed(1)}%  ${x.avgSeconds.toStringAsFixed(1)}s',
    );
  }

  PairMaker kids(int lv) =>
      (r) => (setupAt(s, randomKid(s, r), lv), setupAt(s, randomKid(s, r), lv));
  run('kid vs kid Lv20', kids(20));
  run('triangle random Lv20', (r) {
    final a = Attr.values[r.nextInt(3)];
    return (
      setupAt(s, randomKid(s, r), 20, attr: a),
      setupAt(s, randomKid(s, r), 20, attr: a.beats),
    );
  });
  run('triangle same Lv1', (r) {
    final g = randomKid(s, r);
    final a = Attr.values[r.nextInt(3)];
    return (setupAt(s, g, 1, attr: a), setupAt(s, g, 1, attr: a.beats));
  });
  run('triangle same Lv50', (r) {
    final g = randomKid(s, r);
    final a = Attr.values[r.nextInt(3)];
    return (setupAt(s, g, 50, attr: a), setupAt(s, g, 50, attr: a.beats));
  });
  for (final lv in [5, 20, 50]) {
    run('strong vs normal Lv$lv', kids(lv), ta: AiTier.strong);
  }
  run('normal vs weak Lv20', kids(20), tb: AiTier.weak);
  run('omakase vs 1s Lv20', kids(20), ca: omakaseController());
  run('omakase vs 1s Lv50', kids(50), ca: omakaseController());
  for (final lv in [1, 50]) {
    run(
      '5v2 strong Lv$lv',
      (r) => (
        withLv1Sp(s, randomKid(s, r), lv, 55),
        withLv1Sp(s, randomKid(s, r), lv, 25),
      ),
      ta: AiTier.strong,
      tb: AiTier.strong,
    );
  }
  run(
    '5v2 normal Lv20',
    (r) => (
      withLv1Sp(s, randomKid(s, r), 20, 55),
      withLv1Sp(s, randomKid(s, r), 20, 25),
    ),
  );
  run(
    '5v2 strong Lv20',
    (r) => (
      withLv1Sp(s, randomKid(s, r), 20, 55),
      withLv1Sp(s, randomKid(s, r), 20, 25),
    ),
    ta: AiTier.strong,
    tb: AiTier.strong,
  );
}
