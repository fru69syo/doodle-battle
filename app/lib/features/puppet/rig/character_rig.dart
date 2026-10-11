import 'dart:convert';
import 'dart:math' as math;

/// A 2D point in drawing pixels (the cut-out PNG's coordinate system, y
/// down). Kept separate from `dart:ui` so rigging runs in isolates and in
/// pure-Dart tests.
class P2 {
  const P2(this.x, this.y);
  final double x, y;

  P2 operator +(P2 o) => P2(x + o.x, y + o.y);
  P2 operator -(P2 o) => P2(x - o.x, y - o.y);
  P2 operator *(double s) => P2(x * s, y * s);
  double get length => math.sqrt(x * x + y * y);
  double dist(P2 o) => (this - o).length;
  P2 lerp(P2 o, double t) => P2(x + (o.x - x) * t, y + (o.y - y) * t);
  bool get isFinite => x.isFinite && y.isFinite;

  /// One decimal is plenty (sub-pixel) and keeps the JSON small.
  List<num> toJson() => [_r(x), _r(y)];

  static P2 fromJson(Object? j) {
    if (j is! List || j.length != 2 || j[0] is! num || j[1] is! num) {
      throw const FormatException('point');
    }
    return P2((j[0] as num).toDouble(), (j[1] as num).toDouble());
  }

  static num _r(double v) {
    final r = (v * 10).roundToDouble() / 10;
    return r == r.roundToDouble() ? r.round() : r;
  }

  @override
  bool operator ==(Object other) => other is P2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// What a limb is, which decides how clips move it.
enum LimbKind {
  head,
  arm,
  leg,

  /// A horizontal appendage on the side opposite the head (animals), or a
  /// drawn tail part.
  tail,

  /// Anything else that sticks out (ears, antennae, hair, a hat...):
  /// secondary "jiggle" motion only.
  extra,

  /// Drawn wings: flap.
  wing,

  /// Something held (a drawn sword, a wand): follows the hand it is
  /// attached to.
  item;

  /// Short JSON code.
  String get code => switch (this) {
    head => 'h',
    arm => 'a',
    leg => 'l',
    tail => 't',
    extra => 'x',
    wing => 'w',
    item => 'i',
  };

  static LimbKind? fromCode(Object? c) {
    for (final k in values) {
      if (k.code == c || k.name == c) return k;
    }
    return null;
  }

  /// Kinds a child can add / remove in the joint editor.
  bool get editable => this != extra;
}

/// One limb as a 2-segment chain base → mid → tip (a head is base → tip;
/// its mid is the midpoint).
class RigLimb {
  RigLimb(
    this.kind,
    this.base,
    this.mid,
    this.tip, {
    this.edited = false,
    this.attach,
    this.part,
  });

  LimbKind kind;
  P2 base, mid, tip;

  /// True when a person placed the tip in the joint editor.
  bool edited;

  /// Index of the limb this one hangs from (a hat on the head, a sword in a
  /// hand); null = the body. Always smaller than this limb's own index.
  int? attach;

  /// Id of the drawn part (docs/LOOP.md) this limb animates, if any.
  String? part;

  Map<String, Object?> toJson() => {
    'k': kind.code,
    'b': base.toJson(),
    if (kind != LimbKind.head) 'm': mid.toJson(),
    't': tip.toJson(),
    if (edited) 'e': 1,
    'p': ?attach,
    'd': ?part,
  };

  static RigLimb fromJson(Map<String, Object?> j) {
    final kind = LimbKind.fromCode(j['k'] ?? j['kind']);
    if (kind == null) throw const FormatException('limb kind');
    final base = P2.fromJson(j['b'] ?? j['base']);
    final tip = P2.fromJson(j['t'] ?? j['tip']);
    final m = j['m'] ?? j['mid'];
    final attach = j['p'];
    final part = j['d'];
    if (attach != null && attach is! int) throw const FormatException('p');
    if (part != null && (part is! String || part.length > 40)) {
      throw const FormatException('d');
    }
    return RigLimb(
      kind,
      base,
      m == null ? base.lerp(tip, 0.5) : P2.fromJson(m),
      tip,
      edited: j['e'] == 1 || j['edited'] == true,
      attach: attach as int?,
      part: part as String?,
    );
  }

  RigLimb copy() => RigLimb(
    kind,
    base,
    mid,
    tip,
    edited: edited,
    attach: attach,
    part: part,
  );
}

/// How a rig was made.
enum RigSource {
  /// Auto-rigged from the silhouette (and the picture's own lines).
  auto,

