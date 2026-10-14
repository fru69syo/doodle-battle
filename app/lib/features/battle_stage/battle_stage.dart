import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../puppet/anim/clips.dart';
import '../puppet/mesh/puppet_mesh.dart';
import '../puppet/puppet_builder.dart';
import '../puppet/puppet_look.dart';
import '../puppet/render/puppet_sprite.dart';
import '../puppet/render/puppet_view.dart';
import 'stage_background.dart';
import 'stage_director.dart';
import 'stage_events.dart';
import 'stage_painter.dart';
import 'stage_quality.dart';
import 'stage_theme.dart';
import 'stage_vfx.dart';

export 'stage_events.dart';
export 'stage_quality.dart';
export 'stage_theme.dart';

/// Drives a 2.5D battle from a [StageFeed] (the engine adapter): pulls
/// events every frame, hands them to the [StageDirector] (choreography,
/// camera) and exposes what the overlay shows (HP that drops at the moment
/// of impact, gauges, statuses, the winner). Listen to it to rebuild the
/// overlay.
class BattleStageController extends ChangeNotifier {
  BattleStageController({
    required this.feed,
    this.theme = StageTheme.meadow,
    this.seed = 1,
    this.reducedMotion = false,
  });

  final StageFeed feed;
  final StageTheme theme;
  final int seed;

  /// No camera shake (accessibility setting).
  final bool reducedMotion;

  StageDirector? _director;
  StageDirector? get director => _director;

  /// Events seen so far (tests, replays).
  final log = <StageEvent>[];
  bool _ended = false;

  /// Average CPU time of [advance] (µs), for the debug label.
  double frameUs = 0;

  /// Called by [BattleStage] once the puppets are built. [sizes]: per side
  /// drawing size (1 = normal, [kBossSize] for a world's boss); visual only.
  void attach(
    List<PuppetMesh> meshes,
    List<PuppetLook> looks, {
    List<double> sizes = const [1, 1],
  }) {
    _director = StageDirector(
      contexts: [
        for (final m in meshes) AnimContext(m.rig, limited: m.simplified),
      ],
      seed: seed,
      halfWidth: [
        for (final (i, m) in meshes.indexed) halfWidthOf(m) * sizes[i],
      ],
      fxScale: [for (final l in looks) l.fxScale],
      size: sizes,
    )..shakeScale = reducedMotion ? 0 : 1;
    for (var i = 0; i < 2; i++) {
      _director!.fighters[i].shownHp = feed.fighter(i).maxHp.toDouble();
    }
    notifyListeners();
  }

  /// Advances by [dt] seconds (called every frame by [BattleStage]; tests
  /// call it directly).
  void advance(double dt) {
    final d = _director;
    if (d == null) return;
    final sw = Stopwatch()..start();
    for (final e in feed.advance(dt)) {
      log.add(e);
      d.handle(e);
    }
    d.syncStatus([feed.fighter(0), feed.fighter(1)]);
    d.update(dt);
    frameUs = frameUs * 0.9 + sw.elapsedMicroseconds * 0.1;
    if (!_ended && d.winner != null) _ended = true;
    notifyListeners();
  }

  StageFighterState state(int side) => feed.fighter(side);

  /// HP as shown (drops when the blow lands on screen, not at the engine
  /// tick).
  double shownHp(int side) =>
      _director?.fighters[side].shownHp ?? feed.fighter(side).maxHp.toDouble();

  /// Winner once the K.O. has been shown, else null.
  int? get winner => _director?.winner;
  bool get over => winner != null;
}

/// Drawing size of a world's boss (stage 10) on the stage: bigger on
/// screen only — stats, hit boxes of the engine and moves are unchanged.
const double kBossSize = 1.3;

/// Half the drawing's width in world units when it stands
/// [StagePainter.charHeight] tall.
double halfWidthOf(PuppetMesh c) {
  var top = double.infinity, minX = double.infinity, maxX = -double.infinity;
  for (var i = 0; i < c.rest.length; i += 2) {
    final x = c.rest[i], y = c.rest[i + 1];
    if (y < top) top = y;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
  }
  final h = (c.rig.groundY - top).clamp(1.0, 1e9);
  return 0.5 * (maxX - minX) / h * 1.25;
}

