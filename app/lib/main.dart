import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/crash_reporting.dart';
import 'core/licenses.dart';
import 'core/providers.dart';
import 'data/backend/firebase_bootstrap.dart';
import 'data/drawing_loop_storage.dart';
import 'data/file_character_repository.dart';
import 'data/settings_repository.dart';
import 'features/birth/ai_report.dart';
import 'features/monetization/admob_gateway.dart';
import 'features/monetization/app_monetization_service.dart';
import 'features/monetization/gateways.dart';
import 'features/monetization/monetization_service.dart';
import 'features/monetization/play_store_gateway.dart';
import 'features/puppet/puppet_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  registerAssetLicenses();
  final docs = await getApplicationDocumentsDirectory();
  final backend = await initBackend(); // offline when Firebase isn't set up
  // Crashlytics only exists when Firebase is configured; collection stays
  // off until the parent opts in (monetizationSyncProvider).
  final CrashReporter crash = backend.isAvailable
      ? FirebaseCrashReporter()
      : const NoopCrashReporter();
  // Ads SDK is only initialised after the parent allows ads (lazy).
  // Rewarded ads exist only on Android (SPEC §12.6: the iPhone build has
  // no ads); purchases only when kIapEnabled (SPEC §12.1: v2.0 is free).
  final MonetizationService monetization =
      Platform.isAndroid && (kAdsEnabledOnAndroid || kIapEnabled)
      ? AppMonetizationService(
          ads: kAdsEnabledOnAndroid ? AdMobGateway() : const NoAdsGateway(),
          store: kIapEnabled
              ? PlayStoreGateway()
              : const DisabledStoreGateway(),
          rewardedAdUnitId: rewardedAdUnitId,
        )
      : const NoopMonetizationService();
  runApp(
    ProviderScope(
      // Local files and assets do not get better by retrying.
      retry: (_, _) => null,
      overrides: [
        characterRepositoryProvider.overrideWithValue(
          FileCharacterRepository(docs),
        ),
        settingsRepositoryProvider.overrideWithValue(
          FileSettingsRepository(docs),
        ),
        drawingLoopStorageProvider.overrideWithValue(
          FileDrawingLoopStorage(docs),
        ),
        puppetStoreProvider.overrideWithValue(FilePuppetStore(docs)),
        aiReportStoreProvider.overrideWithValue(FileAiReportStore(docs)),
        backendApiProvider.overrideWithValue(backend),
        crashReporterProvider.overrideWithValue(crash),
        monetizationServiceProvider.overrideWithValue(monetization),
      ],
      child: const DoodleBattleApp(),
    ),
  );
}