  /// Auto-rigged with the in-app drawing tool's strokes.
  strokes,

  /// Fixed by a person in the joint editor.
  edited,
}

/// The rig stored with a character. Coordinates are in the cut-out PNG's
/// pixels, so the same rig works at any display size. It travels with the
/// character record (and to an online opponent's phone), so it is small
/// (≤ [maxJsonBytes]), versioned and validated: anything unexpected is
/// rejected and the drawing is auto-rigged again.
class CharacterRig {
  CharacterRig({
    required this.width,
    required this.height,
    required this.root,
    required this.chest,
    required this.limbs,
    this.ground,
    this.source = RigSource.auto,
  });

  /// JSON schema version. v1 was the spike's format (still readable).
  static const version = 2;
  static const maxJsonBytes = 2048;
  static const maxLimbs = 12;

  final double width, height;

  /// Pivot of the body (pelvis for figures with legs, the bottom of the
  /// body for blobs).
  P2 root;

  /// Where arms and head hang from (== [root] for a blob).
  P2 chest;
  final List<RigLimb> limbs;

  /// y of the feet / bottom (drawing pixels). Defaults to the lowest leg.
  double? ground;

  RigSource source;

  bool get isBlob => limbs.isEmpty;

  Iterable<RigLimb> of(LimbKind k) => limbs.where((l) => l.kind == k);
  RigLimb? get head => of(LimbKind.head).firstOrNull;

  /// The drawing's own facing: +1 right, −1 left, 0 frontal. A head (or a
  /// tail on the other side) that is clearly off-centre means a profile
  /// drawing (animals, cars...); frontal drawings are never mirrored.
  int get facing {
    final h = head;
    if (h != null) {
      final dx = (h.tip.x - root.x) / width;
      if (dx.abs() > 0.18) return dx > 0 ? 1 : -1;
    }
    final t = of(LimbKind.tail).where((l) => l.part == null).firstOrNull;
    if (t != null) {
      final dx = (t.tip.x - root.x) / width;
      if (dx.abs() > 0.18) return dx > 0 ? -1 : 1;
    }
    return 0;
  }

  double get groundY {
    if (ground != null) return ground!;
    var g = root.y;
    for (final l in limbs) {
      if (l.kind == LimbKind.leg) g = math.max(g, l.tip.y);
    }
    return g;
  }

  CharacterRig copy({RigSource? source}) => CharacterRig(
    width: width,
    height: height,
    root: root,
    chest: chest,
    limbs: [for (final l in limbs) l.copy()],
    ground: ground,
    source: source ?? this.source,
  );

  /// Same rig with every point moved by ([dx], [dy]) and the frame grown by
  /// 2·[pad] (e.g. the sticker border, or a composite canvas).
  CharacterRig shifted(double dx, double dy, {double padW = 0, double padH = 0}) {
    P2 s(P2 p) => P2(p.x + dx, p.y + dy);
    return CharacterRig(
      width: width + padW,
      height: height + padH,
      root: s(root),
      chest: s(chest),
      limbs: [
        for (final l in limbs)
          RigLimb(
            l.kind,
            s(l.base),
            s(l.mid),
            s(l.tip),
            edited: l.edited,
            attach: l.attach,
            part: l.part,
          ),
      ],
      ground: ground == null ? null : ground! + dy,
      source: source,
    );
  }

  Map<String, Object?> toJson() => {
    'v': version,
    'size': [P2._r(width), P2._r(height)],
    'root': root.toJson(),
    'chest': chest.toJson(),
    if (ground != null) 'ground': P2._r(ground!),
    'limbs': [for (final l in limbs) l.toJson()],
    'src': source.name,
  };

  /// Compact JSON string (what is stored and sent).
  String encode() => jsonEncode(toJson());

  /// Parses and validates; throws [FormatException] on anything unexpected
  /// (unknown version, out-of-range points, too many limbs, attach cycles,
  /// too large). Use [tryDecode] to fall back to auto-rigging.
  static CharacterRig fromJson(Map<String, Object?> j) {
    final v = j['v'];
    if (v != 1 && v != version) throw FormatException('rig version $v');
    final size = j['size'];
    if (size is! List || size.length != 2) throw const FormatException('size');
    final w = (size[0] as num).toDouble(), h = (size[1] as num).toDouble();
    if (!(w >= 1 && h >= 1 && w <= 4096 && h <= 4096)) {
      throw const FormatException('size range');
    }
    final rawLimbs = j['limbs'];
    if (rawLimbs is! List || rawLimbs.length > maxLimbs) {
      throw const FormatException('limbs');
    }
    final limbs = <RigLimb>[
      for (final l in rawLimbs)
        if (l is Map)
          RigLimb.fromJson(l.cast<String, Object?>())
        else
          throw const FormatException('limb'),
    ];
    final src = j['src'] ?? j['source'];
    final rig = CharacterRig(
      width: w,
      height: h,
      root: P2.fromJson(j['root']),
      chest: P2.fromJson(j['chest']),
      ground: (j['ground'] as num?)?.toDouble(),
      limbs: limbs,
      source: RigSource.values.firstWhere(
        (s) => s.name == src,
        orElse: () => RigSource.auto,
      ),
    );
    final problem = rig.validate();
    if (problem != null) throw FormatException(problem);
    return rig;
  }

