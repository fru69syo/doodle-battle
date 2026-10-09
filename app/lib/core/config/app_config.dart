/// Every external id and URL the app uses, in one place (docs/COMPLIANCE.md).
///
/// Values that differ per build come from `--dart-define` (CI: release.yml);
/// the defaults are safe for development: Google's official *test* ad unit
/// and the planned GitHub Pages site. The AdMob **App ID** is not here: it
/// must be in the Android manifest and is set by Gradle (`ADMOB_APP_ID`, see
/// android/app/build.gradle.kts).
library;

/// Google's official test rewarded ad unit (Android). Test ads never earn
/// money and are safe to tap during development.
/// https://developers.google.com/admob/android/test-ads
const String testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

/// AdMob ad unit for 「どうがを みて けいけんち 2ばい」.
const String rewardedAdUnitId = String.fromEnvironment(
  'ADMOB_REWARDED_UNIT_ID',
  defaultValue: testRewardedAdUnitId,
);

/// Maximum ad-based XP boosts per local day (おうえんパス is not limited).
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
