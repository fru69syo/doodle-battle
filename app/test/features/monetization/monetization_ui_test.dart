import 'dart:io';

import 'package:doodle_battle/core/config/app_config.dart';
import 'package:doodle_battle/core/providers.dart';
import 'package:doodle_battle/core/router/app_router.dart';
import 'package:doodle_battle/core/router/routes.dart';
import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/app_state.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/data/settings_repository.dart';
import 'package:doodle_battle/features/monetization/monetization_service.dart';
import 'package:doodle_battle/features/monetization/monetization_sync.dart';
import 'package:doodle_battle/features/monetization/rewarded_ad_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

AppSettings withConsents(ParentConsents c, {Set<String>? entitlements}) =>
    setupDone.copyWith(consents: c, entitlements: entitlements);

/// Just the result-screen button, with fakes.
Future<(InMemorySettingsRepository, int Function())> pumpAdButton(
  WidgetTester tester, {
  required FakeMonetization monetization,
  AppSettings? settings,
  GameProgress progress = const GameProgress(),
}) async {
  final repo = InMemorySettingsRepository(
    settings: settings ?? withConsents(const ParentConsents(ads: true)),
    progress: progress,
  );
  var rewards = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        monetizationServiceProvider.overrideWithValue(monetization),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 9, 10)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: RewardedAdButton(onRewarded: () async => rewards++),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, () => rewards);
}

