import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../anim/clips.dart';
import '../anim/skinner.dart';
import '../mesh/puppet_mesh.dart';

/// Draws a [PuppetMesh] with `Canvas.drawVertices` + an `ImageShader`
/// of the drawing. This is plain 2D canvas work: it runs on Skia with
/// GLES 2 (Android 7–9) and on Impeller (Android 10+, iOS Metal) alike —
/// no Flutter GPU, no shaders of our own.
class PuppetSprite {
  PuppetSprite._(this.data, this.image)
    : skinner = Skinner(data),
      clip = AnimContext(data.rig, limited: data.simplified),
      pose = Pose(data.rig.limbs.length),
      _paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true
        ..shader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Float64List.fromList([
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
          filterQuality: FilterQuality.medium,
        );

  static Future<PuppetSprite> create(PuppetMesh data) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      data.textureRgba,
      data.texW,
      data.texH,
      ui.PixelFormat.rgba8888,
      c.complete,
    );
    return PuppetSprite._(data, await c.future);
  }

  final PuppetMesh data;
  final ui.Image image;
  final Skinner skinner;
  final AnimContext clip;
  final Pose pose;
  final Paint _paint;

  /// The drawing's own facing (+1 right, −1 left, 0 frontal).
  int get naturalFacing => data.rig.facing;

  /// Height of the drawing in texture pixels (feet to top).
  double get height => data.rig.groundY - _top;
  late final double _top = () {
    var t = double.infinity;
    for (var i = 1; i < data.rest.length; i += 2) {
      if (data.rest[i] < t) t = data.rest[i];
    }
    return t;
  }();
  double get width => data.texW.toDouble();

  /// Placement: the feet point (root.x, groundY) goes to [feet] on screen,
  /// [pxPerUnit] screen px per texture px, mirrored when [mirror].
  Affine placement(Offset feet, double scale, {bool mirror = false}) {
    final r = data.rig;
    return Affine.translate(feet.dx, feet.dy) *
        Affine.scale(mirror ? -scale : scale, scale) *
        Affine.translate(-r.root.x, -r.groundY);
  }

  /// Poses with [clipId] at [t] facing [screenDir] (+1 = opponent to the
  /// right on screen) and draws at [feet] with [scale].
  void draw(
    Canvas canvas,
    Anim clipId,
    double t, {
    required Offset feet,
    required double scale,
    required int screenDir,
    Color? tint,
    double tintAmount = 0,
    double hopPx = 0,
  }) {
    final mirror = prepare(clipId, t, screenDir);
    drawPose(
      canvas,
      placement(feet.translate(0, -hopPx), scale, mirror: mirror),
      tint: tint,
      tintAmount: tintAmount,
    );
  }

  /// Evaluates the clip into [pose]; returns whether to mirror. Mirror
  /// profile drawings so the head points at the opponent; frontal drawings
  /// are never mirrored (no mirrored writing or faces).
  bool prepare(Anim clipId, double t, int screenDir) {
    final nf = naturalFacing;
    final mirror = nf != 0 && nf != screenDir;
    final fwd = mirror ? -screenDir : screenDir;
    evaluateAnim(clipId, t, clip, fwd, pose);
    return mirror;
  }

  void drawPose(
    Canvas canvas,
    Affine place, {
    Color? tint,
    double tintAmount = 0,
  }) {
    skinner.skin(pose, place);
    final v = ui.Vertices.raw(
      VertexMode.triangles,
      skinner.out,
      textureCoordinates: data.rest,
      indices: data.indices,
    );
    if (pose.opacity < 1) {
      _paint.color = Color.fromRGBO(0, 0, 0, pose.opacity);
    }
    _paint.colorFilter = null;
    canvas.drawVertices(v, BlendMode.srcOver, _paint);
    final flash = pose.flash;
    if (flash > 0 || tintAmount > 0) {
      final c = flash > 0
          ? const Color(0xFFFFFFFF).withValues(alpha: 0.45 * flash)
          : tint!.withValues(alpha: tintAmount);
      _paint.colorFilter = ColorFilter.mode(c, BlendMode.srcATop);
      canvas.drawVertices(v, BlendMode.srcOver, _paint);
      _paint.colorFilter = null;
    }
    v.dispose();
  }

  void dispose() => image.dispose();
}
