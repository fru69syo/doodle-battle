import 'dart:convert';

import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/backend/backend_api.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/character_v2_view.dart';
import 'package:doodle_battle/features/battle_stage/stage_events.dart';
import 'package:doodle_battle/features/battle_stage/stage_overlay.dart';
import 'package:doodle_battle/features/draw_canvas/stroke_drawing.dart';
import 'package:doodle_battle/features/online/online_messages.dart';
import 'package:doodle_battle/features/online/realtime/online_feed.dart';
import 'package:doodle_battle/features/online/realtime/realtime_client.dart';
import 'package:doodle_battle/features/online/realtime/realtime_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_realtime.dart';
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
  'IMAGE_AI_GENERATED',
  'IMAGE_OTHER',
  'TOO_MANY_CHARACTERS',
];

const _online = ParentConsents(online: true);

Map<String, Object?> ev(int seq, int tick, List<Map<String, Object?>> e) => {
  't': 'ev',
  'seq': seq,
  'tick': tick,
  'events': e,
};

Map<String, Object?> endMsg({
  String outcome = 'win',
  int xp = 150,
  String badge = 'rabbit',
  bool badgeUp = true,
  String reason = 'ko',
}) => {
  't': 'end',
  'matchId': 'm1',
  'winner': outcome == 'win' ? 'a' : 'b',
  'reason': reason,
  'you': {'outcome': outcome, 'xp': xp, 'badge': badge, 'badgeUp': badgeUp},
};

