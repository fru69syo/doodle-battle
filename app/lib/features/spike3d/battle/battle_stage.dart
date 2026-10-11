import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../inflate/procedural_rig.dart';
import 'battle_director.dart';

/// Whether this device/process can render with Flutter GPU (Impeller with
/// the `EnableFlutterGPU` manifest flag). False on Skia (Android < 10 or
/// Impeller opted out) and in plain `flutter test` without
/// `--enable-impeller --enable-flutter-gpu`.
bool flutterGpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

/// Visual quality knobs (low-end devices drop real shadows and props).
class StageQuality {
  const StageQuality({this.realShadows = true, this.props = true});
  static const low = StageQuality(realShadows: false, props: false);
  final bool realShadows;
  final bool props;
}

/// The flutter_scene side of the battle: owns the [Scene], the two
/// imported character GLBs and the effects, and applies a
/// [BattleDirector]'s state each frame. Everything game-related lives in
/// the director; this class only maps it to nodes, clips and particles.
class BattleStage {
  BattleStage._(this.scene, this._fighters, this._impacts);

  final Scene scene;
  final List<RiggedModel> _fighters;
  final List<_ImpactFx> _impacts;
  int _nextImpact = 0;

  /// Loads both characters (GLB bytes from the inflate pipeline, or a
  /// cloud-generated model later) and builds the stage.
  static Future<BattleStage> create({
    required Uint8List playerGlb,
    required Uint8List cpuGlb,
    StageQuality quality = const StageQuality(),
  }) async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    buildStageEnvironment(scene, quality);
    final fighters = <RiggedModel>[];
    for (final glb in [playerGlb, cpuGlb]) {
      final model = await Node.fromGlbBytes(glb);
      final holder = Node(name: 'fighter${fighters.length}')..add(model);
      scene.add(holder);
      final shadow = Node(
        name: 'blob_shadow',
        mesh: Mesh(
          DiscGeometry(radius: 0.5, segments: 24),
          blobShadow(quality),
        ),
      );
      shadow.position = Vector3(0, 0.004, 0);
      scene.add(shadow);
      fighters.add(RiggedModel(holder, model, shadow));
    }
    final impacts = [for (var i = 0; i < 3; i++) _ImpactFx.create(scene)];
    return BattleStage._(scene, fighters, impacts);
  }

  /// Forgets clip state (call when a new director takes over).
  void reset() {
    for (final f in _fighters) {
      f.token = -1;
    }
  }

  /// Applies positions, facing, clips (with a short cross-fade) and effects.
  void apply(BattleDirector d, double dt, List<ImpactCue> cues) {
    for (final f in d.fighters) {
      final rig = _fighters[f.side];
      rig.holder.position = f.position;
      // The importer mirrors glTF +Z to engine −Z, so the model's face is
      // local −Z: add π to face along (sin yaw, 0, cos yaw).
      rig.holder.rotation = Quaternion.axisAngle(
        Vector3(0, 1, 0),
        f.yaw + math.pi,
      );
      rig.shadow.position = Vector3(f.position.x, 0.004, f.position.z);
      rig.play(f.clip, f.clipToken);
      rig.fade(dt);
    }
    for (final c in cues) {
      _impacts[_nextImpact++ % _impacts.length].fire(c.position, big: c.ko);
    }
    for (final fx in _impacts) {
      fx.update(dt);
    }
  }

  Camera cameraFor(CameraView v) => PerspectiveCamera(
    fovRadiansY: v.fovY * degrees2Radians,
    position: v.eye,
    target: v.target,
  );

  /// Sky, sun (optionally with shadows), ground and props.
  static void buildStageEnvironment(Scene scene, StageQuality q) {
    scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: Vector3(0.25, 0.55, 1.0),
        horizonColor: Vector3(0.85, 0.93, 1.0),
        groundColor: Vector3(0.45, 0.6, 0.35),
        sunDirection: Vector3(0.5, 0.7, -0.4),
      ),
    );
    scene.directionalLight = DirectionalLight(
      direction: Vector3(-0.45, -1, 0.35),
      intensity: 2.6,
      castsShadow: q.realShadows,
      shadowSoftness: 0.15,
      shadowCascadeCount: 2,
      shadowMaxDistance: 25,
    );
    // Ground: pastel grass disc with the ring painted on.
    final ground = PhysicallyBasedMaterial(baseColorTexture: _groundTexture())
      ..metallicFactor = 0
      ..roughnessFactor = 0.95;
    scene.add(
      Node(
        name: 'ground',
        mesh: Mesh(DiscGeometry(radius: 14, segments: 64), ground),
      ),
    );
    if (q.props) {
      // A few low-poly trees and rocks for parallax (depth cues).
      final rnd = math.Random(5);
      final trunk = PhysicallyBasedMaterial()
        ..baseColorFactor = Vector4(0.55, 0.36, 0.22, 1)
        ..metallicFactor = 0
        ..roughnessFactor = 0.9;
      final leaves = PhysicallyBasedMaterial()
        ..baseColorFactor = Vector4(0.3, 0.72, 0.35, 1)
        ..metallicFactor = 0
        ..roughnessFactor = 0.8;
      final rock = PhysicallyBasedMaterial()
        ..baseColorFactor = Vector4(0.72, 0.7, 0.78, 1)
        ..metallicFactor = 0
        ..roughnessFactor = 0.85;
      for (var i = 0; i < 12; i++) {
        final a = i / 12 * 2 * math.pi + rnd.nextDouble() * 0.3;
        final r = 6.5 + rnd.nextDouble() * 3;
        final p = Vector3(math.cos(a) * r, 0, math.sin(a) * r);
        if (i.isEven) {
          final s = 0.8 + rnd.nextDouble() * 0.7;
          scene.add(
            Node(
              mesh: Mesh(
                CylinderGeometry(
                  topRadius: 0.12 * s,
                  bottomRadius: 0.16 * s,
                  height: 1.0 * s,
                  radialSegments: 8,
                ),
                trunk,
              ),
            )..position = p + Vector3(0, 0.5 * s, 0),
          );
          scene.add(
            Node(
              mesh: Mesh(
                IcosphereGeometry(radius: 0.8 * s, subdivisions: 1),
                leaves,
              ),
            )..position = p + Vector3(0, 1.5 * s, 0),
          );
        } else {
          final s = 0.3 + rnd.nextDouble() * 0.4;
          scene.add(
            Node(
              mesh: Mesh(IcosphereGeometry(radius: s, subdivisions: 1), rock),
            )..position = p + Vector3(0, s * 0.5, 0),
          );
        }
      }
    }
  }

  /// Soft round contact shadow (cheap; the only shadow on low quality).
  static Material blobShadow(StageQuality q) {
    const n = 64;
    final px = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final dx = (x + 0.5) / n * 2 - 1, dy = (y + 0.5) / n * 2 - 1;
        final r = math.sqrt(dx * dx + dy * dy);
        final a = (1 - r).clamp(0.0, 1.0);
        final i = (y * n + x) * 4;
        px[i + 3] = (255 * a * a * (q.realShadows ? 0.35 : 0.6)).round();
      }
    }
    return UnlitMaterial(colorTexture: Texture2D.fromPixels(px, n, n))
      ..alphaMode = AlphaMode.blend
      ..depthLayer = 1;
  }

  static TextureSource _groundTexture() {
    const n = 256;
    final px = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        // Disc UVs span the disc's bounding square; r in metres.
        final dx = ((x + 0.5) / n - 0.5) * 28, dz = ((y + 0.5) / n - 0.5) * 28;
        final r = math.sqrt(dx * dx + dz * dz);
        final stripe = ((dx / 1.6).floor() + (dz / 1.6).floor()).isEven
            ? 1.0
            : 0.94;
        var g = [0.62 * stripe, 0.85 * stripe, 0.5 * stripe];
        if (r < 3.4) {
          g = [0.93, 0.86 * stripe + 0.04, 0.66 * stripe]; // sandy ring
        }
        if ((r - 3.4).abs() < 0.08) g = [1, 1, 1];
        final i = (y * n + x) * 4;
        px[i] = (g[0] * 255).round();
        px[i + 1] = (g[1].clamp(0, 1) * 255).round();
        px[i + 2] = (g[2] * 255).round();
        px[i + 3] = 255;
      }
    }
    return Texture2D.fromPixels(px, n, n);
  }
}

