import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'gateways.dart';

/// [StoreGateway] on Google Play Billing (`in_app_purchase`, Play Billing
/// Library 8 via in_app_purchase_android).
class PlayStoreGateway implements StoreGateway {
  PlayStoreGateway({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } on Object {
      return false;
    }
  }

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async {
    final r = await _iap.queryProductDetails(ids);
    if (r.error != null && r.productDetails.isEmpty) {
      throw StateError('queryProductDetails: ${r.error!.message}');
    }
    return [
      for (final d in r.productDetails)
        StoreProduct(id: d.id, price: d.price, raw: d),
    ];
  }

  @override
  Future<bool> buyNonConsumable(StoreProduct product) => _iap.buyNonConsumable(
    purchaseParam: PurchaseParam(
      productDetails: product.raw! as ProductDetails,
    ),
  );

  @override
  Stream<List<StorePurchase>> get purchaseUpdates =>
      _iap.purchaseStream.map((list) => [for (final p in list) _map(p)]);

  @override
  Future<void> completePurchase(StorePurchase purchase) async {
    final raw = purchase.raw! as PurchaseDetails;
    final platform = InAppPurchasePlatform.instance;
    if (platform is InAppPurchaseAndroidPlatform) {
      // Use the Android platform directly to see the acknowledge result.
      final r = await platform.completePurchase(raw);
      if (r.responseCode != BillingResponse.ok) {
        throw StateError('acknowledge failed: ${r.responseCode}');
      }
    } else {
      await _iap.completePurchase(raw);
    }
  }

  @override
  Future<List<StorePurchase>> queryOwned() async {
    final android = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final r = await android.queryPastPurchases();
    if (r.error != null) {
      throw StateError('queryPastPurchases: ${r.error!.message}');
    }
    return [for (final p in r.pastPurchases) _map(p)];
  }

  /// Maps plugin purchases. On Android the Play purchase state is the source
  /// of truth: the plugin reports restored purchases as `restored` even when
  /// Play says they are still PENDING (e.g. コンビニ払い not paid yet), and
  /// those must not grant anything or be acknowledged.
  static StorePurchase _map(PurchaseDetails p) {
    var status = switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      PurchaseStatus.error => StorePurchaseStatus.error,
    };
    if (p is GooglePlayPurchaseDetails &&
        status != StorePurchaseStatus.canceled &&
        status != StorePurchaseStatus.error) {
      final state = p.billingClientPurchase.purchaseState;
      if (state != PurchaseStateWrapper.purchased) {
        status = StorePurchaseStatus.pending;
      }
    }
    final owned =
        status == StorePurchaseStatus.purchased ||
        status == StorePurchaseStatus.restored;
    return StorePurchase(
      productId: p.productID,
      status: status,
      // Only PURCHASED purchases are acknowledged; never PENDING ones.
      needsCompletion: owned && p.pendingCompletePurchase,
      raw: p,
    );
  }
}
