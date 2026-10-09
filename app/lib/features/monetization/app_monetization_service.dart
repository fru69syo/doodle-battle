import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateways.dart';
import 'monetization_service.dart';

/// The real [MonetizationService] (docs/COMPLIANCE.md §2–3).
///
/// Ads: nothing touches the ads SDK until the parent allows ads
/// ([setAdsAllowed] true → lazy `initialize()` with the child-directed
/// request configuration → preload one rewarded ad). Load failures back off
/// for [adRetryDelay]. Revoking consent drops the loaded ad.
///
/// Purchases: one-time non-consumables. Entitlements are granted only for
/// PURCHASED (never PENDING) purchases, then acknowledged. A successful
/// [restorePurchases] is authoritative (refunded purchases disappear). v1
/// does no server-side verification (see docs/COMPLIANCE.md for the risk and
/// the v1.1 plan).
class AppMonetizationService extends ChangeNotifier
    implements MonetizationService {
  AppMonetizationService({
    required RewardedAdsGateway ads,
    required StoreGateway store,
    required this.rewardedAdUnitId,
    DateTime Function()? clock,
    this.adRetryDelay = const Duration(minutes: 1),
    this.purchaseTimeout = const Duration(minutes: 15),
  }) : _ads = ads, // ignore: prefer_initializing_formals
       _store = store, // ignore: prefer_initializing_formals
       _clock = clock ?? DateTime.now;

  final RewardedAdsGateway _ads;
  final StoreGateway _store;
  final String rewardedAdUnitId;
  final DateTime Function() _clock;
  final Duration adRetryDelay;
  final Duration purchaseTimeout;

  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  // ---- lifecycle ------------------------------------------------------------

  StreamSubscription<List<StorePurchase>>? _updates;
  bool _started = false;

  @override
  Future<void> start(Set<Product> cachedEntitlements) async {
    if (_started) return;
    _started = true;
    _owned = {..._owned, ...cachedEntitlements};
    // Listen as early as possible: purchases that finish while the app runs
    // (e.g. a pending payment completing) arrive here.
    _updates = _store.purchaseUpdates.listen(
      _onPurchaseUpdates,
      onError: (Object _) {},
    );
    // Silent reconciliation (no UI): picks up purchases made on another
    // device / completed while the app was closed, acknowledges leftovers
    // and drops refunded products.
    await restorePurchases();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _loadedAd?.dispose();
    _loadedAd = null;
    unawaited(_entitlements.close());
    super.dispose();
  }

  // ---- ads ------------------------------------------------------------------

  bool _adsAllowed = false;
  Future<void>? _sdkInit;
  LoadedRewardedAd? _loadedAd;
  bool _loading = false;
  bool _showing = false;
  DateTime? _lastLoadFailure;
  AdState _adState = AdState.off;

  @override
  AdState get adState => _adState;

  @override
  bool get rewardedAdReady => _adState == AdState.ready;

  void _setAdState(AdState s) {
    if (_adState == s) return;
    _adState = s;
    _changed();
  }

  @override
  Future<void> setAdsAllowed(bool allowed) async {
    if (_adsAllowed == allowed) return;
    _adsAllowed = allowed;
    if (!allowed) {
      _loadedAd?.dispose();
      _loadedAd = null;
      _setAdState(AdState.off);
      return;
    }
    await preloadRewardedAd();
  }

  @override
  Future<void> preloadRewardedAd() async {
    if (!_adsAllowed || _loadedAd != null || _loading || _showing) return;
    final failedAt = _lastLoadFailure;
    if (failedAt != null && _clock().difference(failedAt) < adRetryDelay) {
      return;
    }
    _loading = true;
    _setAdState(AdState.loading);
    LoadedRewardedAd? ad;
    try {
      await (_sdkInit ??= _ads.initialize());
      ad = await _ads.load(rewardedAdUnitId);
    } on Object catch (e) {
      debugPrint('rewarded ad unavailable: $e');
      _sdkInit = null; // retry the initialisation next time
      ad = null;
    } finally {
      _loading = false;
    }
    if (!_adsAllowed || _disposed) {
      // Consent was withdrawn while loading.
      ad?.dispose();
      return;
    }
    if (ad == null) {
      _lastLoadFailure = _clock();
      _setAdState(AdState.unavailable);
    } else {
      _lastLoadFailure = null;
      _loadedAd = ad;
      _setAdState(AdState.ready);
    }
  }

  @override
  Future<RewardedAdResult> showRewardedAd() async {
    final ad = _loadedAd;
    if (!_adsAllowed || ad == null || _showing) {
      if (_adsAllowed) unawaited(preloadRewardedAd());
      return RewardedAdResult.unavailable;
    }
    _loadedAd = null;
    _showing = true;
    _setAdState(AdState.loading);
    bool earned;
    try {
      earned = await ad.show();
    } on Object {
      earned = false;
    } finally {
      ad.dispose();
      _showing = false;
    }
    _setAdState(_adsAllowed ? AdState.loading : AdState.off);
    unawaited(preloadRewardedAd());
    return earned ? RewardedAdResult.rewarded : RewardedAdResult.notRewarded;
  }

  // ---- store ----------------------------------------------------------------

  bool _storeAvailable = false;
  final Map<Product, StoreProduct> _products = {};
  Set<Product> _owned = {};
  final _entitlements = StreamController<Set<Product>>.broadcast();
  final Map<Product, Completer<PurchaseResult>> _inFlight = {};

  @override
  bool get storeAvailable => _storeAvailable && _products.isNotEmpty;

  @override
  String? priceOf(Product product) => _products[product]?.price;

  @override
  Set<Product> get owned => Set.unmodifiable(_owned);

  @override
  Stream<Set<Product>> get entitlements => _entitlements.stream;

  void _emitOwned(Set<Product> owned) {
    final changed = !setEquals(owned, _owned);
    _owned = owned;
    if (!_entitlements.isClosed) _entitlements.add(Set.unmodifiable(owned));
    if (changed) _changed();
  }

  @override
  Future<void> refreshStore() async {
    var available = false;
    final products = <Product, StoreProduct>{};
    try {
      available = await _store.isAvailable();
      if (available) {
        for (final sp in await _store.queryProducts(Product.allIds)) {
          final p = Product.byId(sp.id);
          if (p != null) products[p] = sp;
        }
      }
    } on Object catch (e) {
      debugPrint('store unavailable: $e');
      available = false;
    }
    _storeAvailable = available;
    _products
      ..clear()
      ..addAll(products);
    _changed();
  }

  @override
  Future<PurchaseResult> purchase(Product product) async {
    if (_owned.contains(product)) return PurchaseResult.purchased;
    final details = _products[product];
    if (!_storeAvailable || details == null) return PurchaseResult.unavailable;
    final existing = _inFlight[product];
    if (existing != null) return existing.future;
    final done = Completer<PurchaseResult>();
    _inFlight[product] = done;
    try {
      final launched = await _store.buyNonConsumable(details);
      if (!launched) _finish(product, PurchaseResult.error);
    } on Object catch (e) {
      debugPrint('purchase could not start: $e');
      _finish(product, PurchaseResult.error);
    }
    return done.future.timeout(
      purchaseTimeout,
      onTimeout: () {
        _inFlight.remove(product);
        return PurchaseResult.pending;
      },
    );
  }

  void _finish(Product product, PurchaseResult result) {
    final c = _inFlight.remove(product);
    if (c != null && !c.isCompleted) c.complete(result);
  }

  Future<void> _onPurchaseUpdates(List<StorePurchase> updates) async {
    final granted = <Product>{};
    for (final u in updates) {
      final product = Product.byId(u.productId);
      if (product == null) continue;
      switch (u.status) {
        case StorePurchaseStatus.pending:
          // Paid later (e.g. コンビニ払い). Grant nothing yet.
          _finish(product, PurchaseResult.pending);
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          granted.add(product);
          await _acknowledge(u);
          _finish(product, PurchaseResult.purchased);
        case StorePurchaseStatus.canceled:
          _finish(product, PurchaseResult.cancelled);
        case StorePurchaseStatus.error:
          _finish(product, PurchaseResult.error);
      }
    }
    if (granted.isNotEmpty) _emitOwned({..._owned, ...granted});
  }

  /// Acknowledges a PURCHASED purchase (Play refunds unacknowledged ones
  /// after 3 days). A failure is retried by the next [restorePurchases].
  Future<void> _acknowledge(StorePurchase p) async {
    if (!p.needsCompletion) return;
    try {
      await _store.completePurchase(p);
    } on Object catch (e) {
      debugPrint('acknowledge failed (retried on next restore): $e');
    }
  }

  @override
  Future<bool> restorePurchases() async {
    final List<StorePurchase> owned;
    try {
      owned = await _store.queryOwned();
    } on Object catch (e) {
      debugPrint('restore failed: $e');
      return false;
    }
    final products = <Product>{};
    for (final p in owned) {
      final product = Product.byId(p.productId);
      if (product == null || !p.isOwned) continue; // pending: not yet
      products.add(product);
      await _acknowledge(p);
    }
    _emitOwned(products);
    return true;
  }
}
