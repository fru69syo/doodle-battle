import 'dart:async';

import 'package:doodle_battle/features/monetization/admob_gateway.dart';
import 'package:doodle_battle/features/monetization/app_monetization_service.dart';
import 'package:doodle_battle/features/monetization/gateways.dart';
import 'package:doodle_battle/features/monetization/monetization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class FakeAd implements LoadedRewardedAd {
  FakeAd({this.earn = true});
  final bool earn;
  bool disposed = false;
  int shown = 0;

  @override
  Future<bool> show() async {
    shown++;
    return earn;
  }

  @override
  void dispose() => disposed = true;
}

class FakeAdsGateway implements RewardedAdsGateway {
  int inits = 0;
  final loads = <String>[];

  /// Next results of [load]; null = no fill. Empty list = a fresh ad.
  final results = <FakeAd?>[];
  final loaded = <FakeAd>[];
  Completer<void>? holdLoad;

  @override
  Future<void> initialize() async => inits++;

  @override
  Future<LoadedRewardedAd?> load(String adUnitId) async {
    loads.add(adUnitId);
    if (holdLoad != null) await holdLoad!.future;
    final ad = results.isEmpty ? FakeAd() : results.removeAt(0);
    if (ad != null) loaded.add(ad);
    return ad;
  }
}

class FakeStoreGateway implements StoreGateway {
  bool available = true;
  bool launch = true;
  Object? queryError;
  Object? ownedError;
  Object? completeError;
  List<StorePurchase> ownedList = [];
  final bought = <String>[];
  final completed = <String>[];
  final updates = StreamController<List<StorePurchase>>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async {
    if (queryError != null) throw queryError!;
    return [
      if (ids.contains('slots_24'))
        const StoreProduct(id: 'slots_24', price: '￥250'),
      if (ids.contains('frame_pack_1'))
        const StoreProduct(id: 'frame_pack_1', price: '￥160'),
      if (ids.contains('no_ads_pass'))
        const StoreProduct(id: 'no_ads_pass', price: '￥320'),
      const StoreProduct(id: 'unknown_item', price: '￥1'),
    ];
  }

  @override
  Future<bool> buyNonConsumable(StoreProduct product) async {
    bought.add(product.id);
    return launch;
  }

  @override
  Stream<List<StorePurchase>> get purchaseUpdates => updates.stream;

  @override
  Future<void> completePurchase(StorePurchase purchase) async {
    if (completeError != null) throw completeError!;
    completed.add(purchase.productId);
  }

  @override
  Future<List<StorePurchase>> queryOwned() async {
    if (ownedError != null) throw ownedError!;
    return ownedList;
  }
}

StorePurchase sp(
  String id,
  StorePurchaseStatus status, {
  bool needsCompletion = false,
}) => StorePurchase(
  productId: id,
  status: status,
  needsCompletion: needsCompletion,
);

