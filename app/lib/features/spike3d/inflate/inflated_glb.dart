import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../ar/glb/glb_writer.dart';
import 'inflate_mesh.dart';
import 'procedural_rig.dart';

/// Phase timings of one [buildInflatedGlb] call (microseconds).
class InflateTimings {
  const InflateTimings({
    required this.decodeUs,
    required this.meshUs,
    required this.rigUs,
    required this.encodeUs,
  });
  final int decodeUs, meshUs, rigUs, encodeUs;
  int get totalUs => decodeUs + meshUs + rigUs + encodeUs;

  @override
  String toString() =>
      'decode ${decodeUs ~/ 1000} ms, mesh ${meshUs ~/ 1000} ms, '
      'rig ${rigUs ~/ 1000} ms, encode ${encodeUs ~/ 1000} ms '
      '(total ${totalUs ~/ 1000} ms)';
}

/// Result of [buildInflatedGlb].
class InflatedGlb {
  const InflatedGlb({
    required this.glb,
    required this.vertexCount,
    required this.triangleCount,
    required this.width,
    required this.height,
    required this.depth,
    required this.timings,
  });

  /// glTF 2.0 binary: one skinned mesh, skeleton `rig_root → rig_spine →
  /// rig_head`, animations [RigClips.all]. +Y up, facing +Z, feet at origin.
  final Uint8List glb;
  final int vertexCount;
  final int triangleCount;
  final double width, height, depth;
  final InflateTimings timings;
}

/// [buildInflatedGlb] on a background isolate (what the app does on device).
Future<InflatedGlb> buildInflatedGlbInBackground(
  Uint8List cutoutPng, {
  InflateOptions options = const InflateOptions(),
}) => Isolate.run(() => buildInflatedGlb(cutoutPng, options: options));

/// Cut-out PNG (transparent background, ≤512 px) → rigged, animated GLB.
///
/// Throws [FormatException] for undecodable input and
/// [EmptyCutoutException] when nothing is opaque.
InflatedGlb buildInflatedGlb(
  Uint8List cutoutPng, {
  InflateOptions options = const InflateOptions(),
}) {
  final sw = Stopwatch()..start();
  final decoded = img.decodePng(cutoutPng);
  if (decoded == null) throw const FormatException('cutout is not a PNG');
  final decodeUs = sw.elapsedMicroseconds;
  sw.reset();
  final mesh = buildInflatedMesh(decoded, options: options);
  final meshUs = sw.elapsedMicroseconds;
  sw.reset();
  final clips = buildRigClips(mesh.height);
  final (joints, weights) = skinWeights(mesh.positions, mesh.height);
  final rigUs = sw.elapsedMicroseconds;
  sw.reset();
  final glb = encodeInflatedGlb(mesh, clips, joints, weights);
  final encodeUs = sw.elapsedMicroseconds;
  return InflatedGlb(
    glb: glb,
    vertexCount: mesh.vertexCount,
    triangleCount: mesh.triangleCount,
    width: mesh.width,
    height: mesh.height,
    depth: mesh.depth,
    timings: InflateTimings(
      decodeUs: decodeUs,
      meshUs: meshUs,
      rigUs: rigUs,
      encodeUs: encodeUs,
    ),
  );
}

