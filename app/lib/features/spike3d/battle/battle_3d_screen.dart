import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../inflate/inflate_mesh.dart';
import '../inflate/inflated_glb.dart';
import 'atb.dart';
import 'battle_director.dart';
import 'battle_stage.dart';
import 'spike_battle_setup.dart';

/// Prototype 3D battle (debug route `/debug/3d`): two inflated characters,
/// real-time ATB, auto-movement, dynamic camera, Flutter overlay UI.
///
/// Frame loop (one `onTick` of flutter_scene's SceneView):
///   AtbBattle.tick → BattleDirector.handle/update → BattleStage.apply
///   → overlay notifier (gauges, buttons, damage numbers).
/// The overlay is ordinary Flutter widgets stacked on the SceneView: no
/// platform view, so no composition cost or z-order issues.
class Battle3DScreen extends StatefulWidget {
  const Battle3DScreen({
    super.key,
    required this.playerPng,
    required this.cpuPng,
    this.cpuSimplified = false,
    this.quality = const StageQuality(),
  });

  final Uint8List playerPng;
  final Uint8List cpuPng;
  final bool cpuSimplified;
  final StageQuality quality;

  @override
  State<Battle3DScreen> createState() => _Battle3DScreenState();
}

class _Popup {
  _Popup(this.side, this.damage, this.at);
  final int side;
  final int damage;
  final vm.Vector3 at;
  double age = 0;
}

class _Battle3DScreenState extends State<Battle3DScreen> {
  final _overlay = ValueNotifier<int>(0);
  late AtbBattle _battle;
  late BattleDirector _director;
  BattleStage? _stage;
  String? _error;
  String _loadInfo = '';
  final _shownHp = <double>[0, 0];
  final _popups = <_Popup>[];
  fs.Camera? _lastCamera;
  double _fps = 0;
  int _seed = 4;

  @override
  void initState() {
    super.initState();
    _newBattle();
    _load();
  }

  void _newBattle() {
    _battle = spikeBattle(seed: _seed);
    _director = BattleDirector(seed: _seed);
    for (var i = 0; i < 2; i++) {
      _shownHp[i] = _battle.fighters[i].maxHp.toDouble();
    }
    _popups.clear();
  }

  Future<void> _load() async {
    if (!flutterGpuAvailable()) {
      setState(
        () => _error =
            'Flutter GPU が つかえない たんまつ です（Impeller オフ / Android 9 以下）。\n'
            'せいしき版では 2D バトルに きりかえます。',
      );
      return;
    }
    try {
      final sw = Stopwatch()..start();
      final results = await Future.wait([
        buildInflatedGlbInBackground(widget.playerPng),
        buildInflatedGlbInBackground(
          widget.cpuPng,
          options: widget.cpuSimplified
              ? const InflateOptions.simplified()
              : const InflateOptions(),
        ),
      ]);
      final genMs = sw.elapsedMilliseconds;
      final stage = await BattleStage.create(
        playerGlb: results[0].glb,
        cpuGlb: results[1].glb,
        quality: widget.quality,
      );
      if (!mounted) return;
      setState(() {
        _stage = stage;
        _loadInfo =
            'inflate ${results[0].timings.totalUs ~/ 1000}+${results[1].timings.totalUs ~/ 1000} ms '
            '(isolates ${genMs}ms), load ${sw.elapsedMilliseconds - genMs} ms, '
            '${results[0].triangleCount + results[1].triangleCount} tris';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _tick(Duration elapsed, double dt) {
    final stage = _stage;
    if (stage == null) return;
    dt = math.min(dt, 0.1);
    if (dt > 0) _fps = _fps * 0.95 + (1 / dt) * 0.05;
    for (final e in _battle.tick(dt)) {
      _director.handle(e);
    }
    _director.update(dt);
    final cues = _director.takeCues();
    stage.apply(_director, dt, cues);
    for (final c in cues) {
      _shownHp[c.targetSide] = math.max(0, _shownHp[c.targetSide] - c.damage);
      _popups.add(
        _Popup(c.targetSide, c.damage, c.position + vm.Vector3(0, 0.6, 0)),
      );
    }
    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age > 1.0);
    _overlay.value++;
  }

  @override
  void dispose() {
    _overlay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    return Scaffold(
      backgroundColor: const Color(0xFFBFE3FF),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : stage == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, box) => Stack(
                fit: StackFit.expand,
                children: [
                  fs.SceneView(
                    stage.scene,
                    cameraBuilder: (_) =>
                        _lastCamera = stage.cameraFor(_director.camera),
                    onTick: _tick,
                  ),
                  ListenableBuilder(
                    listenable: _overlay,
                    builder: (context, _) => _overlayUi(context, box.biggest),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _overlayUi(BuildContext context, Size size) {
    final cam = _lastCamera;
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Row(
              children: [
                Expanded(child: _panel(0)),
                const SizedBox(width: 8),
                Expanded(child: _panel(1)),
              ],
            ),
          ),
          if (cam != null)
            for (final p in _popups)
              if (cam.worldToScreen(p.at + vm.Vector3(0, p.age * 0.6, 0), size)
                  case final o?)
                Positioned(
                  left: o.dx - 40,
                  top: o.dy - 20,
                  width: 80,
                  child: Opacity(
                    opacity: (1 - p.age).clamp(0.0, 1.0),
                    child: Text(
                      '${p.damage}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: p.side == 0 ? Colors.redAccent : Colors.amber,
                        shadows: const [Shadow(blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
          Positioned(left: 8, right: 8, bottom: 8, child: _controls()),
          Positioned(
            left: 8,
            bottom: 200,
            child: Text(
              '${_fps.toStringAsFixed(0)} fps · $_loadInfo',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(int side) {
    final f = _battle.fighters[side];
    final full = f.gauge >= 1;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            side == 0 ? '${f.name}（きみ）' : f.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _bar(_shownHp[side] / f.maxHp, Colors.green, 10),
          const SizedBox(height: 4),
          _bar(f.gauge, full ? Colors.orange : Colors.lightBlue, 8),
        ],
      ),
    );
  }

  Widget _bar(double v, Color c, double h) => ClipRRect(
    borderRadius: BorderRadius.circular(h),
    child: LinearProgressIndicator(
      value: v.clamp(0.0, 1.0),
      minHeight: h,
      color: c,
      backgroundColor: Colors.black12,
    ),
  );

  Widget _controls() {
    if (_battle.over) {
      final win = _battle.winner == 0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            win ? 'かち！' : 'まけちゃった…',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => setState(() {
              _seed++;
              _newBattle();
              _stage?.reset();
            }),
            child: const Text('もういちど'),
          ),
        ],
      );
    }
    final moves = _battle.fighters[0].moves;
    final left = _battle.playerChoiceLeft;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  left != null
                      ? 'わざを えらんでね（あと ${left.ceil()}）'
                      : 'ゲージが たまるまで まってね',
                ),
              ),
              const Text('おまかせ'),
              Switch(
                value: _battle.alwaysAuto,
                onChanged: (v) => setState(() => _battle.alwaysAuto = v),
              ),
            ],
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final (i, m) in moves.indexed)
                FilledButton(
                  onPressed: left != null
                      ? () => setState(() => _battle.choose(i))
                      : null,
                  child: Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
