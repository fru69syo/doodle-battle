/// Service providers. `main.dart` overrides the repositories and the
/// backend; tests override anything with fakes.
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend/backend_api.dart';
import '../data/character_repository.dart';
import '../data/settings_repository.dart';
import '../domain/battle/battle.dart';
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
