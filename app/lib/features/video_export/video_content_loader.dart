/// Gathers and decodes everything the video shows (docs/VIDEO.md §3).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../data/before_photo.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/cosmetics.dart';
import '../../domain/cpu_roster_v2.dart';
import '../puppet/render/puppet_sprite.dart';
import 'battle_highlight.dart';
import 'video_composer.dart';

/// Thrown when the video cannot be put together (e.g. no character image).
class VideoContentException implements Exception {
  const VideoContentException(this.message);
  final String message;
  @override
  String toString() => 'VideoContentException: $message';
}

/// Builds the [VideoContent] for [character].
///
/// [displayPng] is the character's display image (with drawn-on parts,
/// `DisplayImageService.displayImageFor`); [originalPng] the plain cut-out
/// of the paper drawing (defaults to [displayPng]). [before] is the stored
/// paper photo; characters made before it was kept get the cut-out on a
/// generated sheet of paper. [moveEffectPngs] are the child's drawn move
/// effects (used as the projectile).
Future<VideoContent> loadVideoContent({
  required CharacterV2 character,
  required Uint8List displayPng,
  required BeforePhoto? before,
  Uint8List? originalPng,
  Map<DrawnMove, Uint8List> moveEffectPngs = const {},
  required CpuRosterV2 roster,
  required Future<Uint8List> Function(String asset) loadAsset,
  Future<PuppetSprite?> Function(Uint8List png, {required bool cpu})?
  puppetOf,
}) async {
  final highlight = scriptBattleHighlight(roster: roster, player: character);
  if (highlight == null) {
    throw const VideoContentException('no battle highlight');
  }
  final charImage = await decodeImage(displayPng);
  final original = originalPng == null || identical(originalPng, displayPng)
      ? charImage
      : await decodeImage(originalPng);
  final effects = <DrawnMove, ui.Image>{};
  for (final e in moveEffectPngs.entries) {
    try {
      effects[e.key] = await decodeImage(e.value);
    } on Object {
      // A broken drawing falls back to the default effect.
    }
  }
  final cpuPng = await loadAsset(highlight.cpu.asset);
  final cpuImage = await decodeImage(cpuPng);
  // 2.5D puppets (docs/PUPPET.md); the flat pictures when building fails.
  PuppetSprite? puppet, cpuPuppet;
  if (puppetOf != null) {
    try {
      puppet = await puppetOf(displayPng, cpu: false);
      cpuPuppet = await puppetOf(cpuPng, cpu: true);
    } on Object {
      puppet = cpuPuppet = null;
    }
  }
  ui.Image? beforeImage;
  NormRect? inkRect;
  if (before != null) {
    try {
      beforeImage = await decodeImage(before.jpeg);
      inkRect = before.inkRect;
    } on Object {
      beforeImage = null;
    }
  }
  if (beforeImage == null) {
    final paper = await paperFallback(original);
    beforeImage = paper.$1;
    inkRect = paper.$2;
  }
  return VideoContent(
    before: beforeImage,
    inkRect: inkRect ?? centeredInkRect(beforeImage, original),
    character: charImage,
    original: identical(original, charImage) ? null : original,
    moveEffects: effects,
    name: character.name,
    element: character.element,
    highlight: highlight,
    cpuImage: cpuImage,
    puppet: puppet,
    cpuPuppet: cpuPuppet,
  );
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Size of the generated paper sheet.
const Size kFallbackPaperSize = Size(900, 1200);

/// Where the cut-out goes on the generated sheet (normalised), fitted into
/// the middle 70 % × 60 %.
NormRect fallbackInkRect(int cutoutW, int cutoutH) {
  final pw = kFallbackPaperSize.width;
  final ph = kFallbackPaperSize.height;
  final s = math.min(pw * 0.7 / cutoutW, ph * 0.6 / cutoutH);
  final w = cutoutW * s / pw;
  final h = cutoutH * s / ph;
  return NormRect(0.5 - w / 2, 0.47 - h / 2, w, h);
}

/// Rect for a drawing centred on [paper] when its position is unknown.
NormRect centeredInkRect(ui.Image paper, ui.Image cutout) {
  final s = math.min(
    paper.width * 0.7 / cutout.width,
    paper.height * 0.6 / cutout.height,
  );
  final w = cutout.width * s / paper.width;
  final h = cutout.height * s / paper.height;
  return NormRect(0.5 - w / 2, 0.5 - h / 2, w, h);
}

/// The cut-out on a plain sheet of drawing paper, for characters that have
/// no stored paper photo.
Future<(ui.Image, NormRect)> paperFallback(ui.Image cutout) async {
  final size = kFallbackPaperSize;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFCFAF3));
  // Faint paper fibres (fixed seed: deterministic).
  final r = math.Random(7);
  final fibre = Paint()
    ..strokeWidth = 1.2
    ..color = const Color(0x0F6B5A3A);
  for (var i = 0; i < 420; i++) {
    final x = r.nextDouble() * size.width;
    final y = r.nextDouble() * size.height;
    final a = r.nextDouble() * math.pi;
    final l = 4 + r.nextDouble() * 10;
    canvas.drawLine(
      Offset(x, y),
      Offset(x + math.cos(a) * l, y + math.sin(a) * l),
      fibre,
    );
  }
  // Soft vignette like a photo.
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.radial(
        size.center(Offset.zero),
        size.longestSide * 0.75,
        [const Color(0x00000000), const Color(0x16000000)],
      ),
  );
  final ink = fallbackInkRect(cutout.width, cutout.height);
  canvas.drawImageRect(
    cutout,
    Rect.fromLTWH(0, 0, cutout.width.toDouble(), cutout.height.toDouble()),
    Rect.fromLTWH(
      ink.left * size.width,
      ink.top * size.height,
      ink.width * size.width,
      ink.height * size.height,
    ),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = rec.endRecording();
  try {
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    return (image, ink);
  } finally {
    picture.dispose();
  }
}