/// Serialises [mesh] + skin + [clips] as GLB.
Uint8List encodeInflatedGlb(
  InflatedMesh mesh,
  List<RigClip> clips,
  Uint8List joints,
  Float32List weights,
) {
  final w = GlbWriter();
  final n = mesh.vertexCount;
  final pos = w.addFloatAccessor(mesh.positions, 'VEC3', withBounds: true);
  final nor = w.addFloatAccessor(mesh.normals, 'VEC3');
  final col = w.addFloatAccessor(mesh.colors, 'VEC4');
  final jnt = w.addRawAccessor(
    joints,
    componentType: GltfComponentType.unsignedByte,
    type: 'VEC4',
    count: n,
  );
  final wgt = w.addFloatAccessor(weights, 'VEC4');
  final int idx;
  if (n <= 0xFFFF) {
    idx = w.addIndexAccessor(mesh.indices);
  } else {
    idx = w.addRawAccessor(
      mesh.indices.buffer.asUint8List(
        mesh.indices.offsetInBytes,
        mesh.indices.lengthInBytes,
      ),
      componentType: GltfComponentType.unsignedInt,
      type: 'SCALAR',
      count: mesh.indices.length,
      target: GltfTarget.elementArrayBuffer,
    );
  }

  final attributes = <String, int>{
    'POSITION': pos,
    'NORMAL': nor,
    'COLOR_0': col,
    'JOINTS_0': jnt,
    'WEIGHTS_0': wgt,
  };
  final material = <String, Object?>{
    'name': mesh.texture != null ? 'drawing' : 'flat',
    'pbrMetallicRoughness': <String, Object?>{
      'metallicFactor': 0.0,
      'roughnessFactor': mesh.flatShaded ? 0.7 : 0.85,
    },
  };
  final images = <Map<String, Object?>>[];
  final textures = <Map<String, Object?>>[];
  final tex = mesh.texture;
  if (tex != null) {
    attributes['TEXCOORD_0'] = w.addFloatAccessor(mesh.uvs, 'VEC2');
    final view = w.addBufferView(img.encodePng(tex, level: 6));
    images.add({'name': 'drawing', 'bufferView': view, 'mimeType': 'image/png'});
    textures.add({'sampler': 0, 'source': 0});
    (material['pbrMetallicRoughness']! as Map)['baseColorTexture'] = {
      'index': 0,
    };
  }

  // Skeleton: root at the feet, spine and head above it.
  final h = mesh.height;
  final bindY = [0.0, RigJoints.spineAt * h, RigJoints.headAt * h];
  final localY = [0.0, bindY[1], bindY[2] - bindY[1]];
  final ibm = <double>[];
  for (final y in bindY) {
    ibm.addAll([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -y, 0, 1]);
  }
  final ibmAcc = w.addFloatAccessor(ibm, 'MAT4', target: null);

  // Nodes: 0 = mesh (scene root, no transform), 1..3 = joints.
  final nodes = <Map<String, Object?>>[
    {'name': 'body', 'mesh': 0, 'skin': 0},
    for (var j = 0; j < 3; j++)
      {
        'name': RigJoints.names[j],
        if (localY[j] != 0) 'translation': [0.0, localY[j], 0.0],
        if (j < 2) 'children': [j + 2],
      },
  ];

  final animations = <Map<String, Object?>>[];
  for (final clip in clips) {
    final input = w.addFloatAccessor(clip.times, 'SCALAR', target: null, withBounds: true);
    final samplers = <Map<String, Object?>>[];
    final channels = <Map<String, Object?>>[];
    for (var j = 0; j < 3; j++) {
      final poses = clip.poses[j];
      final t = <double>[];
      final r = <double>[];
      final s = <double>[];
      for (final p in poses) {
        t.addAll([p.tx, localY[j] + p.ty, p.tz]);
        r.addAll(p.quaternion);
        s.addAll([p.sx, p.sy, p.sx]);
      }
      for (final (path, values, type) in [
        ('translation', t, 'VEC3'),
        ('rotation', r, 'VEC4'),
        ('scale', s, 'VEC3'),
      ]) {
        if (_constant(values, type == 'VEC4' ? 4 : 3) &&
            _isRest(path, values, localY[j])) {
          continue;
        }
        samplers.add({
          'input': input,
          'output': w.addFloatAccessor(values, type, target: null),
          'interpolation': 'LINEAR',
        });
        channels.add({
          'sampler': samplers.length - 1,
          'target': {'node': j + 1, 'path': path},
        });
      }
    }
    animations.add({'name': clip.name, 'samplers': samplers, 'channels': channels});
  }

  return w.build({
    'asset': {'version': '2.0', 'generator': 'doodle_battle spike3d inflate'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0, 1],
      },
    ],
    'nodes': nodes,
    'meshes': [
      {
        'name': 'body',
        'primitives': [
          {'attributes': attributes, 'indices': idx, 'material': 0},
        ],
      },
    ],
    'materials': [material],
    if (textures.isNotEmpty) ...{
      'samplers': [
        {'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071},
      ],
      'images': images,
      'textures': textures,
    },
    'skins': [
      {
        'name': 'rig',
        'inverseBindMatrices': ibmAcc,
        'joints': [1, 2, 3],
        'skeleton': 1,
      },
    ],
    'animations': animations,
  });
}

bool _constant(List<double> v, int n) {
  for (var i = n; i < v.length; i++) {
    if ((v[i] - v[i % n]).abs() > 1e-7) return false;
  }
  return true;
}

bool _isRest(String path, List<double> v, double restY) {
  final rest = switch (path) {
    'translation' => [0.0, restY, 0.0],
    'rotation' => [0.0, 0.0, 0.0, 1.0],
    _ => [1.0, 1.0, 1.0],
  };
  for (var i = 0; i < rest.length; i++) {
    if ((v[i] - rest[i]).abs() > 1e-7) return false;
  }
  return true;
}
