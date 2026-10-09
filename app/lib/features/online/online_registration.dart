import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../domain/character.dart';
import 'online_messages.dart';

sealed class RegistrationResult {
  const RegistrationResult();
}

class RegistrationOk extends RegistrationResult {
  const RegistrationOk(this.character);
  final Character character;
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

  Future<RegistrationResult> ensureRegistered(Character c) async {
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
        RegisterCharacterRequest(character: c, png: png),
      );
      switch (outcome) {
        case RegisterAccepted(:final snapshotId, :final displayName):
          final updated = c.copyWith(onlineId: snapshotId);
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

  /// Renames the local character to a server-provided preset name.
  Future<Character> rename(Character c, String presetName) async {
    final updated = c.copyWith(name: presetName);
    await _ref.read(charactersProvider.notifier).save(updated);
    return updated;
  }
}

final onlineRegistrationProvider = Provider<OnlineRegistration>(
  OnlineRegistration.new,
);
