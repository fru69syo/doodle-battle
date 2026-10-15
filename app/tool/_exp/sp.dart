import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main() {
  const s = V3Spec();
  final r = Mulberry32(5);
  final g = randomKid(s, r);
  print('base ${g.base} lv20 ${g.statsAt(20)} growth ${g.growthMille}');
  final a = withLv1Sp(s, g, 20, 55);
  final b = withLv1Sp(s, g, 20, 25);
  print('A ${a.stats} ${a.maxBars} sum ${a.stats.reduce((x, y) => x + y)}');
  print('B ${b.stats} ${b.maxBars} sum ${b.stats.reduce((x, y) => x + y)}');
}