/// Pumps fake time and lets real async work (images, sprites) finish.
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('every registerCharacter rejection reason has a gentle message', () {
    for (final r in _allRejections) {
      expect(
        registerRejectionMessages.containsKey(r),
        isTrue,
        reason: 'missing message for $r',
      );
    }
  });

  group('protocol messages', () {
    test('client messages follow REALTIME_PROTOCOL §3', () {
      expect(jsonDecode(helloMsg(idToken: 't', lastSeq: 7)), {
        't': 'hello',
        'proto': 1,
        'idToken': 't',
        'lastSeq': 7,
      });
      expect(jsonDecode(queueMsg('Abc')), {'t': 'queue', 'snapshotId': 'Abc'});
      expect(jsonDecode(selectMsg(3, 1)), {'t': 'select', 'seq': 3, 'slot': 1});
      // Every later message stays far below the 512 byte limit.
      expect(utf8.encode(selectMsg(999999, 3)).length, lessThan(512));
    });

    test('server messages parse; unknown ones are ignored', () {
      final m = ServerMsg.parse(jsonEncode(matchMsg(you: 'b')))! as MatchMsg;
      expect(m.you, 1);
      expect(m.fighters[1].isGhost, isTrue);
      expect(m.fighters[0].moves.first.name, 'ねこまるパンチ');
      final e = ServerMsg.parse(jsonEncode(endMsg()))! as EndMsg;
      expect(
        (e.outcome, e.xp, e.badge, e.badgeUp),
        ('win', 150, 'rabbit', true),
      );
      expect(ServerMsg.parse('{"t":"future","x":1}'), isNull);
      expect(ServerMsg.parse('not json'), isNull);
      expect(realtimeErrorMessage('CONSENT_REQUIRED'), contains('おうちのひと'));
      expect(realtimeErrorMessage('DRAINING'), isNull); // silent
    });
  });

  group('OnlineFeed', () {
    test('plays server events ~200 ms late, as stage events', () {
      final feed = OnlineFeed(
        ServerMsg.parse(jsonEncode(matchMsg()))! as MatchMsg,
      );
      feed.addEvents(
        const EvMsg(
          seq: 1,
          tick: 10,
          events: [
            {'tick': 10, 'type': 'ready', 'side': 0},
            {'tick': 10, 'type': 'select', 'side': 0, 'slot': 0, 'cast': 0},
            {'tick': 10, 'type': 'moveStart', 'side': 0, 'slot': 0},
            {
              'tick': 10,
              'type': 'hit',
              'side': 0,
              'target': 1,
              'n': 1,
              'amount': 50,
              'hp': 850,
              'crit': 0,
              'pct': 150,
            },
            {'tick': 10, 'type': 'autoPick', 'side': 1, 'slot': 0},
            {'tick': 10, 'type': 'somethingNew', 'side': 1},
          ],
        ),
      );
      expect(feed.advance(0.05), isEmpty); // still behind the delay
      feed.addSnap(
        SnapMsg(
          tick: 12,
          sides: [
            SideView.fromJson(sideView(ready: true, gauge: 10000)),
            SideView.fromJson(sideView(hp: 850)),
          ],
        ),
      );
      final out = feed.advance(0.3);
      final action = out.whereType<StageAction>().single;
      expect(action.side, 0);
      expect(action.move.name, 'ねこまるパンチ');
      expect(action.hits.single.effectiveness, StageEffectiveness.strong);
      expect(feed.fighter(0).ready, isTrue);
      expect(feed.fighter(1).maxHp, 900);
    });

    test('the child is always side 0 on the stage (you = b)', () {
      final feed = OnlineFeed(
        ServerMsg.parse(jsonEncode(matchMsg(you: 'b')))! as MatchMsg,
      );
      expect(feed.moves[0].first.name, 'さかなくんパンチ');
      feed.addEvents(
        const EvMsg(
          seq: 1,
          tick: 5,
          events: [
            {'tick': 5, 'type': 'moveStart', 'side': 1, 'slot': 0},
          ],
        ),
      );
      feed.finish(1); // server says b (= me) won
      final out = feed.advance(0.1);
      expect(out.whereType<StageAction>().single.side, 0);
      expect(out.whereType<StageEnd>().single.winner, 0);
    });
  });

  group('RealtimeSession', () {
    RealtimeSession session(FakeRealtimeServer server) => RealtimeSession(
      url: Uri.parse(testRealtimeUrl),
      connect: server.connect,
      auth: () async => const RealtimeAuth(idToken: 'tok', appCheckToken: 'ac'),
      snapshotId: 'snap_1',
      backoff: const [Duration(milliseconds: 10), Duration(milliseconds: 10)],
    );

    test('hello → queue → match → select with increasing seq', () async {
      final server = FakeRealtimeServer();
      final s = session(server);
      await s.start();
      expect(server.sent.single, {
        't': 'hello',
        'proto': 1,
        'idToken': 'tok',
        'appCheckToken': 'ac',
      });
      server.push({
        't': 'welcome',
        'proto': 1,
        'serverTimeMs': 1,
        'inMatch': false,
      });
      await pumpEventQueue();
      expect(server.sentTypes.last, 'queue');
      server.push({'t': 'queued', 'snapshotId': 'snap_1'});
      await pumpEventQueue();
      expect(s.phase, RealtimePhase.searching);
      server.push(matchMsg());
      await pumpEventQueue();
      expect(s.phase, RealtimePhase.battle);
      s
        ..select(1)
        ..select(0);
      expect(
        server.sent.where((m) => m['t'] == 'select').map((m) => m['seq']),
        [1, 2],
      );
      await s.close();
    });

    test('a drop during a match reconnects with lastSeq, invisibly', () async {
      final server = FakeRealtimeServer();
      final s = session(server);
      final seen = <int>[];
      s.onEvents = (m) => seen.add(m.seq);
      await s.start();
      server
        ..push({
          't': 'welcome',
          'proto': 1,
          'serverTimeMs': 1,
          'inMatch': false,
        })
        ..push(matchMsg())
        ..push(ev(1, 3, const []))
        ..push(ev(2, 4, const []));
      await pumpEventQueue();
      await server.last.drop();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(server.sockets.length, 2);
      final hello = server.sent.where((m) => m['t'] == 'hello').last;
      expect(hello['lastSeq'], 2);
      expect(s.phase, RealtimePhase.battle); // the child sees no change
      server
        ..push({'t': 'welcome', 'proto': 1, 'serverTimeMs': 1, 'inMatch': true})
        ..push(matchMsg(resumed: true))
        ..push(ev(2, 4, const [])) // replayed duplicate
        ..push(ev(3, 5, const []));
      await pumpEventQueue();
      expect(seen, [1, 2, 3]);
      await s.close();
    });

    test(
      'NOT_FOUND ends the session with its code; give-up offers solo',
      () async {
        final server = FakeRealtimeServer();
        final s = session(server);
        await s.start();
        server.push({'t': 'error', 'code': 'NOT_FOUND'});
        await pumpEventQueue();
        expect(s.phase, RealtimePhase.failed);
        expect(s.errorCode, 'NOT_FOUND');

        final down = FakeRealtimeServer()..failNextConnects = 10;
        final s2 = session(down);
        await s2.start();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(s2.phase, RealtimePhase.failed);
        expect(s2.error, contains('ひとりで'));
      },
    );
  });

  test('registerCharacter schema 2: source, canvas summary, moves', () {
    final d = StrokeDrawing(
      strokes: [
        Stroke(DrawTool.crayon, kCanvasColors[2], [10, 10, 100, 120, 200, 40]),
        Stroke(DrawTool.eraser, kCanvasColors[0], [50, 50, 60, 60]),
      ],
    );
    final summary = d.canvasSummary()!;
    expect(summary['v'], 1);
    expect(summary['strokes'], 1);
    expect(summary['points'], 3);
    expect(summary['colors'], [kCanvasColors[2]]);
    expect((summary['inkBox']! as List).length, 4);
    final c = CharacterV2.create(
      id: 'c_1',
      name: 'ねこまる',
      imagePath: '',
      imageHash: cutoutHash(testPng()),
      rawFeatures: const {'inkCoverage': 0.3},
      energy: 80,
      skill: 20,
      createdAt: DateTime.utc(2026),
      source: DrawingSource.canvas,
    ).copyWith(level: 5);
    final json = RegisterCharacterRequest(
      character: c,
      png: testPng(),
      canvas: summary,
    ).toJson();
    expect(json['schema'], 2);
    expect(json['source'], 'canvas');
    expect(json['canvas'], summary);
    expect(json['imageHash'], cutoutHash(testPng()));
    expect(json.containsKey('stats'), isFalse);
    for (final banned in ['bloomer', 'isBloomer', 'kid']) {
      expect(jsonEncode(json).contains('"$banned"'), isFalse);
    }
  });

  testWidgets(
    'register (name rejected → preset) → search → server battle → XP once',
    (tester) async {
      final server = FakeRealtimeServer();
      final backend = FakeBackend()
        ..registerOutcomes.addAll([
          const RegisterRejected(
            reason: 'NAME_NG',
            presetNames: ['もこたん', 'ぴかりん'],
          ),
          RegisterAccepted(
            snapshotId: 'snap_1',
            name: 'もこたん',
            displayName: 'げんきな うさぎ',
            imageHash: cutoutHash(testPng()),
          ),
        ]);
      final app = await pumpApp(
        tester,
        backend: backend,
        settings: setupDone.copyWith(consents: _online),
        characters: [testCharacter(level: 5)],
        overrides: [
          realtimeConnectorProvider.overrideWithValue(server.connect),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('home-online')));
      expect(find.byKey(const Key('lobby-badge')), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-c_1')));
      await tester.pump();
      await tester.pump();
      expect(find.text(registerRejectionMessage('NAME_NG')), findsOneWidget);
      await tester.tap(find.byKey(const Key('online-preset-もこたん')));
      await settle(tester);
      final req = backend.registered.last.toJson();
      expect((req['schema'], req['source']), (2, 'photo'));
      var c = (await app.characters.loadAll()).single;
      expect((c.name, c.onlineId), ('もこたん', 'snap_1'));
      // The server's seed hash is adopted.
      expect(c.imageHash, cutoutHash(testPng()));
      expect(app.settingsRepo.progress.onlineLevels['c_1'], 5);

      // WebSocket: hello with fresh tokens, then queue.
      expect(server.urls.single.toString(), testRealtimeUrl);
      expect(server.sent.first['idToken'], 'id-token');
      server.push({
        't': 'welcome',
        'proto': 1,
        'serverTimeMs': 1,
        'inMatch': false,
      });
      await settle(tester, frames: 2);
      expect(server.sentTypes, ['hello', 'queue']);
      server.push({'t': 'queued', 'snapshotId': 'snap_1'});
      await settle(tester, frames: 2);
      expect(find.byKey(const Key('online-waiting')), findsOneWidget);

      // Match against a ghost: same screen as PvP, then the stage.
      server.push(matchMsg());
      await settle(tester, frames: 30);
      expect(find.byType(MovePad), findsOneWidget);
      expect(find.textContaining('さかなくん'), findsOneWidget);
      expect(find.text('Lv50'), findsNWidgets(2));
      // さきどり goes to the server as `select`.
      await tester.tap(find.byKey(const Key('move-1')));
      await tester.pump();
      expect(server.sent.last, {'t': 'select', 'seq': 1, 'slot': 1});

      server
        ..push(
          ev(1, 10, const [
            {'tick': 10, 'type': 'ready', 'side': 0},
            {
              'tick': 10,
              'type': 'select',
              'side': 0,
              'slot': 1,
              'cast': 0,
              'auto': 0,
            },
            {'tick': 10, 'type': 'moveStart', 'side': 0, 'slot': 0},
            {
              'tick': 10,
              'type': 'hit',
              'side': 0,
              'target': 1,
              'n': 1,
              'amount': 900,
              'hp': 0,
              'crit': 1,
              'pct': 150,
            },
            {'tick': 10, 'type': 'faint', 'side': 1},
            {'tick': 10, 'type': 'end', 'winner': 0, 'reason': 'ko'},
          ]),
        )
        ..push({
          't': 'snap',
          'tick': 12,
          'a': sideView(),
          'b': sideView(hp: 0),
          'hash': 'abcd1234',
        })
        ..push(endMsg());
      await playBattle(tester);
      expect(find.text('かった！'), findsOneWidget);
      expect(find.text('けいけんち +150'), findsOneWidget);
      expect(find.byKey(const Key('result-badge')), findsOneWidget);
      expect(find.byKey(const Key('result-badge-up')), findsOneWidget);
      c = (await app.characters.loadAll()).single;
      expect((c.level, c.xp), (5, 150));
      expect(app.settingsRepo.progress.appliedMatchIds, ['m1']);
      expect(app.settingsRepo.progress.onlineBadge, 'rabbit');
      // The socket is closed once the result is in.
      expect(server.last.closed, isTrue);
      await unmount(tester);
    },
  );

  testWidgets('a v1 snapshot the server does not know: silent re-register', (
    tester,
  ) async {
    final server = FakeRealtimeServer();
    final backend = FakeBackend()
      ..registerOutcomes.add(
        const RegisterAccepted(snapshotId: 'snap_v2', name: 'ねこまる'),
      );
    final app = await pumpApp(
      tester,
      backend: backend,
      settings: setupDone.copyWith(consents: _online),
      progress: const GameProgress(onlineLevels: {'c_1': 6}),
      characters: [testCharacter(level: 6, onlineId: 'snap_old')],
      overrides: [realtimeConnectorProvider.overrideWithValue(server.connect)],
    );
    await tapVisible(tester, find.byKey(const Key('home-online')));
    await tester.tap(find.byKey(const Key('select-c_1')));
    await settle(tester, frames: 3);
    expect(backend.registered, isEmpty); // known snapshot: no review
    server.push({
      't': 'welcome',
      'proto': 1,
      'serverTimeMs': 1,
      'inMatch': false,
    });
    await settle(tester, frames: 2);
    expect(server.sent.last, {'t': 'queue', 'snapshotId': 'snap_old'});
    server.push({'t': 'error', 'code': 'NOT_FOUND'});
    await settle(tester, frames: 10);
    // Registered again via schema 2, then queued with the new snapshot.
    expect(backend.registered.single.toJson()['schema'], 2);
    expect((await app.characters.loadAll()).single.onlineId, 'snap_v2');
    expect(find.byKey(const Key('online-message')), findsNothing);
    server.push({
      't': 'welcome',
      'proto': 1,
      'serverTimeMs': 1,
      'inMatch': false,
    });
    await settle(tester, frames: 2);
    expect(server.sent.last, {'t': 'queue', 'snapshotId': 'snap_v2'});
    await unmount(tester);
  });

  testWidgets('an image rejection shows its kid message and no presets', (
    tester,
  ) async {
    final server = FakeRealtimeServer();
    final backend = FakeBackend()
      ..registerOutcomes.add(
        const RegisterRejected(reason: 'IMAGE_REAL_PERSON'),
      );
    await pumpApp(
      tester,
      backend: backend,
      settings: setupDone.copyWith(consents: _online),
      characters: [testCharacter(level: 6)],
      overrides: [realtimeConnectorProvider.overrideWithValue(server.connect)],
    );
    await tapVisible(tester, find.byKey(const Key('home-online')));
    await tester.tap(find.byKey(const Key('select-c_1')));
    await tester.pump();
    await tester.pump();
    expect(find.text('ひとの しゃしんや かおは つかえないよ'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(server.sockets, isEmpty); // never connected
    await unmount(tester);
  });

  testWidgets('Lv4 characters are greyed out; no server URL = じゅんびちゅう', (
    tester,
  ) async {
    await pumpApp(
      tester,
      backend: FakeBackend(),
      settings: setupDone.copyWith(consents: _online),
      characters: [testCharacter(level: 4)],
    );
    await tapVisible(tester, find.byKey(const Key('home-online')));
    expect(find.text('Lv5 に なったら あそべるよ'), findsOneWidget);
    await unmount(tester);
    await pumpApp(
      tester,
      backend: FakeBackend(),
      realtimeUrl: '',
      settings: setupDone.copyWith(consents: _online),
      characters: [testCharacter(level: 6)],
    );
    expect(find.text('じゅんびちゅう'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('leaving the search closes the socket (cancel first)', (
    tester,
  ) async {
    final server = FakeRealtimeServer();
    await pumpApp(
      tester,
      backend: FakeBackend(),
      settings: setupDone.copyWith(consents: _online),
      progress: const GameProgress(onlineLevels: {'c_1': 6}),
      characters: [testCharacter(level: 6, onlineId: 'snap_9')],
      overrides: [realtimeConnectorProvider.overrideWithValue(server.connect)],
    );
    await tapVisible(tester, find.byKey(const Key('home-online')));
    await tester.tap(find.byKey(const Key('select-c_1')));
    await settle(tester, frames: 3);
    server
      ..push({'t': 'welcome', 'proto': 1, 'serverTimeMs': 1, 'inMatch': false})
      ..push({'t': 'queued', 'snapshotId': 'snap_9'});
    await settle(tester, frames: 3);
    await tester.tap(find.byKey(const Key('online-cancel')));
    await settle(tester, frames: 5);
    expect(server.sentTypes.last, 'cancel');
    expect(server.last.closed, isTrue);
    await unmount(tester);
  });
}
