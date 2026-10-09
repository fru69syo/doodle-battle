import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'gateways.dart';

/// Request configuration for every ad request (SPEC §7, Google Play
/// Families policy): child-directed treatment, max content rating G.
///
/// `ageRestrictedTreatment: child` is the current API; the deprecated
/// `tagForChildDirectedTreatment` / `tagForUnderAgeOfConsent` flags are set
/// as well because the SDK applies the most conservative of all signals
/// (https://developers.google.com/admob/android/targeting).
RequestConfiguration childDirectedRequestConfiguration() =>
    RequestConfiguration(
      maxAdContentRating: MaxAdContentRating.g,
      ageRestrictedTreatment: AgeRestrictedTreatment.child,
      // ignore: deprecated_member_use
      tagForChildDirectedTreatment: TagForChildDirectedTreatment.yes,
      // ignore: deprecated_member_use
      tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.yes,
    );

/// Non-personalised ads only (no interest-based ads or remarketing).
const AdRequest nonPersonalisedAdRequest = AdRequest(nonPersonalizedAds: true);

/// [RewardedAdsGateway] backed by `google_mobile_ads` (AdMob).
class AdMobGateway implements RewardedAdsGateway {
  AdMobGateway({this.loadTimeout = const Duration(seconds: 30)});

  final Duration loadTimeout;

  @override
  Future<void> initialize() async {
    final ads = MobileAds.instance;
    // Must be set before initialize() so no request goes out untagged.
    await ads.updateRequestConfiguration(childDirectedRequestConfiguration());
    // No mediation partners are used; do not initialise any adapters.
    await ads.disableMediationInitialization();
    await ads.initialize();
  }

  @override
  Future<LoadedRewardedAd?> load(String adUnitId) {
    final done = Completer<LoadedRewardedAd?>();
    unawaited(
      RewardedAd.load(
        adUnitId: adUnitId,
        request: nonPersonalisedAdRequest,
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (done.isCompleted) {
              ad.dispose();
            } else {
              done.complete(_AdMobRewardedAd(ad));
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint('rewarded ad failed to load: ${error.code}');
            if (!done.isCompleted) done.complete(null);
          },
        ),
      ).catchError((Object e) {
        if (!done.isCompleted) done.complete(null);
      }),
    );
    return done.future.timeout(loadTimeout, onTimeout: () => null);
  }
}

class _AdMobRewardedAd implements LoadedRewardedAd {
  _AdMobRewardedAd(this._ad);
  final RewardedAd _ad;

  @override
  Future<bool> show() {
    final closed = Completer<bool>();
    var earned = false;
    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        if (!closed.isCompleted) closed.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (_, _) {
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    unawaited(
      _ad.show(onUserEarnedReward: (_, _) => earned = true).catchError((
        Object _,
      ) {
        if (!closed.isCompleted) closed.complete(false);
      }),
    );
    return closed.future;
  }

  @override
  void dispose() => unawaited(_ad.dispose());
}
