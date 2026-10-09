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
import 'data/file_character_repository.dart';
import 'data/settings_repository.dart';
import 'features/monetization/admob_gateway.dart';
import 'features/monetization/app_monetization_service.dart';
import 'features/monetization/monetization_service.dart';
import 'features/monetization/play_store_gateway.dart';

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
  final MonetizationService monetization = Platform.isAndroid
      ? AppMonetizationService(
          ads: AdMobGateway(),
          store: PlayStoreGateway(),
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
        backendApiProvider.overrideWithValue(backend),
        crashReporterProvider.overrideWithValue(crash),
        monetizationServiceProvider.overrideWithValue(monetization),
      ],
      child: const DoodleBattleApp(),
    ),
  );
}
