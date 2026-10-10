import 'dart:typed_data';

/// The "Before" picture of a character for the Before/After video
/// (SPEC §11.2-1, docs/VIDEO.md): the perspective-cropped sheet of paper the
/// drawing was made on. Only the paper region is kept — never the full
/// camera frame — as a JPEG with the longest side ≤ 1280 px. Stored on the
/// device only and deleted together with its character.
class BeforePhoto {
  const BeforePhoto({required this.jpeg, this.inkRect});

  final Uint8List jpeg;

  /// Where the drawing (its cut-out) sits on the paper, normalised to
  /// 0..1 of the photo (left, top, width, height). Lets the video lift the
  /// character off the exact spot it was drawn. Null when unknown.
  final NormRect? inkRect;

  /// Sidecar metadata (`<id>.json`).
  Map<String, Object?> metaJson() => {
    'version': 1,
    if (inkRect != null) 'inkRect': inkRect!.toJson(),
  };

  static NormRect? inkRectFromMeta(Map<String, Object?>? meta) {
    final r = meta?['inkRect'];
    if (r is! List || r.length != 4) return null;
    try {
      return NormRect.fromJson(r);
    } on Object {
      return null;
    }
  }
}

/// Rectangle in normalised (0..1) image coordinates.
class NormRect {
  const NormRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  List<double> toJson() => [left, top, width, height];

  factory NormRect.fromJson(List<Object?> j) {
    double d(int i) => (j[i]! as num).toDouble().clamp(0.0, 1.0);
    return NormRect(d(0), d(1), d(2), d(3));
  }

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'NormRect($left, $top, $width, $height)';
}
