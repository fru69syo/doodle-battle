import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';

void main(List<String> args) {
  const s = V3Spec();
  final n = args.isEmpty ? 400 : int.parse(args[0]);
  for (final lv in [20, 50]) {
    for (final (ba, bb) in [(5, 2), (3, 2), (4, 2), (5, 3)]) {
      print(
        runScenario(s, 'same stats bars $ba vs $bb Lv$lv', n, (r) {
          final g = randomKid(s, r);
          return (
            setupAt(s, g, lv, maxBars: ba),
            setupAt(s, g, lv, maxBars: bb),
          );
        }),
      );
      print(
        runScenario(
          s,
          'same stats bars $ba vs $bb Lv$lv strong',
          n,
          (r) {
            final g = randomKid(s, r);
            return (
              setupAt(s, g, lv, maxBars: ba),
              setupAt(s, g, lv, maxBars: bb),
            );
          },
          tierA: AiTier.strong,
          tierB: AiTier.strong,
        ),
      );
    }
  }
  final r = Mulberry32(3);
  final g = randomKid(s, r);
  for (final mb in [2, 5]) {
    final f = setupAt(s, g, 50, maxBars: mb);
    for (final m in f.moves) {
      print(
        'mb$mb ${m.template} ${m.attr.name} pow ${m.power} hits ${m.hits} bars ${m.bars} pts ${movePoints(s, m)} cast ${m.castTicks} cd ${m.cooldownTicks} heal ${m.healPct}',
      );
    }
  }
}
