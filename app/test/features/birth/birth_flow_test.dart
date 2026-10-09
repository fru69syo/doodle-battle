import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/app_state.dart';
import 'package:doodle_battle/data/backend/backend_api.dart';
import 'package:doodle_battle/features/draw/drawing_services.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Future<void> drawFromGallery(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('home-draw')));
  await tapVisible(tester, find.byKey(const Key('draw-gallery')));
}

Future<void> nameAndSave(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('name-field')), name);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const Key('name-save')));
}

void main() {
  testWidgets('draw → reveal → name → saved in ずかん', (tester) async {
    final app = await pumpApp(tester);
    await drawFromGallery(tester);
    expect(app.imageSource.picked, [PhotoSource.gallery]);
    expect(app.analyzer.calls, 1);
    await tester.pumpAndSettle(); // reveal animation
    expect(find.text('うまれたよ！'), findsOneWidget);
    expect(find.byKey(const Key('birth-shobo')), findsNothing);
    expect(find.text('めらめらパンチ'), findsOneWidget); // default fire move
    await tapVisible(tester, find.byKey(const Key('birth-name')));

    await nameAndSave(tester, 'ほのおまる');
    final chars = await app.characters.loadAll();
    expect(chars.single.name, 'ほのおまる');
    expect(chars.single.level, 1);
    expect(await app.characters.readImage(chars.single.id), isNotNull);
    expect(find.byKey(const Key('detail-level')), findsOneWidget);
    expect(find.text('ほのおまる'), findsWidgets);
  });

  testWidgets('しょぼキャラ gets the げいじゅつか message and the growth hint', (
    tester,
  ) async {
    await pumpApp(
      tester,
      analyzer: FakeAnalyzer(result: fakeAnalysis(skill: 90)),
    );
    await drawFromGallery(tester);
    await tester.pumpAndSettle();
    expect(find.text('げいじゅつか すぎて しょぼキャラに なっちゃった！'), findsOneWidget);
    final growth = tester
        .widget<Text>(find.byKey(const Key('birth-shobo-growth')))
        .data!;
    expect(growth, contains('3ばい はやい'));
    expect(find.text('げいじゅつか'), findsOneWidget); // title badge
  });

  testWidgets('a nearly empty drawing asks to draw more', (tester) async {
    final app = await pumpApp(
      tester,
      analyzer: FakeAnalyzer(reject: DrawingRejectReason.nearlyEmpty),
    );
    await drawFromGallery(tester);
    expect(find.text('もうすこし かいてみよう'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kid-message-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('draw-gallery')), findsOneWidget);
    expect(await app.characters.loadAll(), isEmpty);
  });

  testWidgets('an unreadable photo shows a gentle message', (tester) async {
    await pumpApp(tester, analyzer: FakeAnalyzer(undecodable: true));
    await drawFromGallery(tester);
    expect(find.textContaining('しゃしんが よめなかったよ'), findsOneWidget);
  });

  testWidgets('NG names are refused offline, suggestions can be used', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await drawFromGallery(tester);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('birth-name')));

    Future<String?> problemFor(String name) async {
      await tester.enterText(find.byKey(const Key('name-field')), name);
      await tester.pumpAndSettle();
      final f = find.byKey(const Key('name-problem'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    expect(await problemFor('しね'), 'その なまえは つかえないよ。ほかの なまえに してね');
    expect(
      await problemFor('ﾊﾞｶ'),
      isNotNull,
    ); // half-width katakana normalised
    expect(await problemFor('090-1234-5678'), isNotNull);
    expect(await problemFor('ねこ123'), 'すうじは 2つ までだよ');
    expect(await problemFor('ねこ😀'), 'ひらがな・カタカナ・かんじ・えいご・すうじで かいてね');
    final saveButton = find.byKey(const Key('name-save'));
    expect(tester.widget<ButtonStyleButton>(saveButton).enabled, isFalse);
    expect(await problemFor('ねこまる'), isNull);

    // Tapping a preset suggestion fills the field.
    final chip = find
        .byWidgetPredicate(
          (w) =>
              w is ActionChip && w.key.toString().contains('name-suggestion-'),
        )
        .first;
    await tapVisible(tester, chip);
    await tapVisible(tester, saveButton);
    final name = (await app.characters.loadAll()).single.name;
    expect(name, isNot('ねこまる'));
  });

  testWidgets('cloud judging (consented) blends skill and suggests names', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..judgement = const CloudJudgement(
        subject: 'ねこ',
        suggestedNames: ['にゃんた', 'みけまる', 'ねこりん'],
        elementMoveName: 'にゃんにゃんぱんち',
        specialMoveName: 'ねこびーむ',
        skillEstimate: 80,
        appropriate: true,
      );
    final app = await pumpApp(
      tester,
      backend: backend,
      settings: setupDone.copyWith(
        consents: const ParentConsents(cloudJudge: true),
      ),
    );
    await drawFromGallery(tester);
    await tester.pumpAndSettle();
    expect(backend.calls, containsAllInOrder(['syncConsent', 'judgeDrawing']));
    expect(find.text('にゃんにゃんぱんち'), findsOneWidget);
    expect(find.text('ねこ の キャラ'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('birth-name')));
    expect(find.byKey(const Key('name-suggestion-にゃんた')), findsOneWidget);
    await nameAndSave(tester, 'にゃんた');
    final c = (await app.characters.loadAll()).single;
    // 0.6 × 20 + 0.4 × 80 = 44
    expect(c.skill, 44);
    expect(c.subject, 'ねこ');
    expect(c.specialMoveName, 'ねこびーむ');
  });

  testWidgets('cloud failure silently falls back to the local result', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..judgeError = const BackendException(BackendCodes.aiUnavailable);
    final app = await pumpApp(
      tester,
      backend: backend,
      settings: setupDone.copyWith(
        consents: const ParentConsents(cloudJudge: true),
      ),
    );
    await drawFromGallery(tester);
    await tester.pumpAndSettle();
    expect(find.text('うまれたよ！'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('birth-name')));
    await nameAndSave(tester, 'ふつうまる');
    expect((await app.characters.loadAll()).single.skill, 20);
  });

  testWidgets('cloud judging is never called without consent', (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend: backend);
    await drawFromGallery(tester);
    await tester.pumpAndSettle();
    expect(backend.calls, isNot(contains('judgeDrawing')));
  });

  testWidgets('full collection: the draw screen points to ずかん', (tester) async {
    final app = await pumpApp(
      tester,
      characters: [for (var i = 0; i < 12; i++) testCharacter(id: 'c_$i')],
    );
    await tapVisible(tester, find.byKey(const Key('home-draw')));
    expect(find.byKey(const Key('draw-full')), findsOneWidget);
    expect(find.byKey(const Key('draw-gallery')), findsNothing);
    expect(app.container.read(collectionLimitProvider), 12);
  });

  testWidgets('the slots_24 entitlement raises the limit to 36', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      settings: setupDone.copyWith(entitlements: {'slots_24'}),
      characters: [for (var i = 0; i < 12; i++) testCharacter(id: 'c_$i')],
    );
    expect(app.container.read(collectionLimitProvider), 36);
    await tapVisible(tester, find.byKey(const Key('home-draw')));
    expect(find.byKey(const Key('draw-gallery')), findsOneWidget);
  });
}