void main() {
  group('rewarded ad button', () {
    testWidgets('hidden unless ads are allowed (and no こうこくなしパス)', (
      tester,
    ) async {
      final m = FakeMonetization();
      await pumpAdButton(tester, monetization: m, settings: setupDone);
      expect(find.byKey(const Key('ad-double-xp')), findsNothing);
      expect(find.byKey(const Key('ad-cap')), findsNothing);
    });

    testWidgets('a watched ad counts towards the daily cap', (tester) async {
      final m = FakeMonetization();
      final (repo, rewards) = await pumpAdButton(tester, monetization: m);
      expect(m.preloads, 1); // retried when the result screen opens
      expect(find.text('きょうは あと 3 かい'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ad-double-xp')));
      await tester.pumpAndSettle();
      expect(find.text(adNoticeText), findsOneWidget);
      await tester.tap(find.byKey(const Key('kid-ask-yes')));
      await tester.pumpAndSettle();
      expect(m.adsShown, 1);
      expect(rewards(), 1);
      expect(repo.progress.adBoostDate, '2026-10-09');
      expect(repo.progress.adBoostsToday, 1);
      expect(find.byKey(const Key('ad-done')), findsOneWidget);
    });

    testWidgets('cap reached: no button, friendly text', (tester) async {
      final m = FakeMonetization();
      await pumpAdButton(
        tester,
        monetization: m,
        progress: const GameProgress(
          adBoostDate: '2026-10-09',
          adBoostsToday: dailyAdBoostCap,
        ),
      );
      expect(find.byKey(const Key('ad-double-xp')), findsNothing);
      expect(find.text(adCapText), findsOneWidget);
    });

    testWidgets('yesterday’s boosts do not count today', (tester) async {
      await pumpAdButton(
        tester,
        monetization: FakeMonetization(),
        progress: const GameProgress(
          adBoostDate: '2026-10-08',
          adBoostsToday: dailyAdBoostCap,
        ),
      );
      expect(find.text('きょうは あと 3 かい'), findsOneWidget);
    });

    testWidgets('load failure hides the button with a friendly text', (
      tester,
    ) async {
      final m = FakeMonetization(adState: AdState.unavailable);
      await pumpAdButton(tester, monetization: m);
      expect(find.byKey(const Key('ad-double-xp')), findsNothing);
      expect(find.text(adUnavailableText), findsOneWidget);
      m.setAdState(AdState.ready);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ad-double-xp')), findsOneWidget);
    });

    testWidgets('while loading the button is disabled', (tester) async {
      final m = FakeMonetization(adState: AdState.loading);
      await pumpAdButton(tester, monetization: m);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('ad-double-xp')),
      );
      expect(button.enabled, isFalse);
      expect(find.text('どうがを じゅんび しているよ…'), findsOneWidget);
    });

    testWidgets('closing the ad early gives nothing and is not counted', (
      tester,
    ) async {
      final m = FakeMonetization(adResult: RewardedAdResult.notRewarded);
      final (repo, rewards) = await pumpAdButton(tester, monetization: m);
      await tester.tap(find.byKey(const Key('ad-double-xp')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kid-ask-yes')));
      await tester.pumpAndSettle();
      expect(rewards(), 0);
      expect(repo.progress.adBoostsToday, 0);
    });

    testWidgets('こうこくなしパス: bonus without an ad, same daily cap', (
      tester,
    ) async {
      final m = FakeMonetization();
      final (repo, rewards) = await pumpAdButton(
        tester,
        monetization: m,
        // Ads allowed too: the pass still hides every ad entry point.
        settings: withConsents(
          const ParentConsents(ads: true),
          entitlements: {Product.noAdsPass.id},
        ),
        progress: const GameProgress(
          adBoostDate: '2026-10-09',
          adBoostsToday: dailyAdBoostCap - 1,
        ),
      );
      expect(m.preloads, 0, reason: 'no ad is loaded with the pass');
      expect(find.text('こうこくなしパスで けいけんち 2ばい'), findsOneWidget);
      expect(find.text('きょうは あと 1 かい'), findsOneWidget);
      expect(find.textContaining('どうが'), findsNothing);
      await tester.tap(find.byKey(const Key('ad-double-xp')));
      await tester.pumpAndSettle();
      expect(find.text(adNoticeText), findsNothing);
      expect(m.adsShown, 0);
      expect(rewards(), 1);
      expect(repo.progress.adBoostsOn('2026-10-09'), dailyAdBoostCap);
      expect(find.byKey(const Key('ad-done')), findsOneWidget);
    });

    testWidgets('こうこくなしパス: cap reached, no button, no ad', (tester) async {
      final m = FakeMonetization();
      final (_, rewards) = await pumpAdButton(
        tester,
        monetization: m,
        settings: withConsents(
          const ParentConsents(ads: true),
          entitlements: {Product.noAdsPass.id},
        ),
        progress: const GameProgress(
          adBoostDate: '2026-10-09',
          adBoostsToday: dailyAdBoostCap,
        ),
      );
      expect(find.byKey(const Key('ad-double-xp')), findsNothing);
      expect(find.text(passCapText), findsOneWidget);
      expect(find.text(adCapText), findsNothing);
      expect(m.adsShown, 0);
      expect(rewards(), 0);
    });

    test('こうこくなしパス product text', () {
      expect(Product.noAdsPass.id, 'no_ads_pass');
      expect(Product.noAdsPass.title, 'こうこくなしパス');
      expect(
        Product.noAdsPass.description,
        'こうこくを みないで けいけんち 2ばい（1にち ${dailyAdBoostCap}かいまで）',
      );
    });

    test('adBoostsLeft', () {
      expect(adBoostsLeft(cap: 3, usedToday: 0), 3);
      expect(adBoostsLeft(cap: 3, usedToday: 2), 1);
      expect(adBoostsLeft(cap: 3, usedToday: 5), 0);
    });

    test('ad boosts persist per local day', () {
      const p = GameProgress();
      final once = p.withAdBoost('2026-10-09');
      final twice = once.withAdBoost('2026-10-09');
      expect(twice.adBoostsOn('2026-10-09'), 2);
      expect(twice.withAdBoost('2026-10-10').adBoostsOn('2026-10-10'), 1);
      final back = GameProgress.fromJson(twice.toJson());
      expect(back.adBoostsOn('2026-10-09'), 2);
      expect(back.adBoostsOn('2026-10-10'), 0);
    });
  });

  group('settings ↔ service sync', () {
    testWidgets('ads consent is mirrored; SDK stays off by default', (
      tester,
    ) async {
      final m = FakeMonetization();
      await pumpApp(tester, monetization: m);
      expect(m.adsAllowedCalls, [false]);
      await tapVisible(tester, find.byKey(const Key('home-parent')));
      await tapVisible(tester, find.byKey(const Key('consent-ads')));
      expect(m.adsAllowedCalls.last, isTrue);
      await tapVisible(tester, find.byKey(const Key('consent-ads')));
      expect(m.adsAllowedCalls.last, isFalse);
    });

    testWidgets('こうこくなしパス keeps the ads SDK off and explains the switch', (
      tester,
    ) async {
      final m = FakeMonetization();
      await pumpApp(
        tester,
        monetization: m,
        settings: withConsents(
          const ParentConsents(ads: true),
          entitlements: {Product.noAdsPass.id},
        ),
      );
      expect(m.adsAllowedCalls, everyElement(isFalse));
      await tapVisible(tester, find.byKey(const Key('home-parent')));
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('consent-ads')),
      );
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
      expect(find.textContaining('こうこくなしパスを購入済み'), findsOneWidget);
      // A refund (restore without the pass) turns the consented ads back on.
      m.emitOwned({});
      await tester.pumpAndSettle();
      expect(m.adsAllowedCalls.last, isTrue);
    });

    testWidgets('starts with the cached entitlements', (tester) async {
      final m = FakeMonetization();
      await pumpApp(
        tester,
        monetization: m,
        settings: withConsents(
          const ParentConsents(),
          entitlements: {'slots_24', 'no_longer_sold'},
        ),
      );
      expect(m.startedWith, {Product.slots24});
    });

    testWidgets('store entitlements are persisted (collection 12 → 36)', (
      tester,
    ) async {
      final m = FakeMonetization();
      final app = await pumpApp(tester, monetization: m);
      expect(app.container.read(collectionLimitProvider), 12);
      m.emitOwned({Product.slots24, Product.noAdsPass});
      await tester.pumpAndSettle();
      expect(app.settingsRepo.settings.entitlements, {
        'slots_24',
        'no_ads_pass',
      });
      expect(app.container.read(collectionLimitProvider), 36);
      // A refund (restore without the product) removes it again.
      m.emitOwned({Product.noAdsPass});
      await tester.pumpAndSettle();
      expect(app.settingsRepo.settings.entitlements, {'no_ads_pass'});
      expect(app.container.read(collectionLimitProvider), 12);
    });

    testWidgets('crash reports: unavailable without Firebase', (tester) async {
      final crash = FakeCrashReporter(isAvailable: false);
      await pumpApp(tester, crash: crash);
      await tapVisible(tester, find.byKey(const Key('home-parent')));
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('consent-crashReports')),
      );
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
      expect(crash.calls, [false]);
    });

    testWidgets('crash reports: off by default, opt-in, opt-out', (
      tester,
    ) async {
      final crash = FakeCrashReporter();
      final app = await pumpApp(tester, crash: crash);
      expect(crash.calls, [false]);
      await tapVisible(tester, find.byKey(const Key('home-parent')));
      await tapVisible(tester, find.byKey(const Key('consent-crashReports')));
      expect(crash.calls.last, isTrue);
      expect(app.settingsRepo.settings.consents.crashReports, isTrue);
      await tapVisible(tester, find.byKey(const Key('consent-crashReports')));
      expect(crash.calls.last, isFalse);
    });

    testWidgets('delete all data turns crash reports off and restores '
        'purchases into the cache', (tester) async {
      final crash = FakeCrashReporter();
      final m = FakeMonetization();
      await pumpApp(
        tester,
        crash: crash,
        monetization: m,
        settings: withConsents(const ParentConsents(crashReports: true)),
      );
      expect(crash.calls, [true]);
      await tapVisible(tester, find.byKey(const Key('home-parent')));
      await tapVisible(tester, find.byKey(const Key('delete-all')));
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();
      expect(crash.calls.last, isFalse);
      expect(m.restores, 1);
    });
  });

  group('shop', () {
    Future<TestApp> openShop(WidgetTester tester, FakeMonetization m) async {
      final app = await pumpApp(
        tester,
        monetization: m,
        settings: withConsents(const ParentConsents(purchases: true)),
      );
      await tapVisible(tester, find.byKey(const Key('home-parent')));
      await tester.scrollUntilVisible(
        find.byKey(const Key('shop-restore')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      return app;
    }

    testWidgets('shows store prices; refreshes the store once', (tester) async {
      final m = FakeMonetization();
      await openShop(tester, m);
      expect(m.refreshes, 1);
      expect(find.textContaining('価格: ￥250'), findsOneWidget);
      expect(find.textContaining('価格: ￥320'), findsOneWidget);
      expect(find.textContaining('定期購入ではありません'), findsWidgets);
    });

    testWidgets('no price → buying is disabled', (tester) async {
      final m = FakeMonetization(storeAvailable: false);
      await openShop(tester, m);
      expect(find.byKey(const Key('shop-unavailable')), findsOneWidget);
      final buy = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('buy-no_ads_pass')),
      );
      expect(buy.enabled, isFalse);
    });

    testWidgets('cancelling the confirmation buys nothing', (tester) async {
      final m = FakeMonetization();
      final app = await openShop(tester, m);
      await tapVisible(tester, find.byKey(const Key('buy-frame_pack_1')));
      expect((app.gate as FakeGate).calls, 2);
      expect(find.text('￥160'), findsOneWidget);
      await tester.tap(find.byKey(const Key('purchase-cancel')));
      await tester.pumpAndSettle();
      expect(m.purchases, isEmpty);
    });

    testWidgets('a purchase shows as 購入済み; pending is explained', (
      tester,
    ) async {
      final m = FakeMonetization();
      await openShop(tester, m);
      await tapVisible(tester, find.byKey(const Key('buy-no_ads_pass')));
      await tester.tap(find.byKey(const Key('purchase-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('購入しました。ありがとうございます。'), findsOneWidget);
      expect(find.byKey(const Key('buy-no_ads_pass')), findsNothing);
      m.purchaseResult = PurchaseResult.pending;
      await tapVisible(tester, find.byKey(const Key('buy-slots_24')));
      await tester.tap(find.byKey(const Key('purchase-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('支払いの手続き中です'), findsOneWidget);
    });

    testWidgets('restore asks the store again', (tester) async {
      final m = FakeMonetization();
      await openShop(tester, m);
      await tapVisible(tester, find.byKey(const Key('shop-restore')));
      expect(m.restores, 1);
      expect(find.text('購入状況を更新しました。'), findsOneWidget);
    });
  });

  group('フレームパック', () {
    testWidgets('frame picker only with the pack; frame is saved and drawn', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        characters: [testCharacter()],
        settings: withConsents(
          const ParentConsents(),
          entitlements: {Product.framePack.id},
        ),
      );
      app.container.read(routerProvider).push(Routes.character('c_1'));
      await tester.pumpAndSettle();
      Future<void> toTop() async {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
      }

      await tapVisible(tester, find.byKey(const Key('frame-hoshi')));
      expect((await app.characters.loadAll()).single.cardFrame, 'hoshi');
      await toTop();
      expect(find.byKey(const Key('card-frame-hoshi')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('frame-niji')));
      await toTop();
      expect(find.byKey(const Key('card-frame-niji')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('frame-none')));
      expect((await app.characters.loadAll()).single.cardFrame, isNull);
      await toTop();
      expect(find.byKey(const Key('card-frame-niji')), findsNothing);
    });

    testWidgets('without the pack: no picker, saved frames are not drawn', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        characters: [testCharacter().copyWith(cardFrame: () => 'hana')],
      );
      app.container.read(routerProvider).push(Routes.character('c_1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('frame-picker')), findsNothing);
      expect(find.byKey(const Key('card-frame-hana')), findsNothing);
    });

    testWidgets('ずかん cards draw the frame', (tester) async {
      await pumpApp(
        tester,
        characters: [testCharacter().copyWith(cardFrame: () => 'hana')],
        settings: withConsents(
          const ParentConsents(),
          entitlements: {Product.framePack.id},
        ),
      );
      await tapVisible(tester, find.byKey(const Key('home-zukan')));
      expect(find.byKey(const Key('card-frame-hana')), findsOneWidget);
    });
  });

  group('policy pages', () {
    testWidgets('open from おうちのひと (behind the gate)', (tester) async {
      final app = await pumpApp(tester);
      await tapVisible(tester, find.byKey(const Key('home-parent')));
      expect((app.gate as FakeGate).calls, 1);
      await tapVisible(tester, find.byKey(const Key('policy-privacy')));
      await tapVisible(tester, find.byKey(const Key('policy-deletion')));
      expect(app.openedUrls, [PolicyPage.privacy.uri, PolicyPage.deletion.uri]);
      expect(PolicyPage.privacy.uri.toString(), startsWith('https://'));
    });

    test('every page the app opens exists in site/', () {
      for (final p in PolicyPage.values) {
        expect(File('../site/${p.path}').existsSync(), isTrue, reason: p.path);
      }
    });

    test('all pages live under one base URL', () {
      for (final p in PolicyPage.values) {
        expect(p.uri.toString(), startsWith(policySiteBaseUrl));
        expect(p.uri.isAbsolute, isTrue);
      }
    });
  });
}
