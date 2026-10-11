import 'dart:math' as math;

/// Ground-plane camera of the 2.5D stage: a pinhole camera above the
/// ground looking at it at a shallow angle. Only points on the ground are
/// projected; characters are flat cut-outs standing on their feet point and
/// scaled by depth ("2.5D"). x right, z away from the camera, world units
/// ≈ metres.
class StageCamera {
  StageCamera({
    this.x = 0,
    this.z = 0,
    this.zoom = 1,
    this.shakeX = 0,
    this.shakeY = 0,
    this.tilt = 0,
  });

  /// Pan (x), dolly (z), zoom (focal length factor), shake (px), tilt
  /// (vertical framing offset, px).
  double x, z, zoom, shakeX, shakeY, tilt;

  static const camHeight = 1.7;
  static const camBack = 3.4; // camera stands this far in front of z = 0
  static const horizonFrac = 0.33;

  /// Focal length in px for a screen of [w]×[h].
  double focal(double w, double h) => math.min(h * 0.62, w * 1.45) * zoom;

  double depth(double wz) => math.max(0.4, wz - (z - camBack));

  /// Screen position of ground point ([wx], [wz]) and px per world unit.
  (double, double, double) project(double wx, double wz, double w, double h) {
    final f = focal(w, h);
    final d = depth(wz);
    final sx = w / 2 + f * (wx - x) / d + shakeX;
    final sy = h * horizonFrac + f * camHeight / d + shakeY + tilt;
    return (sx, sy, f / d);
  }

  /// Screen y of the horizon.
  double horizon(double h) => h * horizonFrac + shakeY + tilt;

  StageCamera copy() => StageCamera(
    x: x,
    z: z,
    zoom: zoom,
    shakeX: shakeX,
    shakeY: shakeY,
    tilt: tilt,
  );
}
