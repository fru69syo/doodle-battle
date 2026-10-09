/// Monetization (SPEC §7): rewarded ads (AdMob, child-directed,
/// non-personalised) and Google Play Billing (one-time, non-consumable
/// products only). The real implementation is [AppMonetizationService]
/// (app_monetization_service.dart); [NoopMonetizationService] is the
/// default (no ads, no store) for tests and non-Android builds.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Products sold in the おうちのひと shop. All are one-time, non-consumable
/// purchases. No random items (no gacha) and no subscriptions.
enum Product {
  /// ずかんの ほぞんわく +24 (collection limit 12 → 36).
  slots24('slots_24', 'ずかんの ほぞんわく +24', 'キャラを あと24たい ほぞん できる'),

  /// カードの フレームパック (cosmetic card frames in ずかん).
  framePack('frame_pack_1', 'カードの フレームパック', 'ずかんの カードに かわいい わくが つく'),

  /// おうえんパス: XP ×2 after every battle without ads.
  ouenPass('ouen_pass', 'おうえんパス', 'こうこくなしで けいけんちが 2ばい');

  const Product(this.id, this.title, this.description);

  /// Play Console product id (managed product, docs/STORE_LISTING.md §8).
  final String id;
  final String title;
  final String description;

  static Product? byId(String id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }

  static Set<String> get allIds => {for (final p in values) p.id};
}

enum RewardedAdResult {
  /// Watched to the end: grant the reward.
  rewarded,

  /// Closed early / failed to show: no reward.
  notRewarded,

  /// Ads not allowed, no SDK or no fill.
  unavailable,
}

/// Rewarded-ad readiness, for the result-screen button.
enum AdState {
  /// The parent has not allowed ads (SDK not even initialised).
  off,

  /// Initialising the SDK / loading an ad.
  loading,

  /// An ad is loaded and can be shown.
  ready,

  /// Loading failed (offline / no fill); retried later.
  unavailable,
}

enum PurchaseResult { purchased, cancelled, pending, unavailable, error }

abstract interface class MonetizationService implements Listenable {
  /// Called once when the cached entitlements are known (app start). Starts
  /// listening for purchase updates and silently reconciles owned products
  /// with the store (acknowledges anything left unacknowledged).
  Future<void> start(Set<Product> cachedEntitlements);

  // ---- Ads ---------------------------------------------------------------

  /// Mirrors the parent's ads consent. The ads SDK is initialised lazily the
  /// first time this is called with true; with false any loaded ad is
  /// dropped and nothing is requested.
  Future<void> setAdsAllowed(bool allowed);

  AdState get adState;

  /// Whether a rewarded ad can be shown right now.
  bool get rewardedAdReady;

  /// Loads an ad if allowed and none is loaded (failures back off).
  Future<void> preloadRewardedAd();

  /// Shows a rewarded ad. Callers must already have shown the notice
  /// (「おうちのひとに きいてから みてね」) and checked the daily cap.
  Future<RewardedAdResult> showRewardedAd();

  // ---- Purchases ---------------------------------------------------------

  /// Whether the store is reachable and the products were found.
  bool get storeAvailable;

  /// Localised price from the store (e.g. "￥250"), null until loaded.
  String? priceOf(Product product);

  /// (Re)loads store availability and product details.
  Future<void> refreshStore();

  /// Starts a purchase. Callers must already have passed the parental gate
  /// and shown the notice with the price.
  Future<PurchaseResult> purchase(Product product);

  /// Asks the store which products are owned and re-emits [entitlements].
  /// Returns false when the store could not be reached.
  Future<bool> restorePurchases();

  /// Currently owned products.
  Set<Product> get owned;

  /// Owned products; emits after purchases and restores. The app caches the
  /// last value in settings so limits work offline.
  Stream<Set<Product>> get entitlements;
}

/// Default when no SDK is wired: no ads, no store.
class NoopMonetizationService implements MonetizationService {
  const NoopMonetizationService();

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}

  @override
  Future<void> start(Set<Product> cachedEntitlements) async {}

  @override
  Future<void> setAdsAllowed(bool allowed) async {}

  @override
  AdState get adState => AdState.off;

  @override
  bool get rewardedAdReady => false;

  @override
  Future<void> preloadRewardedAd() async {}

  @override
  Future<RewardedAdResult> showRewardedAd() async =>
      RewardedAdResult.unavailable;

  @override
  bool get storeAvailable => false;

  @override
  String? priceOf(Product product) => null;

  @override
  Future<void> refreshStore() async {}

  @override
  Future<PurchaseResult> purchase(Product product) async =>
      PurchaseResult.unavailable;

  @override
  Future<bool> restorePurchases() async => false;

  @override
  Set<Product> get owned => const {};

  @override
  Stream<Set<Product>> get entitlements => const Stream.empty();
}
