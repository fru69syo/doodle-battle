import 'package:doodle_battle/core/router/app_router.dart';
import 'package:doodle_battle/core/router/routes.dart';
import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/features/monetization/monetization_service.dart';
import 'package:doodle_battle/features/monetization/shop_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doodle_battle/data/game_progress.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

AppSettings withConsents(ParentConsents c) => setupDone.copyWith(consents: c);

Future<void> openParent(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('home-parent')));
}

void main() {
  group('router redirect', () {
    test('splash while loading, setup first, parent area needs the gate', () {
      String? r(
        String loc, {
        bool needsSetup = false,
        bool unlocked = false,
        AsyncValue<Object?> s = const AsyncData(1),
      }) => redirectFor(
        location: loc,
        settingsState: s,
        needsSetup: needsSetup,
        parentUnlocked: unlocked,
      );
      expect(r('/', s: const AsyncLoading()), Routes.splash);
      expect(r('/zukan', needsSetup: true), Routes.setup);
      expect(r(Routes.setup, needsSetup: true), isNull);
      expect(r(Routes.setup), Routes.home);
      expect(r(Routes.parent), Routes.home);
      expect(r(Routes.parent, unlocked: true), isNull);
      expect(r('/zukan'), isNull);
    });
  });

  testWidgets('first run shows the parent setup until it is completed', (
    tester,
  ) async {
    final app = await pumpApp(tester, settings: const AppSettings());
    expect(find.byKey(const Key('setup-start')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('setup-start')));
    expect((app.gate as FakeGate).calls, 1);
    // Server features (and Crashlytics) are disabled while Firebase is not
    // configured.
    expect(find.textContaining('現在準備中'), findsNWidgets(3));
    await tapVisible(tester, find.byKey(const Key('consent-ads')));
    await tapVisible(tester, find.byKey(const Key('setup-finish')));
    expect(find.byKey(const Key('home-draw')), findsOneWidget);
    final s = app.settingsRepo.settings;
    expect(s.setupCompleted, isTrue);
    expect(s.policyVersion, currentPolicyVersion);
    expect(s.consents, const ParentConsents(ads: true));
  });

  testWidgets('a failed gate keeps the child in the setup', (tester) async {
    await pumpApp(
      tester,
      settings: const AppSettings(),
      gate: FakeGate(pass: false),
    );
    await tapVisible(tester, find.byKey(const Key('setup-start')));
    expect(find.byKey(const Key('setup-finish')), findsNothing);
  });

  testWidgets('setup with a server writes consent to the backend', (
    tester,
  ) async {
    final backend = FakeBackend();
    await pumpApp(tester, settings: const AppSettings(), backend: backend);
    await tapVisible(tester, find.byKey(const Key('setup-start')));
    await tapVisible(tester, find.byKey(const Key('consent-online')));
    await tapVisible(tester, find.byKey(const Key('setup-finish')));
    expect(backend.lastConsent, const ParentConsents(online: true));
  });

  testWidgets('offline-only families never create a server account', (
    tester,
  ) async {
    final backend = FakeBackend();
    await pumpApp(tester, settings: const AppSettings(), backend: backend);
    await tapVisible(tester, find.byKey(const Key('setup-start')));
    await tapVisible(tester, find.byKey(const Key('setup-finish')));
    expect(backend.calls, isEmpty);
  });

  group('server consent sync (no backend contact while both are off)', () {
    testWidgets('ads / purchases only: never contacts the backend', (
      tester,
    ) async {
      final backend = FakeBackend();
      final app = await pumpApp(tester, backend: backend);
      await openParent(tester);
      await tapVisible(tester, find.byKey(const Key('consent-ads')));
      await tapVisible(tester, find.byKey(const Key('consent-purchases')));
      expect(backend.calls, isEmpty);
      expect(app.settingsRepo.settings.syncedConsent, isNull);
    });

    testWidgets(
      'turning online on syncs; off again withdraws once, then silence',
      (tester) async {
        final backend = FakeBackend();
        final app = await pumpApp(tester, backend: backend);
        await openParent(tester);
        await tapVisible(tester, find.byKey(const Key('consent-online')));
        expect(backend.calls, ['syncConsent']);
        expect(app.settingsRepo.settings.syncedConsent?.online, isTrue);
        await tapVisible(tester, find.byKey(const Key('consent-online')));
        expect(backend.calls, ['syncConsent', 'syncConsent']);
        expect(backend.lastConsent?.online, isFalse);
        // Further non-server changes do not call the backend.
        await tapVisible(tester, find.byKey(const Key('consent-ads')));
        await tapVisible(tester, find.byKey(const Key('playtime-30')));
        expect(backend.calls, ['syncConsent', 'syncConsent']);
      },
    );

    testWidgets('an already synced consent is not re-sent after a restart', (
      tester,
    ) async {
      final backend = FakeBackend()..uid = 'uid-1';
      await pumpApp(
        tester,
        backend: backend,
        settings: setupDone.copyWith(
          consents: const ParentConsents(cloudJudge: true),
          syncedConsent: () => const ServerConsent(
            cloudJudge: true,
            online: false,
            policyVersion: currentPolicyVersion,
          ),
        ),
      );
      await tapVisible(tester, find.byKey(const Key('home-draw')));
      await tapVisible(tester, find.byKey(const Key('draw-gallery')));
      expect(backend.calls, ['judgeDrawing']);
    });
  });

  group('online gating', () {
    testWidgets('hidden unless the parent allowed it', (tester) async {
      await pumpApp(tester, backend: FakeBackend());
      expect(find.byKey(const Key('home-online')), findsNothing);
    });

    testWidgets('じゅんびちゅう when Firebase is not configured', (tester) async {
      await pumpApp(
        tester,
        settings: withConsents(const ParentConsents(online: true)),
      );
      expect(find.byKey(const Key('home-online')), findsOneWidget);
      expect(find.text('じゅんびちゅう'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-online')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-draw')), findsOneWidget); // disabled
    });

    testWidgets('lobby lists only Lv5+ characters', (tester) async {
      await pumpApp(
        tester,
        backend: FakeBackend(),
        settings: withConsents(const ParentConsents(online: true)),
        characters: [
          testCharacter(id: 'c_1', level: 4),
          testCharacter(id: 'c_2', name: 'つよまる', level: 5),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('home-online')));
      expect(find.text('Lv5 に なったら あそべるよ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-c_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('online-registering')), findsNothing);
    });

    testWidgets('direct navigation to the lobby is refused without consent', (
      tester,
    ) async {
      final app = await pumpApp(tester, backend: FakeBackend());
      app.container.read(routerProvider).push(Routes.online);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('online-not-allowed')), findsOneWidget);
    });
  });

  group('parent area', () {
    testWidgets('needs the gate; route is refused otherwise', (tester) async {
      final gate = FakeGate(pass: false);
      final app = await pumpApp(tester, gate: gate);
      await openParent(tester);
      expect(find.text('許可の設定'), findsNothing);
      app.container.read(routerProvider).push(Routes.parent);
      await tester.pumpAndSettle();
      expect(find.text('許可の設定'), findsNothing);
      gate.pass = true;
      await openParent(tester);
      expect(find.text('許可の設定'), findsOneWidget);
    });

    testWidgets('toggles consents and the play-time guideline', (tester) async {
      final app = await pumpApp(tester, backend: FakeBackend());
      await openParent(tester);
      await tapVisible(tester, find.byKey(const Key('consent-cloudJudge')));
      await tapVisible(tester, find.byKey(const Key('playtime-60')));
      expect(app.settingsRepo.settings.consents.cloudJudge, isTrue);
      expect(app.settingsRepo.settings.playTimeMinutes, 60);
      expect(app.backend.lastConsent?.cloudJudge, isTrue);
    });

    testWidgets('shop hidden unless purchases are allowed', (tester) async {
      await pumpApp(tester);
      await openParent(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('shop-disabled')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('shop')), findsNothing);
    });

    testWidgets('shop shows the notice and gates every purchase', (
      tester,
    ) async {
      final gate = FakeGate();
      final store = FakeMonetization();
      await pumpApp(
        tester,
        gate: gate,
        monetization: store,
        settings: withConsents(const ParentConsents(purchases: true)),
      );
      await openParent(tester);
      expect(gate.calls, 1);
      await tester.scrollUntilVisible(
        find.byKey(const Key('shop-notice')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(purchaseNoticeText), findsOneWidget);
      gate.pass = false;
      await tapVisible(tester, find.byKey(const Key('buy-slots_24')));
      expect(gate.calls, 2);
      expect(store.purchases, isEmpty);
      gate.pass = true;
      await tapVisible(tester, find.byKey(const Key('buy-slots_24')));
      expect(gate.calls, 3);
      // Confirmation with the store price and the notice; nothing bought yet.
      expect(find.byKey(const Key('purchase-price')), findsOneWidget);
      expect(find.text('￥250'), findsOneWidget);
      expect(find.byKey(const Key('purchase-notice')), findsOneWidget);
      expect(store.purchases, isEmpty);
      await tester.tap(find.byKey(const Key('purchase-confirm')));
      await tester.pumpAndSettle();
      expect(store.purchases, [Product.slots24]);
    });

    testWidgets('support id is shown once signed in', (tester) async {
      await pumpApp(tester, backend: FakeBackend()..uid = 'uid-9');
      await openParent(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('delete-all')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('uid-9'), findsOneWidget);
    });

    testWidgets('delete all data: server first, then local, back to setup', (
      tester,
    ) async {
      final backend = FakeBackend()..uid = 'uid-9';
      final app = await pumpApp(
        tester,
        backend: backend,
        characters: [testCharacter()],
      );
      await openParent(tester);
      await tapVisible(tester, find.byKey(const Key('delete-all')));
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();
      expect(backend.calls, contains('deleteMyData'));
      expect(await app.characters.loadAll(), isEmpty);
      expect(app.settingsRepo.settings.setupCompleted, isFalse);
      expect(find.byKey(const Key('setup-start')), findsOneWidget);
    });

    testWidgets('server deletion failure keeps local data', (tester) async {
      final backend = FakeBackend()..deleteFails = true;
      final app = await pumpApp(
        tester,
        backend: backend,
        characters: [testCharacter()],
      );
      await openParent(tester);
      await tapVisible(tester, find.byKey(const Key('delete-all')));
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('削除できませんでした'), findsOneWidget);
      expect(await app.characters.loadAll(), hasLength(1));
    });

    testWidgets('licences include the bundled font', (tester) async {
      await pumpApp(tester);
      await openParent(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('licenses')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('uid-9'), findsNothing); // no account yet
      Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('licenses'))),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('licenses')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LicensePage), findsOneWidget);
    });
  });

  testWidgets('play-time banner after the guideline', (tester) async {
    await pumpApp(
      tester,
      settings: setupDone.copyWith(playTimeMinutes: () => 30),
      progress: const GameProgress(
        playDate: '2026-10-09',
        playSecondsToday: 31 * 60,
      ),
    );
    expect(find.byKey(const Key('playtime-banner')), findsOneWidget);
  });

  testWidgets('no banner before the guideline', (tester) async {
    await pumpApp(
      tester,
      settings: setupDone.copyWith(playTimeMinutes: () => 30),
      progress: const GameProgress(
        playDate: '2026-10-09',
        playSecondsToday: 10 * 60,
      ),
    );
    expect(find.byKey(const Key('playtime-banner')), findsNothing);
  });
}
