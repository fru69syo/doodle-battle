import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Pinch-to-scale / twist-to-rotate / drag state shared by the ARCore view
/// (scale + yaw sent to native) and the かんたん AR sprite (2D transform).
class PlacementTransform {
  PlacementTransform({
    this.scale = 1.0,
    this.rotation = 0.0,
    this.offset = Offset.zero,
    this.minScale = 0.4,
    this.maxScale = 3.0,
  });

  /// Uniform scale relative to the model's natural size.
  double scale;

  /// Screen-space rotation in radians, clockwise positive (Flutter's
  /// ScaleUpdateDetails.rotation convention).
  double rotation;

  /// 2D translation (only used by かんたん AR).
  Offset offset;

  final double minScale;
  final double maxScale;

  double _startScale = 1;
  double _startRotation = 0;

  /// Call on ScaleStartDetails.
  void begin() {
    _startScale = scale;
    _startRotation = rotation;
  }

  /// Call on ScaleUpdateDetails. [scaleFactor] and [rotationDelta] are
  /// cumulative since [begin] (as Flutter reports them); [panDelta] is the
  /// incremental focal point movement.
  void update({
    double scaleFactor = 1,
    double rotationDelta = 0,
    Offset panDelta = Offset.zero,
  }) {
    scale = (_startScale * scaleFactor).clamp(minScale, maxScale);
    rotation = _normalize(_startRotation + rotationDelta);
    offset += panDelta;
  }

  /// Rotation about the model's +Y axis in degrees for the 3D view: a
  /// clockwise twist on screen spins the standee clockwise seen from above,
  /// i.e. a negative rotation around +Y.
  double get yawDegrees => -rotation * 180 / math.pi;

  static double _normalize(double r) {
    const twoPi = 2 * math.pi;
    var v = r % twoPi;
    if (v > math.pi) v -= twoPi;
    return v;
  }
}
