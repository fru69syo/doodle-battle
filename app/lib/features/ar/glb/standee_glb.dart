import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../ar_effects.dart';
import 'glb_writer.dart';
import 'standee_textures.dart';

/// Options for [buildStandeeGlb].
class StandeeGlbOptions {
  const StandeeGlbOptions({
    this.heightMeters = 0.25,
    this.maxWidthMeters = 0.40,
    this.thicknessMeters = 0.003,
    this.borderFraction = 0.035,
    this.maxTextureSize = 512,
    this.effects = ArEffects.none,
    this.idleBounce = true,
    this.groundShadow = true,
    this.unlit = true,
  });

  /// Height of the standee at scale 1 (SPEC: ~20–30 cm).
  final double heightMeters;

  /// Very wide drawings are shrunk so they are at most this wide.
  final double maxWidthMeters;

  /// Distance between the front and back faces ("paper thickness").
  final double thicknessMeters;

  /// White paper margin around the drawing, relative to its longest side.
  final double borderFraction;

  /// Longest side of the front/back textures (incl. border).
  final int maxTextureSize;

  /// Evolution-stage effects baked into the model.
  final ArEffects effects;

  /// Adds the looping "idle" animation (ぴょこぴょこ hop + squash).
  final bool idleBounce;

  /// Soft blob shadow on the floor under the standee.
  final bool groundShadow;

  /// Use KHR_materials_unlit so drawings keep their colours regardless of
  /// the estimated room lighting.
  final bool unlit;
}

/// Result of [buildStandeeGlb].
class StandeeGlb {
  const StandeeGlb({
    required this.glb,
    required this.widthMeters,
    required this.heightMeters,
    required this.spritePng,
    required this.spriteWidth,
    required this.spriteHeight,
    this.auraPng,
    this.auraMarginPx = 0,
  });

  /// glTF 2.0 binary. Origin at the bottom centre, +Y up, facing +Z.
  final Uint8List glb;

  /// Size of the paper silhouette's bounding box at scale 1.
  final double widthMeters;
  final double heightMeters;

  /// Front texture (drawing on white paper with a cut margin). Used as the
  /// sprite of the かんたん AR fallback.
  final Uint8List spritePng;
  final int spriteWidth;
  final int spriteHeight;

  /// Aura glow texture (if the effects ask for one). It covers the sprite
  /// rectangle extended by [auraMarginPx] sprite pixels on the left, right
  /// and top.
  final Uint8List? auraPng;
  final int auraMarginPx;

  /// Room (sprite px) left/right/top of the sprite used by aura & sparkles.
  int get effectMarginPx => standeeEffectMarginPx(spriteWidth, spriteHeight);
}

/// Name of the looping animation inside the GLB.
const standeeIdleAnimation = 'idle';

/// Runs [buildStandeeGlb] on a background isolate.
Future<StandeeGlb> buildStandeeGlbInBackground(
  Uint8List cutoutPng, {
  StandeeGlbOptions options = const StandeeGlbOptions(),
}) => Isolate.run(() => buildStandeeGlb(cutoutPng, options: options));

/// Builds a "paper standee" GLB from the character's cut-out PNG
/// (transparent background, longest side ≤ 512px).
///
/// Throws [FormatException] when [cutoutPng] is not a decodable PNG.
StandeeGlb buildStandeeGlb(
  Uint8List cutoutPng, {
  StandeeGlbOptions options = const StandeeGlbOptions(),
}) {
  final decoded = img.decodePng(cutoutPng);
  if (decoded == null) {
    throw const FormatException('cutout is not a valid PNG');
  }
  return buildStandeeGlbFromImage(decoded, options: options);
}