  /// Null when [json] is missing, too large or invalid.
  static CharacterRig? tryDecode(String? json) {
    if (json == null || json.isEmpty || json.length > maxJsonBytes) return null;
    try {
      final j = jsonDecode(json);
      if (j is! Map) return null;
      return fromJson(j.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  /// A reason the rig is unusable, or null. Points may lie a little outside
  /// the picture (a dragged handle), but not far.
  String? validate() {
    bool ok(P2 p) =>
        p.isFinite &&
        p.x >= -0.5 * width &&
        p.x <= 1.5 * width &&
        p.y >= -0.5 * height &&
        p.y <= 1.5 * height;
    if (!ok(root) || !ok(chest)) return 'body out of range';
    if (ground != null && !(ground! >= -0.5 * height && ground! <= 1.5 * height)) {
      return 'ground out of range';
    }
    if (limbs.length > maxLimbs) return 'too many limbs';
    for (final (i, l) in limbs.indexed) {
      if (!ok(l.base) || !ok(l.mid) || !ok(l.tip)) return 'limb $i range';
      final a = l.attach;
      if (a != null) {
        if (a < 0 || a >= i) return 'limb $i attach';
        final k = limbs[a].kind;
        if (k != LimbKind.head && k != LimbKind.arm && k != LimbKind.extra) {
          return 'limb $i attach kind';
        }
      }
    }
    if (utf8.encode(encode()).length > maxJsonBytes) return 'too large';
    return null;
  }
}

/// A bone of the deformation skeleton derived from a [CharacterRig].
class Bone {
  Bone(this.name, this.parent, this.from, this.to, {this.limb, this.segment});
  final String name;

  /// Index of the parent bone, or −1 for the global (root) transform.
  final int parent;

  /// Pivot (rest) and end point (rest), drawing pixels.
  final P2 from, to;

  /// Limb index in [CharacterRig.limbs] and segment (0 upper, 1 lower).
  final int? limb;
  final int? segment;

  /// Whether vertices are bound to this bone (the pelvis is only a
  /// transform node that legs and tails hang from).
  bool get skinned => name != 'pelvis';

  double get restAngle => math.atan2(to.y - from.y, to.x - from.x);
}

/// Bones for a rig: pelvis (0), body (1), then 1 bone per head / 2 per
/// other limb. Legs and tails hang from the pelvis so they stay planted
/// when the body leans; arms, head, wings and extras hang from the body,
/// or from the limb they are attached to (a hat follows the head).
List<Bone> bonesOf(CharacterRig rig) {
  final bones = <Bone>[
    Bone('pelvis', -1, rig.root, rig.root - const P2(0, 1)),
    Bone(
      'body',
      0,
      rig.root,
      rig.chest.dist(rig.root) < 1 ? rig.root - const P2(0, 1) : rig.chest,
    ),
  ];
  // Last bone of each limb (attach target).
  final endBone = <int>[];
  for (final (i, l) in rig.limbs.indexed) {
    var parent = l.kind == LimbKind.leg || l.kind == LimbKind.tail ? 0 : 1;
    final a = l.attach;
    if (a != null && a >= 0 && a < endBone.length) parent = endBone[a];
    if (l.kind == LimbKind.head || l.kind == LimbKind.item) {
      bones.add(Bone('${l.kind.name}$i', parent, l.base, l.tip, limb: i, segment: 0));
      endBone.add(bones.length - 1);
      continue;
    }
    final upper = bones.length;
    bones.add(
      Bone('${l.kind.name}${i}a', parent, l.base, l.mid, limb: i, segment: 0),
    );
    bones.add(
      Bone('${l.kind.name}${i}b', upper, l.mid, l.tip, limb: i, segment: 1),
    );
    endBone.add(bones.length - 1);
  }
  return bones;
}