/// An imported inflated character with its clips, cross-faded by name.
class RiggedModel {
  RiggedModel(this.holder, this.model, this.shadow) {
    for (final name in RigClips.all) {
      final anim = model.findAnimationByName(name);
      if (anim == null) continue;
      final clip = model.createAnimationClip(anim)
        ..loop = RigClips.loops(name)
        ..weight = name == RigClips.idle ? 1 : 0;
      if (name == RigClips.idle) clip.play();
      clips[name] = clip;
    }
  }

  final Node holder;
  final Node model;
  final Node shadow;
  final clips = <String, AnimationClip>{};
  String current = RigClips.idle;
  int token = -1;

  void play(String name, int clipToken) {
    if (clipToken == token) return;
    token = clipToken;
    current = name;
    final c = clips[name];
    if (c == null) return;
    c.loop = RigClips.loops(name);
    c.gotoAndPlay(0);
  }

  void fade(double dt) {
    final k = 1 - math.exp(-dt / 0.06);
    for (final MapEntry(key: name, value: c) in clips.entries) {
      final target = name == current ? 1.0 : 0.0;
      c.weight = c.weight + (target - c.weight) * k;
    }
  }
}

/// Star burst + flash for a hit.
class _ImpactFx {
  _ImpactFx(this.node, this.system, this.flash, this.flashMaterial);

