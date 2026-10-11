import 'dart:math' as math;

/// A 2D point in drawing pixels (the cut-out PNG's coordinate system,
/// y down). Kept separate from `dart:ui` so the rig runs in isolates and
/// pure-Dart tests.
class V2 {
  const V2(this.x, this.y);
  final double x, y;

  V2 operator +(V2 o) => V2(x + o.x, y + o.y);
  V2 operator -(V2 o) => V2(x - o.x, y - o.y);
  V2 operator *(double s) => V2(x * s, y * s);
  double get length => math.sqrt(x * x + y * y);
  double dist(V2 o) => (this - o).length;
  V2 lerp(V2 o, double t) => V2(x + (o.x - x) * t, y + (o.y - y) * t);

  List<double> toJson() => [_r(x), _r(y)];
  static V2 fromJson(Object? j) {
    final l = j! as List;
    return V2((l[0] as num).toDouble(), (l[1] as num).toDouble());
  }

  static double _r(double v) => (v * 10).roundToDouble() / 10;

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// What a limb is, which decides how clips move it.
enum LimbKind {
  head,
  arm,
  leg,

  /// A horizontal appendage on the side opposite the head (animals).
  tail,

  /// Anything else that sticks out (ears, antennae, hair, a sword...):
  /// secondary "jiggle" motion only.
  extra,
}

/// One limb as a 2-segment chain base → mid → tip (a head is base → tip;
/// its mid is the midpoint).
class RigLimb {
  RigLimb(this.kind, this.base, this.mid, this.tip);

  LimbKind kind;
  V2 base, mid, tip;

  /// True when a person placed the tip in the joint editor.
  bool edited = false;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'base': base.toJson(),
    'mid': mid.toJson(),
    'tip': tip.toJson(),
    if (edited) 'edited': true,
  };

  static RigLimb fromJson(Map<String, Object?> j) => RigLimb(
    LimbKind.values.byName(j['kind']! as String),
    V2.fromJson(j['base']),
    V2.fromJson(j['mid']),
    V2.fromJson(j['tip']),
  )..edited = j['edited'] == true;

  RigLimb copy() => RigLimb(kind, base, mid, tip)..edited = edited;
}

/// The rig stored with a character (≈ 0.5–1 KB of JSON). Coordinates are
/// in the cut-out PNG's pixels, so the same rig works at any display size.
/// It is also what an online opponent needs to animate your character, so
/// it travels with the character record (see docs/V2_25D_TECH.md §4).
class CharacterRig {
  CharacterRig({
    required this.width,
    required this.height,
    required this.root,
    required this.chest,
    required this.limbs,
    this.ground,
    this.source = 'auto',
  });

  static const version = 1;

  final double width, height;

  /// Pivot of the body (pelvis for figures with legs, the bottom of the
  /// body for blobs).
  V2 root;

  /// Where arms and head hang from (== [root] for a blob).
  V2 chest;
  final List<RigLimb> limbs;

  /// y of the feet / bottom (drawing pixels). Defaults to the lowest tip.
  double? ground;

  /// 'auto' or 'edited'.
  String source;

  bool get isBlob => limbs.isEmpty;

  Iterable<RigLimb> of(LimbKind k) => limbs.where((l) => l.kind == k);
  RigLimb? get head => of(LimbKind.head).firstOrNull;

  /// The drawing's own facing: +1 right, −1 left, 0 frontal. A head (or
  /// a tail on the other side) that is clearly off-centre means a profile
  /// drawing (animals, cars...); frontal drawings are never mirrored.
  int get facing {
    final h = head;
    if (h != null) {
      final dx = (h.tip.x - root.x) / width;
      if (dx.abs() > 0.18) return dx > 0 ? 1 : -1;
    }
    final t = of(LimbKind.tail).firstOrNull;
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

  CharacterRig copy() => CharacterRig(
    width: width,
    height: height,
    root: root,
    chest: chest,
    limbs: [for (final l in limbs) l.copy()],
    ground: ground,
    source: source,
  );

  Map<String, Object?> toJson() => {
    'v': version,
    'size': [width, height],
    'root': root.toJson(),
    'chest': chest.toJson(),
    if (ground != null) 'ground': V2._r(ground!),
    'limbs': [for (final l in limbs) l.toJson()],
    'source': source,
  };

  static CharacterRig fromJson(Map<String, Object?> j) {
    if (j['v'] != version) {
      throw FormatException('unsupported rig version ${j['v']}');
    }
    final size = j['size']! as List;
    return CharacterRig(
      width: (size[0] as num).toDouble(),
      height: (size[1] as num).toDouble(),
      root: V2.fromJson(j['root']),
      chest: V2.fromJson(j['chest']),
      ground: (j['ground'] as num?)?.toDouble(),
      limbs: [
        for (final l in j['limbs']! as List)
          RigLimb.fromJson((l as Map).cast<String, Object?>()),
      ],
      source: j['source'] as String? ?? 'auto',
    );
  }
}

/// A bone of the deformation skeleton derived from a [CharacterRig].
class Bone {
  Bone(this.name, this.parent, this.from, this.to, {this.limb, this.segment});
  final String name;

  /// Index of the parent bone, or −1 for the global (root) transform.
  final int parent;

  /// Pivot (rest) and end point (rest), drawing pixels.
  final V2 from, to;

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
/// when the body leans; arms, head and extras hang from the body.
List<Bone> bonesOf(CharacterRig rig) {
  final bones = <Bone>[
    Bone('pelvis', -1, rig.root, rig.root - const V2(0, 1)),
    Bone(
      'body',
      0,
      rig.root,
      rig.chest.dist(rig.root) < 1 ? rig.root - const V2(0, 1) : rig.chest,
    ),
  ];
  for (final (i, l) in rig.limbs.indexed) {
    final parent = l.kind == LimbKind.leg || l.kind == LimbKind.tail ? 0 : 1;
    if (l.kind == LimbKind.head) {
      bones.add(Bone('head$i', parent, l.base, l.tip, limb: i, segment: 0));
      continue;
    }
    final upper = bones.length;
    bones.add(
      Bone('${l.kind.name}${i}a', parent, l.base, l.mid, limb: i, segment: 0),
    );
    bones.add(
      Bone('${l.kind.name}${i}b', upper, l.mid, l.tip, limb: i, segment: 1),
    );
  }
  return bones;
}
