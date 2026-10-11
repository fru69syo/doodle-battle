import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/drawing_loop_storage.dart';
import '../../domain/character.dart';
import '../draw_canvas/canvas_analysis.dart';
import '../drawing_loop/display_image.dart';
import '../drawing_loop/parts/composite.dart';
import 'puppet_builder.dart';
import 'puppet_look.dart';
import 'puppet_parts.dart';
import 'puppet_store.dart';
import 'render/puppet_view.dart';
import 'rig/character_rig.dart';

/// The puppet of a stored character, ready for [PuppetView] / the battle
/// stage: its picture with the drawn parts (docs/LOOP.md) as extra rigged
/// appendages, the stored (edited) rig or an auto-rig made with the
/// drawing-tool strokes, and the look for its level.
///
/// [lateBloomer] is the engine's hidden flag; it only becomes the
/// [PuppetLook] here and is never shown.
Future<PuppetSpec?> characterPuppetSpec(
  Ref ref,
  Character c, {
  bool lateBloomer = false,
  PuppetQuality quality = PuppetQuality.high,
}) async {
  final base = await ref.read(characterRepositoryProvider).readImage(c.id);
  if (base == null) return null;
  final store = ref.read(puppetStoreProvider);
  final look = PuppetLook.of(level: c.level, lateBloomer: lateBloomer);
  final stored = CharacterRig.tryDecode(await store.loadRigJson(c.id));
  final strokes = hintStrokesFromRecord(await store.loadStrokesJson(c.id));
  if (c.cosmetics.parts.isEmpty) {
    return PuppetSpec(
      png: base,
      rig: stored,
      strokes: stored == null ? strokes : null,
      look: look,
      quality: quality,
    );
  }
  // With drawn parts: rig the base drawing, then add one limb per part in
  // the composite picture's coordinates.
  final loop = ref.read(drawingLoopStorageProvider);
  final partPngs = <String, Uint8List>{};
  for (final p in c.cosmetics.parts) {
    final png = await loop.readAsset(c.id, p.assetName);
    if (png != null) partPngs[p.id] = png;
  }
  final baseRig =
      stored ??
      await ref.read(puppetBuilderProvider).autoRig(base, strokes: strokes);
  final CompositeImage comp;
  try {
    comp = await ref.read(compositeRunnerProvider)(
      compositeRequestFor(
        c,
        base,
        partPngs,
        glowArgb: AppColors.element(c.element).toARGB32(),
      ),
    );
  } on Object {
    return PuppetSpec(png: base, rig: baseRig, look: look, quality: quality);
  }
  final (bw, bh) = pngSize(base);
  final k = comp.baseRect.width / bw;
  final placements = <PartPlacement>[
    for (final p in c.cosmetics.parts)
      if (partPngs[p.id] case final png?)
        PartPlacement.fromTransform(
          id: p.id,
          type: p.type,
          t: p.transform,
          baseW: bw,
          baseH: bh,
          partW: pngSize(png).$1,
          partH: pngSize(png).$2,
          baseLeft: comp.baseRect.left,
          baseTop: comp.baseRect.top,
          k: k,
          scaleBoost: partScaleBoost(c.stage),
        ),
  ];
  return PuppetSpec(
    png: comp.png,
    rig: rigWithParts(
      baseRig,
      parts: placements,
      compositeW: comp.width.toDouble(),
      compositeH: comp.height.toDouble(),
      baseLeft: comp.baseRect.left,
      baseTop: comp.baseRect.top,
      k: k,
    ),
    look: look,
    quality: quality,
  );
}

/// Width and height from a PNG header (IHDR), or (1, 1).
(int, int) pngSize(Uint8List png) {
  if (png.length < 24) return (1, 1);
  int u32(int o) =>
      png[o] << 24 | png[o + 1] << 16 | png[o + 2] << 8 | png[o + 3];
  return (u32(16), u32(20));
}

/// [characterPuppetSpec] as a provider (character id → spec).
final characterPuppetSpecProvider = FutureProvider.autoDispose
    .family<PuppetSpec?, Character>((ref, c) => characterPuppetSpec(ref, c));