/// The 2.5D battle stage: perspective ground, parallax theme, shadows,
/// auto-moving puppets, camera pan / zoom / shake, move effects, damage
/// numbers, effectiveness texts and status icons. Put the overlay widgets
/// (`stage_overlay.dart`) on top in a `Stack`.
class BattleStage extends ConsumerStatefulWidget {
  const BattleStage({
    super.key,
    required this.controller,
    required this.fighters,
    this.sizes = const [1, 1],
    this.drawnEffects = const {},
    this.quality,
    this.autoStart = true,
    this.onQualityChanged,
  });

  final BattleStageController controller;

  /// Player (0) and opponent (1) puppets (picture, rig, look).
  final List<PuppetSpec> fighters;

  /// Per side drawing size (1 = normal; [kBossSize] for bosses). Visual
  /// only; the camera frames the bigger drawing.
  final List<double> sizes;

  /// Drawn move effects by side (docs/LOOP.md), decoded.
  final Map<int, ui.Image> drawnEffects;

  /// Fixed tier, or null for the adaptive switch (starts high).
  final StageQuality? quality;

  /// Tests drive time with [BattleStageController.advance] instead.
  final bool autoStart;
  final ValueChanged<StageQuality>? onQualityChanged;

  @override
  ConsumerState<BattleStage> createState() => BattleStageState();
}

class BattleStageState extends ConsumerState<BattleStage>
    with SingleTickerProviderStateMixin {
  List<PuppetSprite>? sprites;
  late final StageBackground _background;
  final _vfx = StageVfx();
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Object? _error;
  late AdaptiveQuality _adaptive;
  late StageQuality _quality;
  TimingsCallback? _timings;

  StageQuality get quality => _quality;

  @override
  void initState() {
    super.initState();
    _background = StageBackground(widget.controller.theme);
    _quality = widget.quality ?? StageQuality.high;
    _adaptive = AdaptiveQuality(
      initial: _quality,
      onChange: (q) {
        if (!mounted) return;
        setState(() => _quality = q);
        widget.onQualityChanged?.call(q);
      },
    );
    if (widget.quality == null && widget.autoStart) {
      _timings = _adaptive.onTimings;
      SchedulerBinding.instance.addTimingsCallback(_timings!);
    }
    _vfx.drawn.addAll(widget.drawnEffects);
    _load();
  }

  Future<void> _load() async {
    try {
      final builder = ref.read(puppetBuilderProvider);
      final specs = [
        for (final s in widget.fighters)
          PuppetSpec(
            png: s.png,
            rigJson: s.rigJson,
            rig: s.rig,
            strokes: s.strokes,
            look: s.look,
            quality: _quality.puppet,
          ),
      ];
      final meshes = [for (final s in specs) await builder.mesh(s)];
      final made = [for (final m in meshes) await PuppetSprite.create(m)];
      if (!mounted) {
        for (final s in made) {
          s.dispose();
        }
        return;
      }
      widget.controller.attach(meshes, [
        for (final s in specs) s.look,
      ], sizes: widget.sizes);
      setState(() => sprites = made);
      if (widget.autoStart) _ticker = createTicker(_onTick)..start();
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    widget.controller.advance(dt);
  }

  @override
  void dispose() {
    final t = _timings;
    if (t != null) SchedulerBinding.instance.removeTimingsCallback(t);
    _ticker?.dispose();
    for (final s in sprites ?? const <PuppetSprite>[]) {
      s.dispose();
    }
    _background.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = sprites;
    final d = widget.controller.director;
    if (_error != null) {
      return ColoredBox(
        color: widget.controller.theme.ground,
        child: Center(child: Text(kDebugMode ? '$_error' : '')),
      );
    }
    if (s == null || d == null) {
      return ColoredBox(
        color: widget.controller.theme.skyBottom,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: StagePainter(
          director: d,
          sprites: s,
          background: _background,
          vfx: _vfx,
          repaint: widget.controller,
          looks: [for (final f in widget.fighters) f.look],
          quality: _quality,
        ),
      ),
    );
  }
}
