/// Placement math for drawn parts (pure, shared by the editor and the
/// compositor so what the child places is exactly what gets rendered).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../../../domain/cosmetics.dart';

/// 2-D affine map: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
class Affine {
  const Affine(this.a, this.b, this.c, this.d, this.tx, this.ty);

  final double a, b, c, d, tx, ty;

  Offset apply(Offset p) =>
      Offset(a * p.dx + c * p.dy + tx, b * p.dx + d * p.dy + ty);

  double get determinant => a * d - b * c;

  Affine inverse() {
    final det = determinant;
    if (det.abs() < 1e-12) throw StateError('singular transform');
    final ia = d / det, ib = -b / det, ic = -c / det, id = a / det;
    return Affine(ia, ib, ic, id, -(ia * tx + ic * ty), -(ib * tx + id * ty));
  }

  /// Bounding box of the `w × h` rectangle at the origin after mapping.
  Rect boundsOf(double w, double h) {
    final pts = [
      apply(Offset.zero),
      apply(Offset(w, 0)),
      apply(Offset(0, h)),
      apply(Offset(w, h)),
    ];
    var l = pts.first.dx, r = l, t = pts.first.dy, btm = t;
    for (final p in pts.skip(1)) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      btm = math.max(btm, p.dy);
    }
    return Rect.fromLTRB(l, t, r, btm);
  }
}

/// Maps a pixel of the part image (`partW × partH`) to a pixel of the base
/// drawing (`baseW × baseH`) for [t]. [scaleBoost] enlarges the part around
/// its centre (でんせつ shows parts bigger).
Affine partToBase(
  PartTransform t, {
  required num baseW,
  required num baseH,
  required num partW,
  required num partH,
  double scaleBoost = 1,
}) {
  final s =
      t.scale *
      scaleBoost *
      math.max(baseW, baseH) /
      math.max(1, math.max(partW, partH));
  final cos = math.cos(t.rotation), sin = math.sin(t.rotation);
  final a = s * cos, b = s * sin, c = -s * sin, d = s * cos;
  final px = partW / 2, py = partH / 2;
  return Affine(
    a,
    b,
    c,
    d,
    t.cx * baseW - (a * px + c * py),
    t.cy * baseH - (b * px + d * py),
  );
}

/// Default placement of a freshly drawn part of [type]; [index] nudges
/// repeated parts so they don't stack exactly.
PartTransform defaultPlacement(PartType type, {int index = 0}) {
  final nudge = 0.08 * index;
  return switch (type) {
    PartType.hat => PartTransform(cx: 0.5 + nudge, cy: 0.02, scale: 0.5),
    PartType.horn => PartTransform(cx: 0.5 + nudge, cy: 0.04, scale: 0.3),
    PartType.wings => PartTransform(
      cx: 0.5,
      cy: 0.4 + nudge,
      scale: 1.0,
      behind: true,
    ),
    PartType.tail => PartTransform(
      cx: 0.92,
      cy: 0.75 - nudge,
      scale: 0.45,
      behind: true,
    ),
    PartType.weapon => PartTransform(
      cx: 0.98,
      cy: 0.55 - nudge,
      scale: 0.55,
      rotation: 0.3,
    ),
    PartType.accessory => PartTransform(cx: 0.5 + nudge, cy: 0.6, scale: 0.35),
  };
}

/// Where the base drawing and the parts sit inside the editor canvas. The
/// base is centred and takes [baseFraction] of the canvas so parts can
/// stick out on every side.
class EditorGeometry {
  EditorGeometry({
    required this.canvas,
    required this.baseW,
    required this.baseH,
    this.baseFraction = 0.55,
  });

  final Size canvas;
  final int baseW;
  final int baseH;
  final double baseFraction;

  /// Canvas pixels per base pixel.
  double get scale =>
      baseFraction *
      math.min(canvas.width, canvas.height) /
      math.max(1, math.max(baseW, baseH));

  Rect get baseRect {
    final w = baseW * scale, h = baseH * scale;
    return Rect.fromLTWH((canvas.width - w) / 2, (canvas.height - h) / 2, w, h);
  }

  Offset partCenter(PartTransform t) {
    final r = baseRect;
    return Offset(r.left + t.cx * r.width, r.top + t.cy * r.height);
  }

  /// On-canvas size of a `partW × partH` part (before rotation).
  Size partSize(PartTransform t, int partW, int partH) {
    final longest = t.scale * math.max(baseW, baseH) * scale;
    final k = longest / math.max(1, math.max(partW, partH));
    return Size(partW * k, partH * k);
  }

  /// Applies one gesture update (pan in canvas pixels, pinch factor, twist
  /// in radians) and clamps to the editable range.
  PartTransform applyGesture(
    PartTransform t, {
    Offset pan = Offset.zero,
    double scaleFactor = 1,
    double rotationDelta = 0,
  }) {
    final r = baseRect;
    return t
        .copyWith(
          cx: t.cx + pan.dx / r.width,
          cy: t.cy + pan.dy / r.height,
          scale: t.scale * scaleFactor,
          rotation: t.rotation + rotationDelta,
        )
        .clamped();
  }

  /// Index of the top-most part under [p] (front layer first, later parts
  /// first), or null. Uses each part's rotated rectangle.
  int? hitTest(Offset p, List<(PartTransform, int, int)> parts) {
    final order = [
      for (var i = parts.length - 1; i >= 0; i--)
        if (!parts[i].$1.behind) i,
      for (var i = parts.length - 1; i >= 0; i--)
        if (parts[i].$1.behind) i,
    ];
    for (final i in order) {
      final (t, w, h) = parts[i];
      final size = partSize(t, w, h);
      final local = p - partCenter(t);
      final cos = math.cos(-t.rotation), sin = math.sin(-t.rotation);
      final x = local.dx * cos - local.dy * sin;
      final y = local.dx * sin + local.dy * cos;
      // A little slack so small parts are easy to grab with a finger.
      final hw = math.max(size.width / 2, 24),
          hh = math.max(size.height / 2, 24);
      if (x.abs() <= hw && y.abs() <= hh) return i;
    }
    return null;
  }
}
