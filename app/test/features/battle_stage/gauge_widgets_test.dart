// The stackable gauge and the move buttons (bars as pips, dimmed but still
// tappable for さきどり, never a countdown).
import 'package:doodle_battle/features/battle_stage/stage_events.dart';
import 'package:doodle_battle/features/battle_stage/stage_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);

void main() {
  testWidgets('the gauge shows max bars segments with partial fill', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AtbGauge(bars: 2.4, maxBars: 4)));
    final bars = [
      for (var i = 0; i < 4; i++)
        tester.widget<StageBar>(find.byKey(Key('atb-bar-$i'))),
    ];
    expect([for (final b in bars) b.value], [1.0, 1.0, closeTo(0.4, 1e-9), 0]);
    expect(bars.where((b) => b.glow), isEmpty);
    expect(find.byKey(const Key('atb-bar-4')), findsNothing);

    await tester.pumpWidget(_wrap(const AtbGauge(bars: 3, maxBars: 3)));
    expect(
      [
        for (var i = 0; i < 3; i++)
          tester.widget<StageBar>(find.byKey(Key('atb-bar-$i'))).glow,
      ],
      [true, true, true],
    );
  });

  testWidgets('move buttons: pips, dimmed while unaffordable, still tappable', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      _wrap(
        BattleControls(
          moves: const [
            MoveButtonData(name: 'パンチ', tint: MoveTint.gu),
            MoveButtonData(name: 'ビーム', tint: MoveTint.none, bars: 3),
            MoveButtonData(name: 'ドカン', tint: MoveTint.special, bars: 5),
          ],
          onTap: taps.add,
          omakase: false,
          onOmakase: (_) {},
          bars: 1,
          usable: (i) => i == 0,
          queueable: (i) => i < 2, // 5 bars do not fit a 3-bar character
        ),
      ),
    );
    final pips = find.byType(BarPips);
    expect(
      [for (final e in pips.evaluate()) (e.widget as BarPips).count],
      [1, 3, 5],
    );
    expect(find.byKey(const Key('decision-ring')), findsNothing);
    expect(find.text('わざを えらんでね！'), findsOneWidget);
    final b1 = tester.widget<MoveButton>(find.byKey(const Key('move-1')));
    expect((b1.enabled, b1.affordable), (true, false));
    await tester.tap(find.byKey(const Key('move-1')));
    await tester.tap(find.byKey(const Key('move-2')));
    expect(taps, [1]); // the 5-bar move can never be queued
  });

  test('fighter state: bars, ready and full', () {
    const s = StageFighterState(maxHp: 10, gauge: 2.7, maxBars: 3);
    expect((s.bars, s.ready, s.full), (2, true, false));
    const f = StageFighterState(maxHp: 10, gauge: 3, maxBars: 3);
    expect(f.full, isTrue);
    const e = StageFighterState(maxHp: 10, gauge: 0.9);
    expect(e.ready, isFalse);
  });
}
