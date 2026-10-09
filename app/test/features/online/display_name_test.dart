import 'dart:io';

import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/backend/backend_api.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/features/online/display_name_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

const _shared = '../shared/names/display_name_words.json';

final online = setupDone.copyWith(consents: const ParentConsents(online: true));

Future<TestApp> openLobby(
  WidgetTester tester, {
  FakeBackend? backend,
  GameProgress progress = const GameProgress(),
}) async {
  final app = await pumpApp(
    tester,
    backend: backend ?? FakeBackend(),
    settings: online,
    progress: progress,
    characters: [testCharacter(level: 5)],
  );
  await tapVisible(tester, find.byKey(const Key('home-online')));
  return app;
}

/// Scrolls the word list inside the sheet and taps [finder].
Future<void> tapWord(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('display-name-words')),
      matching: find.byType(Scrollable),
    ),
  );
  Scrollable.ensureVisible(finder.evaluate().single, alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('display-name-save')));
  await tester.pumpAndSettle();
}

void main() {
  test('bundled words are byte-identical to shared/names (server source)', () {
    expect(
      File(displayNameWordsAsset).readAsBytesSync(),
      File(_shared).readAsBytesSync(),
      reason: 'run `dart run tool/sync_shared_names.dart`',
    );
  });

  test('word lists: unique ids, kana text, server composition', () {
    final w = DisplayNameWords.fromJsonString(File(_shared).readAsStringSync());
    expect(w.adjectives, hasLength(30));
    expect(w.nouns, hasLength(30));
    for (final list in [w.adjectives, w.nouns]) {
      expect({for (final x in list) x.id}, hasLength(list.length));
      for (final x in list) {
        expect(x.id, matches(RegExp(r'^[an]\d{2}$')));
        expect(x.text, matches(RegExp(r'^[ぁ-ゖァ-ヺー]+$')));
      }
    }
    // Same as the server's composeDisplayName("a01", "n01").
    expect(w.compose(w.adjective('a01')!, w.noun('n01')!), 'あおい ドラゴン');
    expect(w.adjective('zzz'), isNull);
  });

  testWidgets('lobby: pick adjective + noun → setDisplayName with ids', (
    tester,
  ) async {
    final backend = FakeBackend();
    final app = await openLobby(tester, backend: backend);
    expect(find.text('まだ きまって いないよ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('display-name-change')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('display-name-save'));
    expect(tester.widget<ButtonStyleButton>(save).enabled, isFalse);
    await tapWord(tester, find.byKey(const Key('dn-adj-a07')));
    await tapWord(tester, find.byKey(const Key('dn-noun-n06')));
    expect(find.text('きらきら ペンギン'), findsOneWidget);
    await tapSave(tester);
    expect(backend.displayNames, [('a07', 'n06')]);
    // Consent is synced before the first server call.
    expect(backend.calls.first, 'syncConsent');
    final saved = app.settingsRepo.progress.displayName!;
    expect((saved.adjectiveId, saved.nounId), ('a07', 'n06'));
    // The server's text is shown (FakeBackend echoes the ids).
    expect(find.text('a07 n06'), findsOneWidget);
    expect(find.byKey(const Key('display-name-save')), findsNothing);
  });

  testWidgets('failure keeps the sheet open with a kind message', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..displayNameError = const BackendException(BackendCodes.network);
    final app = await openLobby(tester, backend: backend);
    await tester.tap(find.byKey(const Key('display-name-change')));
    await tester.pumpAndSettle();
    await tapWord(tester, find.byKey(const Key('dn-adj-a01')));
    await tapWord(tester, find.byKey(const Key('dn-noun-n01')));
    await tapSave(tester);
    expect(find.byKey(const Key('display-name-error')), findsOneWidget);
    expect(app.settingsRepo.progress.displayName, isNull);
  });

  testWidgets('current choice is preselected', (tester) async {
    await openLobby(
      tester,
      progress: const GameProgress(
        displayName: ChosenDisplayName(
          adjectiveId: 'a02',
          nounId: 'n03',
          text: 'あかい イヌ',
        ),
      ),
    );
    expect(find.text('あかい イヌ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('display-name-change')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('display-name-preview')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('display-name-preview'))).data,
      'あかい イヌ',
    );
  });

  test('display name survives a JSON round trip', () {
    const p = GameProgress(
      displayName: ChosenDisplayName(
        adjectiveId: 'a01',
        nounId: 'n01',
        text: 'あおい ドラゴン',
      ),
    );
    expect(GameProgress.fromJson(p.toJson()).displayName, p.displayName);
    expect(GameProgress.fromJson(const {}).displayName, isNull);
  });
}
