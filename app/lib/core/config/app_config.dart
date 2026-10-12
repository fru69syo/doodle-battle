/// Every external id and URL the app uses, in one place (docs/COMPLIANCE.md).
///
/// Values that differ per build come from `--dart-define` (CI: release.yml);
/// the defaults are safe for development: Google's official *test* ad unit
/// and the planned GitHub Pages site. The AdMob **App ID** is not here: it
/// must be in the Android manifest and is set by Gradle (`ADMOB_APP_ID`, see
/// android/app/build.gradle.kts).
library;

/// The app's display name (SPEC §11.4) as shown inside the app: home and
/// setup titles, licences page, card PDF logo, Before/After video logo,
/// watermark and store line. Renaming the app is a one-line change here;
/// outside Dart it also lives in AndroidManifest.xml (`android:label`),
/// ios/Runner/Info.plist (`CFBundleDisplayName`) and store/metadata.
/// Internal ids (package `doodle_battle`, applicationId) never change.
const String appDisplayName = 'おえかきファイターズ';

/// Google's official test rewarded ad unit (Android). Test ads never earn
/// money and are safe to tap during development.
/// https://developers.google.com/admob/android/test-ads
const String testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

/// AdMob ad unit for 「どうがを みて けいけんち 2ばい」.
const String rewardedAdUnitId = String.fromEnvironment(
  'ADMOB_REWARDED_UNIT_ID',
  defaultValue: testRewardedAdUnitId,
);

/// Maximum post-battle XP ×2 bonuses per local day, by ad or with
/// こうこくなしパス alike (SPEC §11.4: paying must not make characters grow
/// faster than watching ads).
const int dailyAdBoostCap = 3;

/// Base URL of the policy/support site (`site/`, deployed to GitHub Pages).
/// Must end with `/`.
const String policySiteBaseUrl = String.fromEnvironment(
  'POLICY_BASE_URL',
  defaultValue: 'https://fru69syo.github.io/doodle-battle/',
);

/// Pages of `site/` opened from おうちのひと (parent-gated).
enum PolicyPage {
  privacy('privacy.html', 'プライバシーポリシー'),
  terms('terms.html', '利用規約'),
  deletion('delete.html', 'データの削除について'),
  support('index.html', 'サポート・よくある質問');

  const PolicyPage(this.path, this.title);
  final String path;
  final String title;

  Uri get uri => Uri.parse('$policySiteBaseUrl$path');
}

/// In-app purchases (SPEC §12.1: v2.0 ships free, no products). The store
/// code is kept but nothing is sold, shown or queried while this is false
/// (default). Turn on with `--dart-define=IAP_ENABLED=true` once the owner
/// is allowed to sell again.
const bool kIapEnabled = bool.fromEnvironment('IAP_ENABLED');

/// Rewarded ads exist only in the Android build (SPEC §12.6: the iPhone
/// build has no ads at all). `--dart-define=ADS_ENABLED=false` removes
/// them from Android too.
const bool kAdsEnabledOnAndroid = bool.fromEnvironment(
  'ADS_ENABLED',
  defaultValue: true,
);

/// Realtime battle server (docs/REALTIME_PROTOCOL.md §1), e.g.
/// `wss://battle-xxxx-an.a.run.app/v2` (Terraform output `realtime_url`).
/// Empty = online battles show 「じゅんびちゅう」.
const String realtimeUrl = String.fromEnvironment('REALTIME_URL');