/// Same as [buildStandeeGlb] with an already decoded image.
StandeeGlb buildStandeeGlbFromImage(
  img.Image cutout, {
  StandeeGlbOptions options = const StandeeGlbOptions(),
}) {
  final effects = options.effects;
  final tex = StandeeTextures.fromCutout(
    cutout,
    maxTextureSize: options.maxTextureSize,
    borderFraction: options.borderFraction,
    effects: effects,
  );

  // Physical size: fixed height, aspect from the texture, capped width.
  var h = options.heightMeters;
  var w = h * tex.width / tex.height;
  if (w > options.maxWidthMeters) {
    h *= options.maxWidthMeters / w;
    w = options.maxWidthMeters;
  }
  final metersPerPx = h / tex.height;
  final t = options.thicknessMeters;

  final writer = GlbWriter();
  final images = <Map<String, Object?>>[];
  final textures = <Map<String, Object?>>[];
  final materials = <Map<String, Object?>>[];
  final meshes = <Map<String, Object?>>[];
  final nodes = <Map<String, Object?>>[];

  final frontPng = img.encodePng(tex.front, level: 6);

  int addTexture(Uint8List png, String name) {
    final view = writer.addBufferView(png);
    images.add({'name': name, 'bufferView': view, 'mimeType': 'image/png'});
    textures.add({'sampler': 0, 'source': images.length - 1});
    return textures.length - 1;
  }

  int addMaterial(
    String name,
    int texture, {
    required String alphaMode,
    required bool doubleSided,
    bool unlit = true,
  }) {
    materials.add({
      'name': name,
      'pbrMetallicRoughness': {
        'baseColorTexture': {'index': texture},
        'metallicFactor': 0.0,
        'roughnessFactor': 1.0,
      },
      'alphaMode': alphaMode,
      if (alphaMode == 'MASK') 'alphaCutoff': 0.5,
      'doubleSided': doubleSided,
      if (unlit) 'extensions': {'KHR_materials_unlit': <String, Object?>{}},
    });
    return materials.length - 1;
  }

  // Shared vertex data for axis-aligned quads.
  final uvs = writer.addFloatAccessor(const [0, 1, 1, 1, 1, 0, 0, 0], 'VEC2');
  final normalFront = writer.addFloatAccessor(const [
    0,
    0,
    1,
    0,
    0,
    1,
    0,
    0,
    1,
    0,
    0,
    1,
  ], 'VEC3');
  final normalBack = writer.addFloatAccessor(const [
    0,
    0,
    -1,
    0,
    0,
    -1,
    0,
    0,
    -1,
    0,
    0,
    -1,
  ], 'VEC3');
  final normalUp = writer.addFloatAccessor(const [
    0,
    1,
    0,
    0,
    1,
    0,
    0,
    1,
    0,
    0,
    1,
    0,
  ], 'VEC3');
  final idxFront = writer.addIndexAccessor(const [0, 1, 2, 0, 2, 3]);
  final idxBack = writer.addIndexAccessor(const [0, 2, 1, 0, 3, 2]);

  Map<String, Object?> verticalQuad(
    double x0,
    double x1,
    double y0,
    double y1,
    double z,
    int material, {
    bool back = false,
  }) {
    final pos = writer.addFloatAccessor(
      [x0, y0, z, x1, y0, z, x1, y1, z, x0, y1, z],
      'VEC3',
      withBounds: true,
    );
    return {
      'attributes': {
        'POSITION': pos,
        'NORMAL': back ? normalBack : normalFront,
        'TEXCOORD_0': uvs,
      },
      'indices': back ? idxBack : idxFront,
      'material': material,
    };
  }

  // --- Body: front, back and two inner "paper core" layers ----------------
  final frontTex = addTexture(frontPng, 'front');
  final backTex = addTexture(img.encodePng(tex.back, level: 6), 'back');
  final unlit = options.unlit;
  final frontMat = addMaterial(
    'paper_front',
    frontTex,
    alphaMode: 'MASK',
    doubleSided: false,
    unlit: unlit,
  );
  final backMat = addMaterial(
    'paper_back',
    backTex,
    alphaMode: 'MASK',
    doubleSided: false,
    unlit: unlit,
  );
  final edgeMat = addMaterial(
    'paper_edge',
    backTex,
    alphaMode: 'MASK',
    doubleSided: true,
    unlit: unlit,
  );

  final x0 = -w / 2, x1 = w / 2;
  meshes.add({
    'name': 'standee',
    'primitives': [
      verticalQuad(x0, x1, 0, h, t / 2, frontMat),
      verticalQuad(x0, x1, 0, h, -t / 2, backMat, back: true),
      // Inner layers make the cut edge look solid at grazing angles.
      verticalQuad(x0, x1, 0, h, t / 6, edgeMat),
      verticalQuad(x0, x1, 0, h, -t / 6, edgeMat),
    ],
  });
  nodes.add({'name': 'standee'}); // 0: root, children filled below
  nodes.add({'name': 'body', 'mesh': 0}); // 1
  final rootChildren = <int>[1];
  final bodyChildren = <int>[];

  // --- Aura (kagayaki+) ------------------------------------------------------
  Uint8List? auraPng;
  int? auraNode;
  if (tex.aura != null) {
    auraPng = img.encodePng(tex.aura!, level: 6);
    final auraTex = addTexture(auraPng, 'aura');
    final auraMat = addMaterial(
      'aura',
      auraTex,
      alphaMode: 'BLEND',
      doubleSided: true,
    );
    final m = tex.auraMarginPx * metersPerPx;
    meshes.add({
      'name': 'aura',
      'primitives': [verticalQuad(x0 - m, x1 + m, 0, h + m, 0, auraMat)],
    });
    nodes.add({'name': 'aura', 'mesh': meshes.length - 1});
    auraNode = nodes.length - 1;
    bodyChildren.add(auraNode);
  }

  // --- Ground shadow -----------------------------------------------------------
  int? shadowNode;
  if (options.groundShadow) {
    final shadowTex = addTexture(
      img.encodePng(_buildShadowTexture(), level: 6),
      'shadow',
    );
    final shadowMat = addMaterial(
      'shadow',
      shadowTex,
      alphaMode: 'BLEND',
      doubleSided: true,
    );
    final sx = w * 0.62;
    final sz = math.max(0.05, w * 0.3);
    const y = 0.0015; // just above the plane to avoid z-fighting
    final pos = writer.addFloatAccessor(
      [-sx, y, sz, sx, y, sz, sx, y, -sz, -sx, y, -sz],
      'VEC3',
      withBounds: true,
    );
    meshes.add({
      'name': 'shadow',
      'primitives': [
        {
          'attributes': {
            'POSITION': pos,
            'NORMAL': normalUp,
            'TEXCOORD_0': uvs,
          },
          'indices': idxFront,
          'material': shadowMat,
        },
      ],
    });
    nodes.add({'name': 'shadow', 'mesh': meshes.length - 1});
    shadowNode = nodes.length - 1;
    rootChildren.add(shadowNode);
  }

  // --- Sparkles (densetsu) -----------------------------------------------------
  final sparkleNodes = <int>[];
  final sparklePhases = <double>[];
  if (effects.sparkles) {
    final sparkleTex = addTexture(
      img.encodePng(buildSparkleTexture(), level: 6),
      'sparkle',
    );
    final sparkleMat = addMaterial(
      'sparkle',
      sparkleTex,
      alphaMode: 'BLEND',
      doubleSided: true,
    );
    final s = math.max(0.03, h * 0.14) / 2;
    meshes.add({
      'name': 'sparkle',
      'primitives': [verticalQuad(-s, s, -s, s, 0, sparkleMat)],
    });
    final mesh = meshes.length - 1;
    for (final (i, p) in standeeSparkleLayout.indexed) {
      nodes.add({
        'name': 'sparkle_$i',
        'mesh': mesh,
        'translation': [p.$1 * w / 2, p.$2 * h, p.$3],
      });
      sparkleNodes.add(nodes.length - 1);
      sparklePhases.add(i / standeeSparkleLayout.length);
      rootChildren.add(nodes.length - 1);
    }
  }

  nodes[0]['children'] = rootChildren;
  if (bodyChildren.isNotEmpty) nodes[1]['children'] = bodyChildren;

  // --- Idle animation ----------------------------------------------------------
  final animations = <Map<String, Object?>>[];
  final channels = <Map<String, Object?>>[];
  final samplers = <Map<String, Object?>>[];
  if (options.idleBounce || sparkleNodes.isNotEmpty) {
    const frames = 24;
    const duration = 1.2;
    final times = [for (var i = 0; i <= frames; i++) duration * i / frames];
    final input = writer.addFloatAccessor(
      times,
      'SCALAR',
      target: null,
      withBounds: true,
    );

    void channel(int node, String path, List<double> values) {
      final output = writer.addFloatAccessor(values, 'VEC3', target: null);
      samplers.add({
        'input': input,
        'output': output,
        'interpolation': 'LINEAR',
      });
      channels.add({
        'sampler': samplers.length - 1,
        'target': {'node': node, 'path': path},
      });
    }

    final phases = [for (var i = 0; i <= frames; i++) i / frames];
    if (options.idleBounce) {
      final hop = phases.map(idleHop).toList();
      channel(1, 'translation', [
        for (final v in hop) ...[0.0, v * h * 0.06, 0.0],
      ]);
      channel(1, 'scale', [for (final p in phases) ...idleSquash(p)]);
      if (shadowNode != null) {
        channel(shadowNode, 'scale', [
          for (final v in hop) ...[1 - 0.18 * v, 1.0, 1 - 0.18 * v],
        ]);
      }
    }
    if (auraNode != null) {
      channel(auraNode, 'scale', [
        for (final p in phases)
          ...List.filled(3, 1 + 0.05 * math.sin(2 * math.pi * p)),
      ]);
    }
    for (final (i, node) in sparkleNodes.indexed) {
      channel(node, 'scale', [
        for (final p in phases)
          ...List.filled(3, sparkleScale(p + sparklePhases[i])),
      ]);
    }
    animations.add({
      'name': standeeIdleAnimation,
      'channels': channels,
      'samplers': samplers,
    });
  }

  final json = <String, Object?>{
    'asset': {'version': '2.0', 'generator': 'doodle_battle standee_glb 1.0'},
    if (materials.any((m) => m.containsKey('extensions')))
      'extensionsUsed': ['KHR_materials_unlit'],
    'scene': 0,
    'scenes': [
      {
        'name': 'standee',
        'nodes': [0],
      },
    ],
    'nodes': nodes,
    'meshes': meshes,
    'materials': materials,
    'textures': textures,
    'images': images,
    'samplers': [
      {
        'magFilter': 9729, // LINEAR
        'minFilter': 9987, // LINEAR_MIPMAP_LINEAR
        'wrapS': 33071, // CLAMP_TO_EDGE
        'wrapT': 33071,
      },
    ],
    if (animations.isNotEmpty) 'animations': animations,
  };

  return StandeeGlb(
    glb: writer.build(json),
    widthMeters: w,
    heightMeters: h,
    spritePng: frontPng,
    spriteWidth: tex.width,
    spriteHeight: tex.height,
    auraPng: auraPng,
    auraMarginPx: tex.auraMarginPx,
  );
}

