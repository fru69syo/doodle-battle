import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/backend/backend_api.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/features/online/online_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

const _allRejections = [
  'LEVEL_TOO_LOW',
  'STATS_INVALID',
  'NAME_INVALID',
  'NAME_NG',
  'NAME_PERSONAL_INFO', //
  'IMAGE_VIOLENCE',
  'IMAGE_SEXUAL',
  'IMAGE_HATE',
  'IMAGE_COPYRIGHT',
  'IMAGE_REAL_PERSON',
  'IMAGE_PERSONAL_INFO',
  'IMAGE_NOT_DRAWING',
  'IMAGE_OTHER',
  'TOO_MANY_CHARACTERS',
];

Map<String, Object?> sideJson(String? uid, String name, {int level = 5}) => {
  'uid': uid,
  'isGhost': uid == null,
  'snapshotId': 'snap_$name',
  'displayName': {'text': 'あおい ドラゴン'},
  'characterName': name,
  'element': 'water',
  'level': level,
  'isShobo': false,
  'evolution': 'normal',
  'stats': {'hp': 100, 'atk': 90, 'def': 80, 'spd': 70},
  'imagePath': 'snapshotImages/x/image.png',
  'moveNames': {'element': 'みずでっぽう', 'special': null},
};

MatchSnapshot snapshot({
  required int turn,
  String status = 'active',
  int hpA = 300,
  int hpB = 300,
  Map<String, Object?>? result,
}) => MatchSnapshot.fromJson('m1', {
  'status': status,
  'turn': turn,
  'sides': {'a': sideJson('uid-1', 'ねこまる'), 'b': sideJson(null, 'さかなくん')},
  'view': {
    'a': {'hp': hpA, 'maxHp': 300, 'gauge': 0},
    'b': {'hp': hpB, 'maxHp': 300, 'gauge': 0},
  },
  'submitted': {'a': false, 'b': false},
  'winner': status == 'finished' ? 'a' : null,
  'result': ?result,
}, myUid: 'uid-1');

