import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main(List<String> args) {
  final p = int.parse(args[0]);
  final lv = int.parse(args[1]);
  final bb = [
    for (var k = 1; k <= 5; k++) 100 * k * (100 + p * (k - 1)) ~/ 100,
  ];
  final s = V3Spec(barBudgets: bb);
  final r = Mulberry32(9);
  final spent = [List.filled(6, 0), List.filled(6, 0)];
  var capTicks = [0, 0];
  var wins = 0;
  for (var i = 0; i < 300; i++) {
    final a = withLv1Sp(s, randomKid(s, r), lv, 55);
    final b = withLv1Sp(s, randomKid(s, r), lv, 25);
    final x = Battle(s, a, b, seed: i);
    final ca = aiController(tier: AiTier.strong),
        cb = aiController(tier: AiTier.strong);
    while (!x.finished) {
      final ev = x.step(a: ca, b: cb);
      for (var k = 0; k < 2; k++) {
        if (x.fighters[k].gauge >= x.fighters[k].maxBars * s.gaugeMax)
          capTicks[k]++;
      }
      for (final e in ev) {
        if (e.type == 'select')
          spent[e.i('side')!][e.i('cost')!] += e.i('cost')!;
      }
    }
    if (x.winner == 0) wins++;
  }
  print(
    'wins A $wins/300 spentA ${spent[0]} spentB ${spent[1]} capTicks $capTicks',
  );
  final g = randomKid(s, Mulberry32(4));
  for (final mb in [5, 2]) {
    for (final m in setupAt(s, g, lv, maxBars: mb).moves) {
      print(
        'mb$mb ${m.template} ${m.attr.name} pow ${m.power} hits ${m.hits} bars ${m.bars} pts ${movePoints(s, m)} cast ${m.castTicks} cd ${m.cooldownTicks} sec ${m.secondary.name}',
      );
    }
  }
}
