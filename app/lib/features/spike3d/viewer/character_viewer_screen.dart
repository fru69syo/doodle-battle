import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../battle/battle_stage.dart';
import '../inflate/inflate_mesh.dart';
import '../inflate/inflated_glb.dart';
import '../inflate/procedural_rig.dart';

/// Turntable viewer for one inflated character (puffy or simplified) with
/// buttons for every procedural clip, plus generation stats.
class CharacterViewerScreen extends StatefulWidget {
  const CharacterViewerScreen({super.key, required this.png});
  final Uint8List png;

  @override
  State<CharacterViewerScreen> createState() => _CharacterViewerScreenState();
}

class _CharacterViewerScreenState extends State<CharacterViewerScreen> {
  fs.Scene? _scene;
  RiggedModel? _model;
  InflatedGlb? _glb;
  bool _simplified = false;
  String? _error;
  String _clip = RigClips.idle;
  int _token = 0;
  double _yaw = 0;
  bool _spin = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!flutterGpuAvailable()) {
      setState(() => _error = 'Flutter GPU が つかえません');
      return;
    }
    final glb = await buildInflatedGlbInBackground(
      widget.png,
      options: _simplified
          ? const InflateOptions.simplified()
          : const InflateOptions(),
    );
    await fs.Scene.initializeStaticResources();
    final scene = fs.Scene();
    BattleStage.buildStageEnvironment(scene, const StageQuality(props: false));
    final model = await fs.Node.fromGlbBytes(glb.glb);
    final holder = fs.Node()..add(model);
    scene.add(holder);
    final shadow = fs.Node(
      mesh: fs.Mesh(
        fs.DiscGeometry(radius: 0.5),
        BattleStage.blobShadow(const StageQuality()),
      ),
    )..position = vm.Vector3(0, 0.004, 0);
    scene.add(shadow);
    if (!mounted) return;
    setState(() {
      _scene = scene;
      _glb = glb;
      _model = RiggedModel(holder, model, shadow);
    });
  }

  void _tick(Duration elapsed, double dt) {
    final m = _model;
    if (m == null) return;
    if (_spin) _yaw += dt * 0.6;
    m.holder.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      _yaw + math.pi,
    );
    m.play(_clip, _token);
    m.fade(dt);
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    final glb = _glb;
    return Scaffold(
      appBar: AppBar(title: const Text('3D ビューア（spike）')),
      body: _error != null
          ? Center(child: Text(_error!))
          : scene == null || glb == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) => _yaw += d.delta.dx * 0.01,
                    onTap: () => setState(() => _spin = !_spin),
                    child: fs.SceneView(
                      scene,
                      camera: fs.PerspectiveCamera(
                        fovRadiansY: 40 * vm.degrees2Radians,
                        position: vm.Vector3(0, 1.3, -3.4),
                        target: vm.Vector3(0, 0.5, 0),
                      ),
                      onTick: _tick,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${glb.vertexCount} verts / ${glb.triangleCount} tris, '
                    '${glb.glb.length ~/ 1024} KiB, '
                    'w ${glb.width.toStringAsFixed(2)} × d ${glb.depth.toStringAsFixed(2)} m\n'
                    '${glb.timings}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in RigClips.all)
                      ChoiceChip(
                        label: Text(c),
                        selected: _clip == c,
                        onSelected: (_) => setState(() {
                          _clip = c;
                          _token++;
                        }),
                      ),
                  ],
                ),
                SwitchListTile(
                  title: const Text('しょぼキャラ（simplified）'),
                  value: _simplified,
                  onChanged: (v) => setState(() {
                    _simplified = v;
                    _scene = null;
                    _model = null;
                    _load();
                  }),
                ),
              ],
            ),
    );
  }
}