void main() {
  late FakeAdsGateway ads;
  late FakeStoreGateway store;
  late DateTime now;
  late AppMonetizationService service;
  late List<Set<Product>> emitted;

  setUp(() {
    ads = FakeAdsGateway();
    store = FakeStoreGateway();
    now = DateTime(2026, 10, 9, 10);
    service = AppMonetizationService(
      ads: ads,
      store: store,
      rewardedAdUnitId: 'unit-1',
      clock: () => now,
      purchaseTimeout: const Duration(seconds: 5),
    );
    emitted = [];
    service.entitlements.listen(emitted.add);
  });

  tearDown(() => service.dispose());

  group('ads: consent gating and lazy initialisation', () {
    test('nothing touches the SDK until the parent allows ads', () async {
      await service.preloadRewardedAd();
      expect(await service.showRewardedAd(), RewardedAdResult.unavailable);
      await service.setAdsAllowed(false);
      expect(ads.inits, 0);
      expect(ads.loads, isEmpty);
      expect(service.adState, AdState.off);
    });

    test('allowing ads initialises once and preloads one ad', () async {
      await service.setAdsAllowed(true);
      expect(ads.inits, 1);
      expect(ads.loads, ['unit-1']);
      expect(service.adState, AdState.ready);
      expect(service.rewardedAdReady, isTrue);
      await service.preloadRewardedAd(); // already loaded
      expect(ads.loads, hasLength(1));
    });

    test('show: rewarded, then the next ad is preloaded', () async {
      await service.setAdsAllowed(true);
      expect(await service.showRewardedAd(), RewardedAdResult.rewarded);
      await pumpEventQueue();
      expect(ads.loaded.first.shown, 1);
      expect(ads.loaded.first.disposed, isTrue);
      expect(ads.loads, hasLength(2));
      expect(ads.inits, 1);
      expect(service.adState, AdState.ready);
    });

    test('closing early is not rewarded', () async {
      ads.results.add(FakeAd(earn: false));
      await service.setAdsAllowed(true);
      expect(await service.showRewardedAd(), RewardedAdResult.notRewarded);
    });

    test('revoking consent drops the loaded ad and stops loading', () async {
      await service.setAdsAllowed(true);
      final ad = ads.loaded.single;
      await service.setAdsAllowed(false);
      expect(ad.disposed, isTrue);
      expect(service.adState, AdState.off);
      expect(await service.showRewardedAd(), RewardedAdResult.unavailable);
      await service.preloadRewardedAd();
      expect(ads.loads, hasLength(1));
    });

    test('consent revoked while loading: the late ad is discarded', () async {
      ads.holdLoad = Completer<void>();
      final loading = service.setAdsAllowed(true);
      await pumpEventQueue();
      expect(service.adState, AdState.loading);
      await service.setAdsAllowed(false);
      ads.holdLoad!.complete();
      await loading;
      expect(ads.loaded.single.disposed, isTrue);
      expect(service.adState, AdState.off);
    });

    test(
      'load failure → unavailable, retried only after the back-off',
      () async {
        ads.results.addAll([null, null]);
        await service.setAdsAllowed(true);
        expect(service.adState, AdState.unavailable);
        await service.preloadRewardedAd();
        expect(ads.loads, hasLength(1)); // backing off
        now = now.add(const Duration(seconds: 61));
        await service.preloadRewardedAd();
        expect(ads.loads, hasLength(2));
        expect(service.adState, AdState.unavailable);
        now = now.add(const Duration(minutes: 2));
        await service.preloadRewardedAd(); // results empty → a fresh ad
        expect(service.adState, AdState.ready);
      },
    );

    test('notifies listeners on state changes', () async {
      var n = 0;
      service.addListener(() => n++);
      await service.setAdsAllowed(true);
      expect(n, greaterThanOrEqualTo(2)); // loading, ready
    });
  });

  group('child-directed ad requests', () {
    test('request configuration: child treatment, max rating G', () {
      final c = childDirectedRequestConfiguration();
      expect(c.maxAdContentRating, MaxAdContentRating.g);
      expect(c.ageRestrictedTreatment, AgeRestrictedTreatment.child);
      // ignore: deprecated_member_use
      expect(c.tagForChildDirectedTreatment, TagForChildDirectedTreatment.yes);
      // ignore: deprecated_member_use
      expect(c.tagForUnderAgeOfConsent, TagForUnderAgeOfConsent.yes);
    });

    test('ad requests are non-personalised', () {
      expect(nonPersonalisedAdRequest.nonPersonalizedAds, isTrue);
      expect(nonPersonalisedAdRequest.keywords, isNull);
    });
  });

  group('store', () {
    test('prices come from the store; unknown store ids are ignored', () async {
      expect(service.storeAvailable, isFalse);
      expect(service.priceOf(Product.slots24), isNull);
      await service.refreshStore();
      expect(service.storeAvailable, isTrue);
      expect(service.priceOf(Product.slots24), '￥250');
      expect(service.priceOf(Product.noAdsPass), '￥320');
    });

    test('unavailable store / query failure', () async {
      store.available = false;
      await service.refreshStore();
      expect(service.storeAvailable, isFalse);
      expect(
        await service.purchase(Product.slots24),
        PurchaseResult.unavailable,
      );
      store
        ..available = true
        ..queryError = StateError('offline');
      await service.refreshStore();
      expect(service.storeAvailable, isFalse);
      expect(store.bought, isEmpty);
    });

    test('purchase → entitlement emitted and acknowledged', () async {
      await service.start(const {});
      await service.refreshStore();
      final result = service.purchase(Product.slots24);
      await pumpEventQueue();
      expect(store.bought, ['slots_24']);
      store.updates.add([
        sp('slots_24', StorePurchaseStatus.purchased, needsCompletion: true),
      ]);
      expect(await result, PurchaseResult.purchased);
      expect(store.completed, ['slots_24']);
      expect(service.owned, {Product.slots24});
      await pumpEventQueue();
      expect(emitted.last, {Product.slots24});
      // Buying an owned product does not launch the store again.
      expect(await service.purchase(Product.slots24), PurchaseResult.purchased);
      expect(store.bought, hasLength(1));
    });

    test(
      'pending: no entitlement, no acknowledgement until purchased',
      () async {
        await service.start(const {});
        await service.refreshStore();
        final result = service.purchase(Product.noAdsPass);
        await pumpEventQueue();
        store.updates.add([sp('no_ads_pass', StorePurchaseStatus.pending)]);
        expect(await result, PurchaseResult.pending);
        expect(service.owned, isEmpty);
        expect(store.completed, isEmpty);
        // Paid later (コンビニ払い): granted and acknowledged then.
        store.updates.add([
          sp(
            'no_ads_pass',
            StorePurchaseStatus.purchased,
            needsCompletion: true,
          ),
        ]);
        await pumpEventQueue();
        expect(service.owned, {Product.noAdsPass});
        expect(store.completed, ['no_ads_pass']);
      },
    );

    test('cancelled and error', () async {
      await service.start(const {});
      await service.refreshStore();
      var r = service.purchase(Product.framePack);
      await pumpEventQueue();
      store.updates.add([sp('frame_pack_1', StorePurchaseStatus.canceled)]);
      expect(await r, PurchaseResult.cancelled);
      r = service.purchase(Product.framePack);
      await pumpEventQueue();
      store.updates.add([sp('frame_pack_1', StorePurchaseStatus.error)]);
      expect(await r, PurchaseResult.error);
      expect(service.owned, isEmpty);
      expect(store.completed, isEmpty);
    });

    test('purchase sheet could not start → error', () async {
      await service.refreshStore();
      store.launch = false;
      expect(await service.purchase(Product.slots24), PurchaseResult.error);
    });

    test('no answer from the store → pending after the timeout', () async {
      final quick = AppMonetizationService(
        ads: ads,
        store: store,
        rewardedAdUnitId: 'unit-1',
        purchaseTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(quick.dispose);
      await quick.refreshStore();
      expect(await quick.purchase(Product.slots24), PurchaseResult.pending);
    });

    test(
      'a failed acknowledgement still grants and is retried on restore',
      () async {
        await service.start(const {});
        store.completeError = StateError('ack failed');
        store.updates.add([
          sp('slots_24', StorePurchaseStatus.purchased, needsCompletion: true),
        ]);
        await pumpEventQueue();
        expect(service.owned, {Product.slots24});
        store
          ..completeError = null
          ..ownedList = [
            sp('slots_24', StorePurchaseStatus.restored, needsCompletion: true),
          ];
        expect(await service.restorePurchases(), isTrue);
        expect(store.completed, ['slots_24']);
      },
    );
  });

  group('entitlements: start and restore', () {
    test(
      'start keeps cached entitlements when the store is unreachable',
      () async {
        store.ownedError = StateError('no Play Store');
        await service.start({Product.framePack});
        expect(service.owned, {Product.framePack});
        await pumpEventQueue();
        expect(emitted, isEmpty);
      },
    );

    test('restore is authoritative: refunded products disappear', () async {
      store.ownedList = [sp('no_ads_pass', StorePurchaseStatus.restored)];
      await service.start({Product.framePack, Product.noAdsPass});
      expect(service.owned, {Product.noAdsPass});
      await pumpEventQueue();
      expect(emitted.last, {Product.noAdsPass});
    });

    test('restore ignores pending and unknown products', () async {
      store.ownedList = [
        sp('slots_24', StorePurchaseStatus.pending),
        sp('old_item', StorePurchaseStatus.restored),
        sp('frame_pack_1', StorePurchaseStatus.restored, needsCompletion: true),
      ];
      expect(await service.restorePurchases(), isTrue);
      expect(service.owned, {Product.framePack});
      expect(store.completed, ['frame_pack_1']);
    });

    test('restore failure reports false and keeps entitlements', () async {
      store.ownedList = [sp('slots_24', StorePurchaseStatus.restored)];
      await service.restorePurchases();
      store.ownedError = StateError('offline');
      expect(await service.restorePurchases(), isFalse);
      expect(service.owned, {Product.slots24});
    });

    test('purchases made elsewhere arrive on the update stream', () async {
      await service.start(const {});
      store.updates.add([sp('frame_pack_1', StorePurchaseStatus.restored)]);
      await pumpEventQueue();
      expect(service.owned, {Product.framePack});
    });
  });
}