  static _ImpactFx create(Scene scene) {
    final system = ParticleSystem(
      maxParticles: 64,
      shape: const SphereEmitterShape(radius: 0.08),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0, count: 26)]),
      lifetime: const UniformFloat(0.3, 0.55),
      startSpeed: const UniformFloat(2.0, 4.2),
      startSize: const UniformFloat(0.1, 0.22),
      startColor: ConstantColor(Vector4(1, 0.95, 0.5, 1)),
      gravity: Vector3(0, -5, 0),
      looping: false,
      duration: 0.05,
      modules: [
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0, Vector4(1, 1, 0.7, 1)),
              ColorStop(0.5, Vector4(1, 0.6, 0.2, 1)),
              ColorStop(1, Vector4(1, 0.3, 0.1, 0)),
            ]),
          ),
        ),
      ],
    );
    final node = Node(name: 'impact');
    final sprite = SpriteMaterial(colorTexture: _starTexture())
      ..blendMode = SpriteBlendMode.additive;
    final emitter = ParticleEmitterComponent(system: system, material: sprite)
      ..paused = true;
    node.addComponent(emitter);
    final flashMaterial = UnlitMaterial()
      ..baseColorFactor = Vector4(1, 1, 0.85, 0)
      ..alphaMode = AlphaMode.blend;
    final flash = Node(
      mesh: Mesh(
        IcosphereGeometry(radius: 0.22, subdivisions: 2),
        flashMaterial,
      ),
    )..visible = false;
    node.add(flash);
    scene.add(node);
    return _ImpactFx(node, system, flash, flashMaterial).._emitter = emitter;
  }

  final Node node;
  final ParticleSystem system;
  final Node flash;
  final UnlitMaterial flashMaterial;
  late ParticleEmitterComponent _emitter;
  double _t = 1;
  bool _big = false;

  void fire(Vector3 at, {bool big = false}) {
    node.position = at;
    system.reset();
    _emitter.paused = false;
    _t = 0;
    _big = big;
    flash.visible = true;
  }

  void update(double dt) {
    _t += dt;
    const flashTime = 0.18;
    if (_t < flashTime) {
      final u = _t / flashTime;
      flash.scale = Vector3.all((0.3 + u) * (_big ? 1.8 : 1));
      flashMaterial.baseColorFactor = Vector4(
        1,
        1,
        0.85,
        0.55 * (1 - u) * (1 - u),
      );
    } else if (flash.visible) {
      flash.visible = false;
    }
    if (_t > 1.5) _emitter.paused = true;
  }

  static TextureSource _starTexture() {
    const n = 32;
    final px = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final dx = (x + 0.5) / n * 2 - 1, dy = (y + 0.5) / n * 2 - 1;
        final r = math.sqrt(dx * dx + dy * dy);
        final a = math.atan2(dy, dx);
        final star = 0.55 + 0.45 * math.cos(a * 5);
        final v = (1 - r / (0.45 + 0.55 * star)).clamp(0.0, 1.0);
        final i = (y * n + x) * 4;
        px[i] = 255;
        px[i + 1] = 255;
        px[i + 2] = 255;
        px[i + 3] = (255 * v).round();
      }
    }
    return Texture2D.fromPixels(px, n, n);
  }
}
