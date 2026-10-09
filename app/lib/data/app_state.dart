/// App-wide state notifiers backed by the repositories.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../domain/character.dart';
import 'app_settings.dart';
import 'character_repository.dart';
import 'game_progress.dart';

/// Parent settings. Consent changes are mirrored to the server (best effort;
/// retried by [ensureConsentSynced] before any server feature is used).
class SettingsController extends AsyncNotifier<AppSettings> {
  ParentConsents? _synced;

  @override
  Future<AppSettings> build() =>
      ref.watch(settingsRepositoryProvider).loadSettings();

  Future<void> _save(AppSettings s) async {
    await ref.read(settingsRepositoryProvider).saveSettings(s);
    state = AsyncData(s);
  }

  /// Finishes the first-run parent setup.
  Future<void> completeSetup(ParentConsents consents) async {
    final current = await future;
    await _save(
      current.copyWith(
        setupCompleted: true,
        policyVersion: currentPolicyVersion,
        consents: consents,
      ),
    );
    unawaited(ensureConsentSynced());
  }

  Future<void> updateConsents(ParentConsents consents) async {
    final current = await future;
    await _save(current.copyWith(consents: consents));
    unawaited(ensureConsentSynced());
  }

  Future<void> setPlayTime(int? minutes) async {
    final current = await future;
    await _save(current.copyWith(playTimeMinutes: () => minutes));
  }

  Future<void> setEntitlements(Set<String> ids) async {
    final current = await future;
    if (setEquals(current.entitlements, ids)) return;
    await _save(current.copyWith(entitlements: ids));
  }

  /// Writes consent to the server if it changed since the last successful
  /// sync. Skipped while every server feature is off and nothing was ever
  /// synced (no account is created for offline-only families).
  Future<bool> ensureConsentSynced() async {
    final backend = ref.read(backendApiProvider);
    if (!backend.isAvailable) return false;
    final s = await future;
    if (_synced == s.consents) return true;
    final anyServer = s.consents.cloudJudge || s.consents.online;
    if (!anyServer && backend.supportId == null) return true;
    try {
      await backend.syncConsent(s.consents, s.policyVersion);
      _synced = s.consents;
      return true;
    } on Object {
      return false;
    }
  }

  /// Local wipe (after 「すべてのデータを削除」).
  Future<void> resetLocal() async {
    await ref.read(settingsRepositoryProvider).clear();
    _synced = null;
    state = const AsyncData(AppSettings());
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Collection size limit from cached entitlements.
final collectionLimitProvider = Provider<int>((ref) {
  final s = ref.watch(settingsProvider).value;
  final extra = (s?.entitlements.contains('slots_24') ?? false)
      ? extraSlotsPerPack
      : 0;
  return freeCollectionLimit + extra;
});

/// The child's characters, oldest first.
class CharactersController extends AsyncNotifier<List<Character>> {
  @override
  Future<List<Character>> build() =>
      ref.watch(characterRepositoryProvider).loadAll();

  CharacterRepository get _repo => ref.read(characterRepositoryProvider);

  /// Throws [CollectionFullException].
  Future<void> add(Character c, Uint8List png) async {
    await _repo.add(c, png, limit: ref.read(collectionLimitProvider));
    state = AsyncData([...await future, c]);
  }

  Future<void> save(Character c) async {
    await _repo.update(c);
    state = AsyncData([for (final x in await future) x.id == c.id ? c : x]);
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    state = AsyncData([
      for (final x in await future)
        if (x.id != id) x,
    ]);
  }

  Future<void> deleteAll() async {
    await _repo.deleteAll();
    state = const AsyncData([]);
  }
}

final charactersProvider =
    AsyncNotifierProvider<CharactersController, List<Character>>(
      CharactersController.new,
    );

/// One character by id (null when missing / still loading).
final characterByIdProvider = Provider.family<Character?, String>((ref, id) {
  final list = ref.watch(charactersProvider).value ?? const [];
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

/// Cut-out PNG of a stored character.
final characterImageProvider = FutureProvider.family<Uint8List?, String>(
  (ref, id) => ref.watch(characterRepositoryProvider).readImage(id),
);

class ProgressController extends AsyncNotifier<GameProgress> {
  @override
  Future<GameProgress> build() =>
      ref.watch(settingsRepositoryProvider).loadProgress();

  Future<void> _save(GameProgress p) async {
    await ref.read(settingsRepositoryProvider).saveProgress(p);
    state = AsyncData(p);
  }

  Future<void> markStageCleared(int stage) async {
    final p = await future;
    if (stage > p.clearedStage) await _save(p.copyWith(clearedStage: stage));
  }

  /// Returns false when [matchId] was already applied.
  Future<bool> markMatchApplied(String matchId) async {
    final p = await future;
    if (p.appliedMatchIds.contains(matchId)) return false;
    await _save(p.withAppliedMatch(matchId));
    return true;
  }

  /// Adds foreground play time for the local [date] (yyyy-mm-dd).
  Future<void> addPlayTime(String date, int seconds) async {
    final p = await future;
    final today = p.playDate == date ? p.playSecondsToday : 0;
    await _save(p.copyWith(playDate: date, playSecondsToday: today + seconds));
  }

  Future<void> setOnlineLevel(String characterId, int level) async {
    final p = await future;
    await _save(
      p.copyWith(onlineLevels: {...p.onlineLevels, characterId: level}),
    );
  }

  Future<void> resetLocal() async => _save(const GameProgress());
}

final progressProvider =
    AsyncNotifierProvider<ProgressController, GameProgress>(
      ProgressController.new,
    );
