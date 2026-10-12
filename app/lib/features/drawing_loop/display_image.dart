/// The picture a character is shown with everywhere on this device
/// (ずかん, battle, AR standee, cards, video): the base drawing composited
/// with its drawn parts. Online snapshots keep using only the base drawing
/// (`CharacterRepository.readImage`).
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_state.dart';
import '../../data/drawing_loop_storage.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/cosmetics.dart';
import 'parts/composite.dart';

/// Runs the compositor off the UI isolate. Tests override it with a
/// synchronous version (isolates don't run inside `testWidgets`' fake
/// async zone).
typedef CompositeRunner = Future<CompositeImage> Function(CompositeRequest r);

final compositeRunnerProvider = Provider<CompositeRunner>(
  (ref) =>
      (r) => Isolate.run(() => renderComposite(r)),
);

/// Identifies one look of a character: its id and a signature of
/// everything the composite depends on ('' = no parts → base drawing).
typedef DisplayImageKey = (String id, String signature);

/// Signature of the parts and evolution stage of [c] ('' without parts).
String displaySignature(CharacterV2 c) {
  if (c.cosmetics.parts.isEmpty) return '';
  final json = jsonEncode({
    'v': 1,
    'stage': c.stage.name,
    'element': c.element.name,
    'parts': [for (final p in c.cosmetics.parts) p.toJson()],
  });
  return sha1.convert(utf8.encode(json)).toString().substring(0, 16);
}

DisplayImageKey displayKeyOf(CharacterV2 c) => (c.id, displaySignature(c));

/// Asset name of the cached composite with [signature].
String displayAssetName(String signature) => 'display_$signature';

class DisplayImageService {
  DisplayImageService(this._ref);
  final Ref _ref;

  DrawingLoopStorage get _store => _ref.read(drawingLoopStorageProvider);

  /// PNG to show for [c]: the base drawing when it has no parts, otherwise
  /// the cached composite (rendered and cached on first use, e.g. after the
  /// character evolves). Null when the base drawing is missing.
  Future<Uint8List?> displayImageFor(CharacterV2 c) async {
    final base = await _ref.read(characterRepositoryProvider).readImage(c.id);
    if (base == null) return null;
    final sig = displaySignature(c);
    if (sig.isEmpty) return base;
    final name = displayAssetName(sig);
    final cached = await _store.readAsset(c.id, name);
    if (cached != null) return cached;
    final partPngs = <String, Uint8List>{};
    for (final p in c.cosmetics.parts) {
      final png = await _store.readAsset(c.id, p.assetName);
      if (png != null) partPngs[p.id] = png;
    }
    if (partPngs.isEmpty) return base;
    final CompositeImage composite;
    try {
      composite = await _ref.read(compositeRunnerProvider)(
        compositeRequestFor(
          c,
          base,
          partPngs,
          glowArgb: AppColors.element(c.element).toARGB32(),
        ),
      );
    } on Object {
      return base; // never lose the picture over a cosmetic
    }
    // Keep only the newest composite.
    for (final old in await _store.listAssets(c.id)) {
      if (old.startsWith('display_') && old != name) {
        await _store.deleteAsset(c.id, old);
      }
    }
    await _store.writeAsset(c.id, name, composite.png);
    return composite.png;
  }

  /// Deletes cached composites of [characterId] (e.g. after the last part
  /// was removed).
  Future<void> clearCache(String characterId) async {
    for (final old in await _store.listAssets(characterId)) {
      if (old.startsWith('display_')) {
        await _store.deleteAsset(characterId, old);
      }
    }
  }

  /// Drawn effect PNG of [move], or null (→ default effect).
  Future<Uint8List?> effectImageFor(CharacterV2 c, DrawnMove move) async {
    final asset = c.cosmetics.effects[move];
    return asset == null ? null : _store.readAsset(c.id, asset);
  }
}

final displayImageServiceProvider = Provider<DisplayImageService>(
  DisplayImageService.new,
);

/// Display picture by [DisplayImageKey] (see [displayKeyOf]).
final characterDisplayImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, DisplayImageKey>((ref, key) async {
      final (id, sig) = key;
      if (sig.isEmpty) return ref.watch(characterImageProvider(id).future);
      final c = ref.read(characterByIdProvider(id));
      if (c == null) return ref.watch(characterImageProvider(id).future);
      return ref.read(displayImageServiceProvider).displayImageFor(c);
    });

/// A drawing-loop asset PNG (part or effect) by (character id, asset name).
final loopAssetProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, String)>(
      (ref, key) =>
          ref.read(drawingLoopStorageProvider).readAsset(key.$1, key.$2),
    );

/// Drawn effects of [c] that have loaded (watch in build).
Map<DrawnMove, Uint8List> watchMoveEffects(WidgetRef ref, CharacterV2 c) => {
  for (final e in c.cosmetics.effects.entries)
    e.key: ?ref.watch(loopAssetProvider((c.id, e.value))).value,
};
