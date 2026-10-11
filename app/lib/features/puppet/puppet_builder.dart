import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'mesh/puppet_mesh.dart';
import 'puppet_look.dart';
import 'render/puppet_sprite.dart';
import 'rig/auto_rig.dart';
import 'rig/bin_mask.dart';
import 'rig/character_rig.dart';
import 'rig/limb_hints.dart';

/// Mesh density / texture tier. [low] is picked by the adaptive quality
/// switch on slow phones (fewer triangles, coarser weights).
enum PuppetQuality {
  high(gridCells: 64, weightRes: 128),
  low(gridCells: 40, weightRes: 96);

  const PuppetQuality({required this.gridCells, required this.weightRes});
  final int gridCells;
  final int weightRes;
}

/// Everything needed to build one character's puppet.
class PuppetSpec {
  const PuppetSpec({
    required this.png,
    this.rigJson,
    this.rig,
    this.strokes,
    this.look = const PuppetLook(),
    this.quality = PuppetQuality.high,
  });

  /// Cut-out PNG (or the composite display picture with drawn parts).
  final Uint8List png;

  /// Stored rig (Character.rig); invalid or missing → auto-rig.
  final String? rigJson;

  /// A rig object (the editor's working copy); wins over [rigJson].
  final CharacterRig? rig;

  /// The drawing tool's strokes (drawing pixels), used by the auto-rigger.
  final List<HintStroke>? strokes;
  final PuppetLook look;
  final PuppetQuality quality;

  /// Cache key: picture + rig + look + quality.
  String get key {
    final h = sha1.convert(png).toString().substring(0, 16);
    final r =
        rig?.encode() ??
        rigJson ??
        (strokes == null ? '' : 's${strokes!.length}');
    final rh = sha1.convert(r.codeUnits).toString().substring(0, 10);
    return '$h:$rh:${look.simple}:${quality.name}';
  }
}

/// Runs a pure function off the UI thread. Tests swap in a synchronous
/// runner (isolates do not run under fake async).
typedef PuppetRunner = Future<T> Function<T>(T Function() fn);

Future<T> isolateRunner<T>(T Function() fn) => Isolate.run(fn);
Future<T> syncRunner<T>(T Function() fn) async => fn();

/// Pure build (call through a [PuppetRunner]).
PuppetMesh buildPuppetSync(PuppetSpec s) {
  final rig = s.rig ?? CharacterRig.tryDecode(s.rigJson);
  return buildPuppetMeshFromPng(
    s.png,
    rig: rig,
    strokes: s.strokes,
    options: BuildOptions(
      gridCells: s.quality.gridCells,
      weightRes: s.quality.weightRes,
      simplified: s.look.simple,
    ),
  );
}

/// Auto-rigs a cut-out PNG (for a new character, the editor's もどす).
CharacterRig autoRigPng(Uint8List png, {List<HintStroke>? strokes}) {
  final im = img.decodePng(png) ?? img.decodeImage(png);
  if (im == null) throw const FormatException('not an image');
  final rgba = Uint8List.fromList(
    im
        .convert(numChannels: 4, format: img.Format.uint8)
        .getBytes(order: img.ChannelOrder.rgba),
  );
  return autoRig(
    BinMask.fromRgba(rgba, im.width, im.height),
    rgba: rgba,
    strokes: strokes,
  ).rig;
}

/// Builds puppets off the UI thread and keeps the last few in memory.
///
/// Memory budget: a puppet is its RGBA texture (≤ ~1.1 MB for a 524² cut-
/// out) plus mesh and weights (~60–150 KB). [maxBytes] (default 8 MB) caps
/// the CPU side; GPU textures live as long as their [PuppetSprite].
class PuppetBuilder {
  PuppetBuilder({this.runner = isolateRunner, this.maxBytes = 8 << 20});

  final PuppetRunner runner;
  final int maxBytes;
  final _meshes = <String, PuppetMesh>{};
  final _pending = <String, Future<PuppetMesh>>{};

  int get cachedBytes => _meshes.values.fold(0, (a, m) => a + m.bytes);
  int get cachedCount => _meshes.length;

  Future<PuppetMesh> mesh(PuppetSpec spec) {
    final key = spec.key;
    final hit = _meshes.remove(key);
    if (hit != null) {
      _meshes[key] = hit; // most recent last
      return Future.value(hit);
    }
    return _pending[key] ??= runner(() => buildPuppetSync(spec)).then(
      (m) {
        _pending.remove(key);
        _meshes[key] = m;
        while (cachedBytes > maxBytes && _meshes.length > 1) {
          _meshes.remove(_meshes.keys.first);
        }
        return m;
      },
      onError: (Object e) {
        _pending.remove(key);
        throw e;
      },
    );
  }

  /// A GPU-ready sprite (the caller disposes it).
  Future<PuppetSprite> sprite(PuppetSpec spec) async =>
      PuppetSprite.create(await mesh(spec));

  Future<CharacterRig> autoRig(Uint8List png, {List<HintStroke>? strokes}) =>
      runner(() => autoRigPng(png, strokes: strokes));

  void clear() => _meshes.clear();
}
