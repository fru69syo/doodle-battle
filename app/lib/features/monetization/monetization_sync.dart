import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import 'monetization_service.dart';

/// Wires the parent's settings to the monetization service and the crash
/// reporter (watched once by the app root):
/// - starts the service with the cached entitlements (first settings load),
/// - mirrors store entitlements into `settings.entitlements` (offline cache),
/// - mirrors the ads consent (lazy SDK initialisation; off = nothing loads),
/// - mirrors the crash-report consent.
final monetizationSyncProvider = Provider<void>((ref) {
  final service = ref.watch(monetizationServiceProvider);
  final sub = service.entitlements.listen((owned) {
    unawaited(
      ref.read(settingsProvider.notifier).setEntitlements({
        for (final p in owned) p.id,
      }),
    );
  });
  ref.onDispose(sub.cancel);

  var started = false;
  ref.listen(settingsProvider, (_, next) {
    final s = next.value;
    if (s == null) return;
    if (!started) {
      started = true;
      unawaited(
        service.start({for (final id in s.entitlements) ?Product.byId(id)}),
      );
    }
    unawaited(service.setAdsAllowed(s.consents.ads));
  }, fireImmediately: true);

  final crash = ref.watch(crashReporterProvider);
  ref.listen(settingsProvider.select((s) => s.value?.consents.crashReports), (
    _,
    on,
  ) {
    if (on == null) return;
    unawaited(crash.setEnabled(on && crash.isAvailable));
  }, fireImmediately: true);
});

/// Ad boosts left today (daily cap, `dailyAdBoostCap`).
int adBoostsLeft({required int cap, required int usedToday}) =>
    usedToday >= cap ? 0 : cap - usedToday;
