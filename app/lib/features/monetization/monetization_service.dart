/// Monetization hooks (SPEC §7). The App/UI team only defines the interface
/// and places the entry points; the Compliance team plugs in AdMob (rewarded,
/// child-directed, non-personalised) and Google Play Billing.
library;

import 'dart:async';

/// Products sold in the おうちのひと shop. No random items (no gacha).
enum Product {
  /// ずかんの ほぞんわく +24.
  slots24('slots_24', 'ずかんの ほぞんわく +24', 'キャラを あと24たい ほぞん できる'),

  /// カードの フレームパック.
  framePack('frame_pack_1', 'カードの フレームパック', 'ずかんの カードに かわいい わくが つく'),

  /// おうえんパス: XP boost without ads.
  ouenPass('ouen_pass', 'おうえんパス', 'こうこくなしで けいけんちが 2ばい');

  const Product(this.id, this.title, this.description);

  /// Play Console product id (placeholder until Compliance confirms).
  final String id;
  final String title;
  final String description;

  static Product? byId(String id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

enum RewardedAdResult {
  /// Watched to the end: grant the reward.
  rewarded,

  /// Closed early / failed: no reward.
  notRewarded,

  /// No ad SDK / no fill.
  unavailable,
}

enum PurchaseResult { purchased, cancelled, pending, unavailable, error }

abstract interface class MonetizationService {
  /// Whether a rewarded ad can be shown right now.
  bool get rewardedAdReady;

  /// Shows a rewarded ad. Callers must already have shown the notice and
  /// checked the parent's ads consent.
  Future<RewardedAdResult> showRewardedAd();

  /// Whether the store is reachable and products can be bought.
  bool get storeAvailable;

  /// Starts a purchase. Callers must already have passed the parental gate.
  Future<PurchaseResult> purchase(Product product);

  /// Re-delivers past purchases via [entitlements].
  Future<void> restorePurchases();

  /// Owned products. Emits whenever the store reports them (e.g. after a
  /// purchase or restore); the app caches the last value in settings.
  Stream<Set<Product>> get entitlements;
}

/// Default until Compliance plugs in real SDKs: no ads, no store.
class NoopMonetizationService implements MonetizationService {
  const NoopMonetizationService();

  @override
  bool get rewardedAdReady => false;

  @override
  Future<RewardedAdResult> showRewardedAd() async =>
      RewardedAdResult.unavailable;

  @override
  bool get storeAvailable => false;

  @override
  Future<PurchaseResult> purchase(Product product) async =>
      PurchaseResult.unavailable;

  @override
  Future<void> restorePurchases() async {}

  @override
  Stream<Set<Product>> get entitlements => const Stream.empty();
}
