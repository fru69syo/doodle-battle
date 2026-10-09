import 'dart:io';

import 'app_settings.dart';
import 'game_progress.dart';
import 'json_file.dart';

/// Local store of [AppSettings] (parent) and [GameProgress] (game).
abstract interface class SettingsRepository {
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
  Future<GameProgress> loadProgress();
  Future<void> saveProgress(GameProgress progress);

  /// Deletes everything (used by 「すべてのデータを削除」).
  Future<void> clear();
}

class FileSettingsRepository implements SettingsRepository {
  FileSettingsRepository(Directory root)
    : _settings = File('${root.path}/settings.json'),
      _progress = File('${root.path}/progress.json');

  final File _settings;
  final File _progress;

  @override
  Future<AppSettings> loadSettings() async {
    final j = await readJsonFile(_settings);
    return j == null ? const AppSettings() : AppSettings.fromJson(j);
  }

  @override
  Future<void> saveSettings(AppSettings settings) =>
      writeJsonFile(_settings, settings.toJson());

  @override
  Future<GameProgress> loadProgress() async {
    final j = await readJsonFile(_progress);
    return j == null ? const GameProgress() : GameProgress.fromJson(j);
  }

  @override
  Future<void> saveProgress(GameProgress progress) =>
      writeJsonFile(_progress, progress.toJson());

  @override
  Future<void> clear() async {
    for (final f in [_settings, _progress]) {
      if (await f.exists()) await f.delete();
    }
  }
}

/// In-memory [SettingsRepository] for tests.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository({
    this.settings = const AppSettings(),
    this.progress = const GameProgress(),
  });

  AppSettings settings;
  GameProgress progress;

  @override
  Future<AppSettings> loadSettings() async => settings;

  @override
  Future<void> saveSettings(AppSettings s) async => settings = s;

  @override
  Future<GameProgress> loadProgress() async => progress;

  @override
  Future<void> saveProgress(GameProgress p) async => progress = p;

  @override
  Future<void> clear() async {
    settings = const AppSettings();
    progress = const GameProgress();
  }
}
