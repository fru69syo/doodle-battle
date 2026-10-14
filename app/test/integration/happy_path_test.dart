// Whole-app happy path with the real router, real parental gate dialog and
// in-memory fakes: setup → draw (fake image) → birth → name → CPU battle →
// level up.
import 'dart:math';

import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/features/parental_gate/parental_gate.dart';
import 'package:doodle_battle/features/battle_stage/stage_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

Future<void> passRealGate(WidgetTester tester) async {
  final g = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('gate-hold'))),
  );
  await tester.pump();
  for (var i = 0; i < 13; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await g.up();
  await tester.pumpAndSettle();
  final q = tester.widget<Text>(find.byKey(const Key('gate-question'))).data!;
  final m = RegExp(r'(\d+) × (\d+)').firstMatch(q)!;
  final answer = int.parse(m[1]!) * int.parse(m[2]!);
  for (final ch in '$answer'.split('')) {
    await tester.ensureVisible(find.byKey(Key('gate-key-$ch')));
    await tester.tap(find.byKey(Key('gate-key-$ch')));
    await tester.pump();
  }
  await tester.ensureVisible(find.byKey(const Key('gate-ok')));
  await tester.tap(find.byKey(const Key('gate-ok')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('setup → draw → birth → battle → level up', (tester) async {
    final app = await pumpApp(
      tester,
      settings: const AppSettings(),
      gate: DialogParentalGate(random: Random(11)),
    );

    // 1. First-run parent setup behind the real gate.
    await tapVisible(tester, find.byKey(const Key('setup-start')));
    expect(find.byType(ParentalGateDialog), findsOneWidget);
    await passRealGate(tester);
    await tapVisible(tester, find.byKey(const Key('consent-ads')));
    await tapVisible(tester, find.byKey(const Key('setup-finish')));
    expect(find.byKey(const Key('home-draw')), findsOneWidget);

    // 2. Draw: photo from the (fake) camera, (fake) on-device analysis.
    await tapVisible(tester, find.byKey(const Key('home-draw')));
    await tapVisible(tester, find.byKey(const Key('draw-camera')));
    // Capture guide (しろい かみ・ふとい せん・あかるい ばしょ) → shoot.
    await tapVisible(tester, find.byKey(const Key('guide-shoot')));
    expect(app.analyzer.calls, 1);

    // 3. Birth reveal, then naming.
    expect(find.text('うまれたよ！'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('birth-name')));
    await tester.enterText(find.byKey(const Key('name-field')), 'ドラゴン');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('name-save')));
    expect(find.byKey(const Key('detail-level')), findsOneWidget);
    final id = (await app.characters.loadAll()).single.id;

    // 4. Single-player stage 1 (real-time ATB on the 2.5D stage) from the
    // character page: world → stage.
    await tapVisible(tester, find.byKey(const Key('detail-battle')));
    await tapVisible(tester, find.byKey(const Key('world-1')));
    await tapNoSettle(tester, find.byKey(const Key('stage-1')));
    // A small child turns おまかせ on (remembered), and may lose and try
    // again (もういちど) until the first win.
    await settleReal(tester, rounds: 10);
    await tester.tap(find.byType(OmakaseToggle));
    await tester.pump();
    var tries = 0;
    for (;;) {
      await playBattle(tester);
      if (find.text('かった！').evaluate().isNotEmpty) break;
      expect(++tries, lessThan(6), reason: 'stage 1 should be winnable');
      await tapNoSettle(tester, find.byKey(const Key('result-retry')));
    }
    expect(find.byKey(const Key('result-levelup')), findsOneWidget);
    final beforeAd = (await app.characters.loadAll()).single;

    // 5. Rewarded ad was allowed in the setup: notice, then double XP.
    await tapVisible(tester, find.byKey(const Key('ad-double-xp')));
    await tester.tap(find.byKey(const Key('kid-ask-yes')));
    await tester.pumpAndSettle();
    expect(app.monetization.adsShown, 1);

    final c = (await app.characters.loadAll()).single;
    expect(c.id, id);
    expect(c.name, 'ドラゴン');
    // The ad doubled the XP of the winning battle.
    expect(c.level, greaterThan(beforeAd.level));
    expect(app.settingsRepo.progress.clearedStage, 1);

    // 6. Back home; ずかん shows the grown character and its 10 stats.
    await tapVisible(tester, find.byKey(const Key('result-home')));
    await tapVisible(tester, find.byKey(const Key('home-zukan')));
    await tapVisible(tester, find.byKey(Key('zukan-card-$id')));
    expect(find.text('Lv${c.level}'), findsOneWidget);
    expect(find.byKey(const Key('stat-agi')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('detail-move-0')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('detail-move-0')), findsOneWidget);
  });
}
