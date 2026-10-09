import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:image/image.dart' as img;

import '../glb/standee_glb.dart';
import '../glb/standee_textures.dart';

/// Maps viewport (screen) coordinates onto a camera photo that is shown with
/// `BoxFit.cover` (centred) in that viewport.
class CoverMapping {
  CoverMapping({required this.viewport, required this.photo})
    : scale = math.max(
        viewport.width / photo.width,
        viewport.height / photo.height,
      );

  final Size viewport;
  final Size photo;

  /// Viewport pixels per photo pixel.
  final double scale;

  /// Part of the photo visible in the viewport, in photo pixels.
  Rect get visibleRect {
    final w = viewport.width / scale;
    final h = viewport.height / scale;
    return Rect.fromLTWH((photo.width - w) / 2, (photo.height - h) / 2, w, h);
  }

  /// Viewport point → point in the cropped photo ([visibleRect] origin).
  Offset toCropped(Offset viewportPoint) => viewportPoint / scale;
}

/// Where the standee sits in the viewport for かんたん AR.
class SpritePlacement {
  const SpritePlacement({
    required this.anchor,
    required this.pixelScale,
    required this.rotation,
  });

  /// Bottom-centre of the sprite (its feet), viewport logical pixels.
  final Offset anchor;

  /// Viewport logical pixels per sprite texture pixel.
  final double pixelScale;

  /// Clockwise rotation in radians around [anchor].
  final double rotation;
}

/// Input for [composeArPhoto] (sendable to an isolate).
class ArPhotoRequest {
  const ArPhotoRequest({
    required this.photoBytes,
    required this.viewport,
    required this.placement,
    required this.spritePng,
    this.auraPng,
    this.sparkles = false,
    this.jpegQuality = 90,
  });

  /// JPEG/PNG from the camera.
  final Uint8List photoBytes;
  final Size viewport;
  final SpritePlacement placement;
  final Uint8List spritePng;
  final Uint8List? auraPng;
  final bool sparkles;
  final int jpegQuality;
}

Future<Uint8List> composeArPhotoInBackground(ArPhotoRequest request) =>
    Isolate.run(() => composeArPhoto(request));

/// Crops the camera photo to what the viewport showed and draws the
/// standee layer (aura + paper sprite + sparkles) where the user put it.
Uint8List composeArPhoto(ArPhotoRequest r) {
  final decoded = img.decodeImage(r.photoBytes);
  if (decoded == null) throw const FormatException('cannot decode photo');
  var photo = img.bakeOrientation(decoded);
  if (photo.numChannels != 3 && photo.numChannels != 4) {
    photo = photo.convert(numChannels: 3);
  }

  final mapping = CoverMapping(
    viewport: r.viewport,
    photo: Size(photo.width.toDouble(), photo.height.toDouble()),
  );
  final vis = mapping.visibleRect;
  final out = img
      .copyCrop(
        photo,
        x: vis.left.round().clamp(0, photo.width - 1),
        y: vis.top.round().clamp(0, photo.height - 1),
        width: vis.width.round().clamp(1, photo.width),
        height: vis.height.round().clamp(1, photo.height),
      )
      .convert(numChannels: 4);

  final sprite = img.decodePng(r.spritePng)!;
  final aura = r.auraPng == null ? null : img.decodePng(r.auraPng!);
  final layer = buildStandeeLayer(
    sprite: sprite,
    aura: aura,
    sparkles: r.sparkles,
  );

  // Layer size in output pixels.
  final k = r.placement.pixelScale / mapping.scale;
  final lw = math.max(1, (layer.width * k).round());
  final lh = math.max(1, (layer.height * k).round());
  final resized = img.copyResize(
    layer,
    width: lw,
    height: lh,
    interpolation: img.Interpolation.linear,
  );

  // Rotate around the feet: pad so the bottom-centre is the image centre.
  final padded = img.Image(width: lw, height: lh * 2, numChannels: 4);
  img.compositeImage(padded, resized, dstX: 0, dstY: 0);
  final angleDeg = r.placement.rotation * 180 / math.pi;
  final rotated = angleDeg.abs() < 0.01
      ? padded
      : img.copyRotate(
          padded,
          angle: angleDeg,
          interpolation: img.Interpolation.linear,
        );

  final feet = mapping.toCropped(r.placement.anchor);
  img.compositeImage(
    out,
    rotated,
    dstX: (feet.dx - rotated.width / 2).round(),
    dstY: (feet.dy - rotated.height / 2).round(),
  );
  return img.encodeJpg(out.convert(numChannels: 3), quality: r.jpegQuality);
}

/// Sprite with its effect margin: aura behind, sparkles around. The sprite's
/// bottom-centre is the layer's bottom-centre.
img.Image buildStandeeLayer({
  required img.Image sprite,
  img.Image? aura,
  bool sparkles = false,
}) {
  final m = standeeEffectMarginPx(sprite.width, sprite.height);
  final w = sprite.width + 2 * m;
  final h = sprite.height + m;
  final layer = img.Image(width: w, height: h, numChannels: 4);
  if (aura != null) {
    img.compositeImage(layer, aura, dstW: w, dstH: h);
  }
  img.compositeImage(layer, sprite, dstX: m, dstY: m);
  if (sparkles) {
    final star = buildSparkleTexture(
      size: math.max(8, (sprite.height * 0.14).round()),
    );
    for (final p in standeeSparkleLayout) {
      final cx = m + sprite.width / 2 + p.$1 * sprite.width / 2;
      final cy = m + sprite.height - p.$2 * sprite.height;
      img.compositeImage(
        layer,
        star,
        dstX: (cx - star.width / 2).round(),
        dstY: (cy - star.height / 2).round(),
      );
    }
  }
  return layer;
}
