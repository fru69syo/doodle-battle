import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/licenses.dart';
import 'core/providers.dart';
import 'data/backend/firebase_bootstrap.dart';
import 'data/file_character_repository.dart';
import 'data/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  registerAssetLicenses();
  final docs = await getApplicationDocumentsDirectory();
  final backend = await initBackend(); // offline when Firebase isn't set up
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
      ],
      child: const DoodleBattleApp(),
    ),
  );
}
