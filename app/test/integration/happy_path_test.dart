// Whole-app happy path with the real router, real parental gate dialog and
// in-memory fakes: setup → draw (fake image) → birth → name → CPU battle →
// level up.
import 'dart:math';

import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/features/parental_gate/parental_gate.dart';
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

    // 4. Battle stage 1 from the character page.
    await tapVisible(tester, find.byKey(const Key('detail-battle')));
    await tapVisible(tester, find.byKey(const Key('stage-1')));
    await fightUntilResult(tester);
    expect(find.text('かった！'), findsOneWidget);
    expect(find.byKey(const Key('result-levelup')), findsOneWidget);

    // 5. Rewarded ad was allowed in the setup: notice, then double XP.
    await tapVisible(tester, find.byKey(const Key('ad-double-xp')));
    await tester.tap(find.byKey(const Key('kid-ask-yes')));
    await tester.pumpAndSettle();
    expect(app.monetization.adsShown, 1);

    final c = (await app.characters.loadAll()).single;
    expect(c.id, id);
    expect(c.name, 'ドラゴン');
    expect(c.level, 3);
    expect(app.settingsRepo.progress.clearedStage, 1);

    // 6. Back home; ずかん shows the grown character with パワーのたね.
    await tapVisible(tester, find.byKey(const Key('result-home')));
    await tapVisible(tester, find.byKey(const Key('home-zukan')));
    await tapVisible(tester, find.byKey(Key('zukan-card-$id')));
    expect(find.text('Lv3'), findsOneWidget);
    expect(find.byKey(const Key('detail-seeds')), findsOneWidget);
    final before = tester.widget<Text>(find.byKey(const Key('stat-atk'))).data;
    await tapVisible(tester, find.byKey(const Key('seed-atk')));
    final after = tester.widget<Text>(find.byKey(const Key('stat-atk'))).data;
    expect(int.parse(after!), greaterThan(int.parse(before!)));
    expect(
      (await app.characters.loadAll()).single.seedAllocations.values.single,
      1,
    );
  });
}
