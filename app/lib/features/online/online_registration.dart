import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../domain/character_v2.dart';
import '../draw_canvas/stroke_drawing.dart';
import '../puppet/puppet_store.dart';
import 'online_messages.dart';

sealed class RegistrationResult {
  const RegistrationResult();
}

class RegistrationOk extends RegistrationResult {
  const RegistrationOk(this.character);
  final CharacterV2 character;
}

class RegistrationRejected extends RegistrationResult {
  const RegistrationRejected(this.message, {this.presetNames = const []});
  final String message;

  /// Offered when the name was the problem (SPEC §5).
  final List<String> presetNames;
}

/// Registers a character for online play (server moderation, SPEC §5) when
/// it has no snapshot yet or has grown since the last one.
class OnlineRegistration {
  OnlineRegistration(this._ref);
  final Ref _ref;

  Future<RegistrationResult> ensureRegistered(CharacterV2 c) async {
    final progress = await _ref.read(progressProvider.future);
    if (c.onlineId != null && progress.onlineLevels[c.id] == c.level) {
      return RegistrationOk(c);
    }
    final backend = _ref.read(backendApiProvider);
    final png = await _ref.read(characterRepositoryProvider).readImage(c.id);
    if (png == null) return const RegistrationRejected('キャラの えが みつからなかったよ');
    try {
      await _ref.read(settingsProvider.notifier).ensureConsentSynced();
      final outcome = await backend.registerCharacter(
        RegisterCharacterRequest(
          character: c,
          png: png,
          canvas: c.source == DrawingSource.canvas
              ? await _canvasSummary(c.id)
              : null,
        ),
      );
      switch (outcome) {
        case RegisterAccepted(
          :final snapshotId,
          :final displayName,
          :final imageHash,
        ):
          // The server's seed hash is the authority: the stats on the
          // phone stay equal to the online ones (docs/TRUST.md §8.1).
          final updated = c.copyWith(
            onlineId: () => snapshotId,
            imageHash: imageHash,
          );
          await _ref.read(charactersProvider.notifier).save(updated);
          final progress = _ref.read(progressProvider.notifier);
          await progress.setOnlineLevel(c.id, c.level);
          // The server assigns a random preset name at the first
          // registration; remember it so the lobby can show it.
          if (displayName != null &&
              (await _ref.read(progressProvider.future)).displayName == null) {
            await progress.setDisplayName(
              ChosenDisplayName(adjectiveId: '', nounId: '', text: displayName),
            );
          }
          return RegistrationOk(updated);
        case RegisterRejected(
          :final reason,
          :final presetNames,
          :final isNameProblem,
        ):
          return RegistrationRejected(
            registerRejectionMessage(reason),
            presetNames: isNameProblem ? presetNames : const [],
          );
      }
    } on BackendException catch (e) {
      return RegistrationRejected(backendErrorMessage(e.code));
    }
  }

  /// The drawing tool's stroke summary (kept on the phone with the
  /// strokes for the rigger), or null.
  Future<Map<String, Object?>?> _canvasSummary(String id) async {
    try {
      final json = await _ref.read(puppetStoreProvider).loadStrokesJson(id);
      return StrokeDrawing.tryDecode(json)?.canvasSummary();
    } on Object {
      return null;
    }
  }

  /// Forgets the server snapshot (e.g. a v1 snapshot the v2 server no
  /// longer knows) so the next [ensureRegistered] registers again.
  Future<CharacterV2> forgetSnapshot(CharacterV2 c) async {
    final updated = c.copyWith(onlineId: () => null);
    await _ref.read(charactersProvider.notifier).save(updated);
    await _ref.read(progressProvider.notifier).setOnlineLevel(c.id, -1);
    return updated;
  }

  /// Renames the local character to a server-provided preset name.
  Future<CharacterV2> rename(CharacterV2 c, String presetName) async {
    final updated = c.copyWith(name: presetName);
    await _ref.read(charactersProvider.notifier).save(updated);
    return updated;
  }
}

final onlineRegistrationProvider = Provider<OnlineRegistration>(
  OnlineRegistration.new,
);