/// Hop height (0..1) over one idle cycle [phase] in [0, 1): a quick hop in the
/// first 45%, then rest.
double idleHop(double phase) {
  final p = phase % 1.0;
  if (p >= 0.45) return 0;
  return math.sin(math.pi * p / 0.45);
}

/// Squash & stretch scale (x, y, z) over one idle cycle.
List<double> idleSquash(double phase) {
  final p = phase % 1.0;
  double sy;
  if (p < 0.45) {
    sy = 1 + 0.04 * math.sin(math.pi * p / 0.45); // stretch in the air
  } else if (p < 0.65) {
    sy = 1 - 0.07 * math.sin(math.pi * (p - 0.45) / 0.2); // squash on landing
  } else {
    sy = 1;
  }
  // Preserve volume-ish: widen when squashed.
  final sx = 1 + (1 - sy) * 0.6;
  return [sx, sy, 1];
}

/// Twinkle scale of a sparkle over one cycle.
double sparkleScale(double phase) {
  final s = 0.5 + 0.5 * math.sin(2 * math.pi * phase);
  return 0.15 + 0.85 * s * s;
}

/// Sparkle positions: (x relative to half-width, y relative to height,
/// z metres). Also used by the かんたん AR overlay (x, y only).
const standeeSparkleLayout = <(double, double, double)>[
  (-1.25, 0.85, 0.02),
  (1.2, 0.68, 0.015),
  (-1.05, 0.32, 0.025),
  (1.3, 0.22, -0.01),
  (0.35, 1.12, 0.02),
  (-0.45, 1.06, -0.015),
];

img.Image _buildShadowTexture({int size = 64}) {
  final out = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size * 2 - 1;
      final v = (y + 0.5) / size * 2 - 1;
      final r = math.sqrt(u * u + v * v);
      final a = (1 - r).clamp(0.0, 1.0);
      out[(y * size + x) * 4 + 3] = (a * a * 0.45 * 255).round();
    }
  }
  return img.Image.fromBytes(
    width: size,
    height: size,
    bytes: out.buffer,
    numChannels: 4,
  );
}
