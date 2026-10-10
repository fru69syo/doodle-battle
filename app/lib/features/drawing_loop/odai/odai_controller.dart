import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/providers.dart';
import '../../../data/drawing_loop_storage.dart';
import '../../../domain/cosmetics.dart';
import 'daily_odai.dart';
import 'stamp_card.dart';

/// Today's prompt (device local date from [clockProvider]).
final todaysOdaiProvider = Provider<OdaiTheme>(
  (ref) => odaiFor(ref.watch(clockProvider)()),
);

/// The stamp card, persisted in [DrawingLoopStorage].
class StampCardController extends AsyncNotifier<OdaiStampCard> {
  @override
  Future<OdaiStampCard> build() async => OdaiStampCard.fromJson(
    await ref.watch(drawingLoopStorageProvider).loadStampCard(),
  );

  /// Stamps the day of [badge]. Returns true when it is a new stamp.
  Future<bool> award(
    OdaiBadge badge, {
    required StampKind kind,
    String? characterId,
  }) async {
    final card = await future;
    final next = card.withStamp(
      OdaiStampCard.stampFor(badge, kind: kind, characterId: characterId),
    );
    if (identical(next, card)) return false;
    await ref.read(drawingLoopStorageProvider).saveStampCard(next.toJson());
    state = AsyncData(next);
    return true;
  }
}

final stampCardProvider =
    AsyncNotifierProvider<StampCardController, OdaiStampCard>(
      StampCardController.new,
    );

/// The theme the child chose to draw for (set by 「おだいで かく」 on the
/// home card, cleared by the plain 「かく」 button and after the stamp is
/// given). Whatever drawing flow finishes next (new character, part or
/// move effect) earns the stamp.
class ActiveOdaiController extends Notifier<OdaiBadge?> {
  @override
  OdaiBadge? build() => null;

  void start(OdaiTheme theme) =>
      state = badgeFor(theme, ref.read(clockProvider)());

  void clear() => state = null;
}

final activeOdaiProvider = NotifierProvider<ActiveOdaiController, OdaiBadge?>(
  ActiveOdaiController.new,
);

/// Gives the stamp for the active theme (if any) and clears it. Returns the
/// badge when a stamp was newly given, so the UI can celebrate.
Future<OdaiBadge?> completeActiveOdai(
  ProviderReader read, {
  required StampKind kind,
  String? characterId,
}) async {
  final badge = read(activeOdaiProvider);
  if (badge == null) return null;
  read(activeOdaiProvider.notifier).clear();
  final fresh = await read(stampCardProvider.notifier)
      .award(badge, kind: kind, characterId: characterId);
  return fresh ? badge : null;
}

/// `ref.read` of either a `Ref` or a `WidgetRef`.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);
