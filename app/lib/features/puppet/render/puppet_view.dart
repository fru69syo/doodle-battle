import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../anim/clips.dart';
import '../puppet_builder.dart';
import 'aura.dart';
import 'puppet_sprite.dart';

/// Shared builder (isolate + cache). Tests override it with
/// `PuppetBuilder(runner: syncRunner)`.
final puppetBuilderProvider = Provider<PuppetBuilder>((ref) => PuppetBuilder());

/// Plays a character's puppet in a box: loads (off the UI thread, cached)
/// and loops [clip] — or cycles through [clips] — fitted to the box with the
/// feet near the bottom. Shows [placeholder] while building and on error.
///
/// Used by the joint editor preview, the birth / character pages and
/// anywhere a character should move outside battle.
class PuppetView extends ConsumerStatefulWidget {
  const PuppetView({
    super.key,
    required this.spec,
    this.clip = Anim.idle,
    this.clips,
    this.clipSeconds = 2.0,
    this.facing = 1,
    this.playing = true,
    this.placeholder,
    this.onReady,
  });

  final PuppetSpec spec;
  final Anim clip;

  /// When set, cycles these clips, [clipSeconds] each.
  final List<Anim>? clips;
  final double clipSeconds;

  /// +1: the "opponent" is to the right (profile drawings face it).
  final int facing;
  final bool playing;
  final Widget? placeholder;

  /// Called once the sprite is ready (tests, first-run hints).
  final ValueChanged<PuppetSprite>? onReady;

  @override
  ConsumerState<PuppetView> createState() => _PuppetViewState();
}

class _PuppetViewState extends ConsumerState<PuppetView>
    with SingleTickerProviderStateMixin {
  PuppetSprite? _sprite;
  String? _key;
  Object? _error;
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6);
    if (widget.playing) _ticker.start();
    _load();
  }

  @override
  void didUpdateWidget(PuppetView old) {
    super.didUpdateWidget(old);
    if (widget.spec.key != _key) _load();
    if (widget.playing && !_ticker.isActive) _ticker.start();
    if (!widget.playing && _ticker.isActive) _ticker.stop();
  }

  Future<void> _load() async {
    final key = widget.spec.key;
    _key = key;
    try {
      final s = await ref.read(puppetBuilderProvider).sprite(widget.spec);
      if (!mounted || _key != key) {
        s.dispose();
        return;
      }
      setState(() {
        _sprite?.dispose();
        _sprite = s;
        _error = null;
      });
      widget.onReady?.call(s);
    } on Object catch (e) {
      if (mounted && _key == key) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _sprite?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sprite;
    if (s == null || _error != null) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: PuppetPainter(
          sprite: s,
          time: _time,
          clip: widget.clip,
          clips: widget.clips,
          clipSeconds: widget.clipSeconds,
          facing: widget.facing,
          legend: widget.spec.look.legend,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints one puppet fitted to the canvas (feet at 92 % of the height).
class PuppetPainter extends CustomPainter {
  PuppetPainter({
    required this.sprite,
    required this.time,
    this.clip = Anim.idle,
    this.clips,
    this.clipSeconds = 2,
    this.facing = 1,
    this.legend = false,
  }) : super(repaint: time);

  final PuppetSprite sprite;
  final ValueListenable<double> time;
  final Anim clip;
  final List<Anim>? clips;
  final double clipSeconds;
  final int facing;
  final bool legend;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    var c = clip;
    var ct = t;
    final cs = clips;
    if (cs != null && cs.isNotEmpty) {
      final i = (t / clipSeconds).floor();
      c = cs[i % cs.length];
      ct = t - i * clipSeconds;
    }
    final len = kAnimLength[c];
    if (len != null) ct = ct % (len + 0.4); // one-shot clips: replay
    final feet = Offset(size.width / 2, size.height * 0.92);
    final scale = math.min(
      size.height * 0.78 / math.max(1, sprite.height),
      size.width * 0.86 / math.max(1, sprite.width),
    );
    if (legend) {
      paintLegendAura(
        canvas,
        feet.translate(0, -sprite.height * scale * 0.5),
        sprite.height * scale * 0.62,
        t,
      );
    }
    final mirror = sprite.prepare(c, ct, facing);
    final pose = sprite.pose;
    if (pose.glow > 0) {
      paintAura(
        canvas,
        feet.translate(0, -sprite.height * scale * 0.5),
        sprite.height * scale * 0.6,
        const Color(0xFF8FE3FF),
        0.5 * pose.glow,
      );
    }
    sprite.drawPose(canvas, sprite.placement(feet, scale, mirror: mirror));
  }

  @override
  bool shouldRepaint(PuppetPainter old) =>
      old.sprite != sprite ||
      old.clip != clip ||
      old.clips != clips ||
      old.facing != facing ||
      old.legend != legend;
}
