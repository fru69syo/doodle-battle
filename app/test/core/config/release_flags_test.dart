// Release defaults (SPEC §10.2): the build a plain `flutter build` makes —
// which is what release.yml builds — is free (no purchases), has rewarded
// ads on Android only, and talks to the test ad unit unless the real one is
// passed in. scripts/check_release.sh checks the same on the release AAB.
import 'package:doodle_battle/core/config/app_config.dart';
import 'package:doodle_battle/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('in-app purchases default to off (v2.0 ships free)', () {
    expect(kIapEnabled, isFalse);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(iapEnabledProvider), isFalse);
  });

  test('rewarded ads are on for Android by default, test unit without ids', () {
    expect(kAdsEnabledOnAndroid, isTrue);
    expect(rewardedAdUnitId, testRewardedAdUnitId);
  });
}
