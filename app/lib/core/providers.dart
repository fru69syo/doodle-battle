/// Service providers. `main.dart` overrides the repositories and the
/// backend; tests override anything with fakes.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend/backend_api.dart';
import '../data/character_repository.dart';
import '../data/settings_repository.dart';
import '../domain/battle/battle.dart';
import '../domain/cost_mode.dart';
import '../domain/cpu_roster_v2.dart';
import '../domain/battle/battle_spec_asset.dart';
import '../features/draw/drawing_services.dart';
import '../features/monetization/monetization_service.dart';
import '../features/ng_filter/ng_filter.dart';
import '../features/parental_gate/parental_gate.dart';
import 'crash_reporting.dart';

final characterRepositoryProvider = Provider<CharacterRepository>(
  (ref) => throw UnimplementedError('override in main()'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('override in main()'),
);

final backendApiProvider = Provider<BackendApi>(
  (ref) => const UnavailableBackendApi(),
);

final monetizationServiceProvider = Provider<MonetizationService>(
  (ref) => const NoopMonetizationService(),
);

/// Opt-in crash reports (Crashlytics when Firebase is configured).
final crashReporterProvider = Provider<CrashReporter>(
  (ref) => const NoopCrashReporter(),
);

final parentalGateProvider = Provider<ParentalGate>(
  (ref) => DialogParentalGate(),
);

final drawingAnalyzerProvider = Provider<DrawingAnalyzerService>(
  (ref) => const OnDeviceDrawingAnalyzer(),
);

final drawingImageSourceProvider = Provider<DrawingImageSource>(
  (ref) => ImagePickerDrawingSource(),
);

/// Wall clock (overridable in tests).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Randomness for battle seeds and ids (seeded in tests).
final randomProvider = Provider<Random>((ref) => Random());

final battleSpecProvider = FutureProvider<BattleSpec>(
  (ref) => loadBattleSpec(),
);

final ngFilterProvider = FutureProvider<NgFilter>((ref) => NgFilter.load());

final cpuRosterProvider = FutureProvider<CpuRoster>((ref) => loadCpuRoster());

/// Bundled CPU doodles of v2.0 single-player (`manifest_v2.json`).
final cpuRosterV2Provider = FutureProvider<CpuRosterV2>(
  (ref) async => CpuRosterV2.fromManifestJson(
    (jsonDecode(await rootBundle.loadString(kCpuManifestV2Path)) as Map)
        .cast<String, Object?>(),
  ),
);

/// Bytes of a bundled asset (CPU doodles for the stage puppets).
final assetBytesProvider = FutureProvider.family<Uint8List, String>(
  (ref, key) async => (await rootBundle.load(key)).buffer.asUint8List(),
);

/// `config/costMode` (SPEC §12.7), read when a server feature starts.
final costModeProvider = FutureProvider<CostMode>(
  (ref) => ref.watch(backendApiProvider).costMode(),
);
