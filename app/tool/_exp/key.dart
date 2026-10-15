import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main(List<String> args) {
  final n = int.parse(args[0]);
  final bb = args[1].split(',').map(int.parse).toList();
  final dmg = args.length > 2 ? int.parse(args[2]) : 60;
  final s = V3Spec(barBudgets: bb, damageScalePct: dmg);
  void run(String name, PairMaker m, {AiTier ta = AiTier.normal, AiTier tb = AiTier.normal, Controller? ca}) {
    final x = runScenario(s, name, n, m, tierA: ta, tierB: tb, controllerA: ca);
    print(x);
  }
  print('--- bars $bb dmg $dmg');
  run('kid vs kid Lv20', (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)));
  run('mirror Lv1', (r) { final f = setupAt(s, randomKid(s, r), 1); return (f, f); });
  run('triangle random Lv20', (r) {
    final a = Attr.values[r.nextInt(3)];
    return (setupAt(s, randomKid(s, r), 20, attr: a), setupAt(s, randomKid(s, r), 20, attr: a.beats));
  });
  run('triangle same Lv50', (r) {
    final g = randomKid(s, r);
    final a = Attr.values[r.nextInt(3)];
    return (setupAt(s, g, 50, attr: a), setupAt(s, g, 50, attr: a.beats));
  });
  run('kid95 vs kid60 Lv20', (r) => (setupAt(s, randomKid(s, r, energy10: 960, skill10: 60), 20), setupAt(s, randomKid(s, r, energy10: 520, skill10: 380), 20)));
  run('bloomer vs kid Lv49', (r) => (setupAt(s, randomBloomer(s, r), 49), setupAt(s, randomKid(s, r), 49)));
  for (final lv in [50, 100]) {
    run('bloomer vs kid Lv$lv', (r) => (setupAt(s, randomBloomer(s, r), lv), setupAt(s, randomKid(s, r), lv)));
  }
  for (final lv in [5, 20, 50]) {
    run('strong vs normal Lv$lv', (r) => (setupAt(s, randomKid(s, r), lv), setupAt(s, randomKid(s, r), lv)), ta: AiTier.strong);
  }
  run('normal vs weak Lv20', (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)), tb: AiTier.weak);
  for (final lv in [1, 20, 50]) {
    run('5 vs 2 bars Lv$lv', (r) => (withLv1Sp(s, randomKid(s, r), lv, 55), withLv1Sp(s, randomKid(s, r), lv, 25)));
  }
  for (final lv in [20, 50]) {
    run('omakase vs 1s Lv$lv', (r) => (setupAt(s, randomKid(s, r), lv), setupAt(s, randomKid(s, r), lv)), ca: omakaseController());
  }
}