void main() {
  test('every registerCharacter rejection reason has a gentle message', () {
    for (final r in _allRejections) {
      expect(registerRejectionMessages[r], isNotNull, reason: r);
    }
    expect(
      registerRejectionMessage('IMAGE_REAL_PERSON'),
      'ひとの しゃしんや かおは つかえないよ',
    );
    expect(
      backendErrorMessage(BackendCodes.rateLimited),
      isNot(contains('INTERNAL')),
    );
  });

  test('match parsing picks my side by uid', () {
    final s = MatchSnapshot.fromJson('m', {
      'turn': 2,
      'sides': {'a': sideJson('other', 'あ'), 'b': sideJson('me', 'い')},
      'view': {},
    }, myUid: 'me');
    expect(s.mySide, Side.b);
    expect(s.opponent.characterName, 'あ');
    expect(s.me.displayName, 'あおい ドラゴン');
  });

  test('turn logs skip unknown events', () {
    final events = parseTurnEvents([
      {'type': 'turnStart', 'turn': 1},
      {'type': 'somethingNew'},
      {
        'type': 'damage',
        'target': 'b',
        'amount': 10,
        'hp': 90,
        'guarded': false,
      },
    ]);
    expect(events.map((e) => e.type), ['turnStart', 'damage']);
  });

  testWidgets('register (name rejected → preset) → queue → battle → XP once', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..registerOutcomes.addAll(const [
        RegisterRejected(reason: 'NAME_NG', presetNames: ['もこたん', 'ぴかりん']),
        RegisterAccepted(snapshotId: 'snap_1', name: 'もこたん'),
      ])
      ..queueResults.add(const QueueStatus(QueueState.matched, matchId: 'm1'));
    final app = await pumpApp(
      tester,
      backend: backend,
      settings: setupDone.copyWith(
        consents: const ParentConsents(online: true),
      ),
      characters: [testCharacter(level: 5)],
    );
    await tapVisible(tester, find.byKey(const Key('home-online')));
    await tester.tap(find.byKey(const Key('select-c_1')));
    await tester.pump();
    await tester.pump();
    expect(find.text(registerRejectionMessage('NAME_NG')), findsOneWidget);
    await tester.tap(find.byKey(const Key('online-preset-もこたん')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      backend.calls,
      containsAllInOrder([
        'registerCharacter:ねこまる',
        'registerCharacter:もこたん',
        'joinQueue',
      ]),
    );
    var c = (await app.characters.loadAll()).single;
    expect((c.name, c.onlineId), ('もこたん', 'snap_1'));
    expect(app.settingsRepo.progress.onlineLevels['c_1'], 5);

    // Match screen: first snapshot.
    backend.matchController.add(snapshot(turn: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('のこり 20びょう'), findsOneWidget);
    expect(find.text('さかなくん'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('のこり 17びょう'), findsOneWidget);

    await tester.tap(find.byKey(const Key('move-tackle')));
    await tester.pump();
    expect(backend.submitted, [(1, BattleAction.tackle)]);
    expect(find.text('まってね'), findsOneWidget);

    // Report the opponent with a preset reason.
    await tester.tap(find.byKey(const Key('report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-bad_name')));
    await tester.pumpAndSettle();
    expect(backend.reports.single, ('snap_さかなくん', ReportReason.badName));
    await tester.tap(find.byKey(const Key('kid-message-ok')));
    await tester.pumpAndSettle();

    // Turn 1 resolved and the match ends.
    backend.turnLogs[1] = const [
      TurnStartEvent(1),
      MoveEvent(Side.a, BattleAction.tackle),
      DamageEvent(Side.b, amount: 300, hp: 0, guarded: false),
      FaintEvent(Side.b),
      BattleEndEvent(Side.a, EndReason.ko),
    ];
    backend.matchController.add(
      snapshot(
        turn: 1,
        status: 'finished',
        hpB: 0,
        result: {
          'a': {'xp': 100, 'outcome': 'win', 'ratingDelta': 16},
          'b': {'xp': 40, 'outcome': 'lose'},
        },
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('かった！'), findsOneWidget);
    expect(find.text('けいけんち +100'), findsOneWidget);
    c = (await app.characters.loadAll()).single;
    expect((c.level, c.xp), (5, 100));
    expect(app.settingsRepo.progress.appliedMatchIds, ['m1']);
    await unmount(tester);
  });

  testWidgets('an image rejection shows its kid message and no presets', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..registerOutcomes.add(
        const RegisterRejected(reason: 'IMAGE_REAL_PERSON'),
      );
    await pumpApp(
      tester,
      backend: backend,
      settings: setupDone.copyWith(
        consents: const ParentConsents(online: true),
      ),
      characters: [testCharacter(level: 6)],
    );
    await tapVisible(tester, find.byKey(const Key('home-online')));
    await tester.tap(find.byKey(const Key('select-c_1')));
    await tester.pump();
    await tester.pump();
    expect(find.text('ひとの しゃしんや かおは つかえないよ'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(backend.calls, isNot(contains('joinQueue')));
    await unmount(tester);
  });

  testWidgets('waiting in the queue sends heartbeats and leaves on cancel', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..queueResults.add(const QueueStatus(QueueState.waiting, waitedMs: 0));
    await pumpApp(
      tester,
      backend: backend,
      settings: setupDone.copyWith(
        consents: const ParentConsents(online: true),
      ),
      progress: const GameProgress(onlineLevels: {'c_1': 6}),
      characters: [testCharacter(level: 6, onlineId: 'snap_9')],
    );
    await tapVisible(tester, find.byKey(const Key('home-online')));
    await tester.tap(find.byKey(const Key('select-c_1')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('online-waiting')), findsOneWidget);
    expect(
      backend.calls.where((c) => c.startsWith('registerCharacter')),
      isEmpty,
    );
    await tester.pump(const Duration(seconds: 21));
    expect(backend.calls.where((c) => c == 'joinQueue').length, 3);
    await tester.tap(find.text('やめる'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(backend.calls.last, 'leaveQueue');
    await unmount(tester);
  });
}
