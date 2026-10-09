/// Thin seams over the ads SDK and the store plugin, so the monetization
/// logic ([AppMonetizationService]) is unit-tested with fakes.
library;

import 'dart:async';

// ---- Ads ---------------------------------------------------------------

/// A loaded rewarded ad. Can be shown once.
abstract interface class LoadedRewardedAd {
  /// Shows the ad full screen; completes when it is closed. True when the
  /// reward was earned (watched to the end).
  Future<bool> show();

  void dispose();
}

abstract interface class RewardedAdsGateway {
  /// Applies the child-directed request configuration and initialises the
  /// SDK. Called at most once, and only after the parent allowed ads.
  Future<void> initialize();

  /// Loads one non-personalised rewarded ad, or null on failure / no fill.
  Future<LoadedRewardedAd?> load(String adUnitId);
}

// ---- Store -------------------------------------------------------------

class StoreProduct {
  const StoreProduct({required this.id, required this.price, this.raw});

  final String id;

  /// Localised price string from the store (e.g. "￥250").
  final String price;

  /// Plugin object needed to buy (ProductDetails).
  final Object? raw;
}

enum StorePurchaseStatus { pending, purchased, restored, canceled, error }

class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    this.needsCompletion = false,
    this.raw,
  });

  final String productId;
  final StorePurchaseStatus status;

  /// The purchase must be completed (acknowledged on Play) — within three
  /// days, or Google refunds it.
  final bool needsCompletion;

  /// Plugin object needed to complete (PurchaseDetails).
  final Object? raw;

  bool get isOwned =>
      status == StorePurchaseStatus.purchased ||
      status == StorePurchaseStatus.restored;
}

abstract interface class StoreGateway {
  Future<bool> isAvailable();

  /// Details of the known [ids] (unknown ids are left out).
  Future<List<StoreProduct>> queryProducts(Set<String> ids);

  /// Launches the Play purchase sheet. False when it could not be started.
  /// The outcome arrives on [purchaseUpdates].
  Future<bool> buyNonConsumable(StoreProduct product);

  /// Purchase updates (purchase flow results, pending → purchased, ...).
  Stream<List<StorePurchase>> get purchaseUpdates;

  /// Acknowledges / finishes a purchase.
  Future<void> completePurchase(StorePurchase purchase);

  /// Everything currently owned according to the store (purchased *and*
  /// pending). Throws when the store cannot be reached.
  Future<List<StorePurchase>> queryOwned();
}
