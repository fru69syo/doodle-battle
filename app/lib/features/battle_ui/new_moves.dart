import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';

/// Asks the cloud (`generateMove`) for the move unlocked at Lv10 (slot 2)
/// or Lv50 (slot 3). Only with the parent's cloud-judging consent and when
/// the cost mode allows it; any failure keeps the template move silently
/// (the child already sees a move with a template name).
class NewMoveNamer {
  NewMoveNamer(this._ref);
  final Ref _ref;

  static const timeout = Duration(seconds: 30);

  Future<void> nameNewSlots(CharacterV2 c, List<int> slots) async {
    final wanted = [
      for (final s in slots)
        if (s >= 2 && s <= 3) s,
    ];
    if (wanted.isEmpty) return;
    try {
      final backend = _ref.read(backendApiProvider);
      final settings = await _ref.read(settingsProvider.future);
      if (!backend.isAvailable || !settings.consents.cloudJudge) return;
      if (!(await backend.costMode().timeout(timeout)).cloudMoveGen) return;
      final png = await _ref.read(characterRepositoryProvider).readImage(c.id);
      if (png == null) return;
      await _ref.read(settingsProvider.notifier).ensureConsentSynced();
      for (final slot in wanted) {
        final now = _ref.read(characterByIdProvider(c.id)) ?? c;
        final moves = now.allMoves();
        final others = [
          for (var i = 0; i < now.unlockedSlotCount(); i++)
            if (i != slot) moveDisplayName(moves[i]),
        ];
        final proposal = await backend
            .generateMove(
              GenerateMoveRequest(
                character: now,
                png: png,
                slot: slot,
                otherNames: others,
              ),
            )
            .timeout(timeout);
        if (proposal == null) continue;
        final latest = _ref.read(characterByIdProvider(c.id));
        if (latest == null) return;
        await _ref
            .read(charactersProvider.notifier)
            .save(latest.withMoveProposal(slot, proposal));
      }
    } on Object {
      // Template move (offline, refused, rate limited…): nothing to tell.
    }
  }
}

final newMoveNamerProvider = Provider<NewMoveNamer>(NewMoveNamer.new);
