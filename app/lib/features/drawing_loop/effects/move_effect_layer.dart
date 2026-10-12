/// わざの エフェクト in battle: the child's drawn effect (or a default one)
/// flies from the attacker to the opponent, bursts and fades.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/cosmetics.dart';
import '../../../domain/element_type.dart';

/// One effect to play (set by `applyBattleEvent` on ぞくせいわざ / ひっさつ).
class MoveEffectCue {
  const MoveEffectCue({
    required this.side,
    required this.move,
    required this.tick,
  });

  /// Attacker (0 or 1).
  final int side;
  final DrawnMove move;

  /// Increments for every new cue (re-triggers the animation).
  final int tick;
}

/// Which picture an effect uses: the drawn one when there is one.
enum EffectSprite { custom, fallback }

EffectSprite effectSpriteFor(
  MoveEffectCue cue,
  Map<int, Map<DrawnMove, Uint8List>> drawn,
) => drawn[cue.side]?[cue.move] != null
    ? EffectSprite.custom
    : EffectSprite.fallback;

/// Motion of the effect at animation progress [t] (0..1): position along
/// the path (0 = attacker, 1 = target), scale, opacity and a little wobble
/// ([spin] in half-turns). Flies for 60% of the time, then bursts and
/// fades.
({double travel, double scale, double opacity, double spin}) effectMotion(
  double t,
) {
  const flyEnd = 0.6;
  if (t <= flyEnd) {
    final u = Curves.easeIn.transform(t / flyEnd);
    return (
      travel: u,
      scale: 0.6 + 0.4 * u,
      opacity: 1,
      spin: 0.12 * math.sin(u * 2 * math.pi),
    );
  }
  final u = (t - flyEnd) / (1 - flyEnd);
  return (
    travel: 1,
    scale: 1 + 0.9 * Curves.easeOut.transform(u),
    opacity: 1 - u,
    spin: 0,
  );
}

IconData defaultEffectIcon(ElementType e, DrawnMove move) =>
    move == DrawnMove.special
    ? Icons.star
    : switch (e) {
        ElementType.fire => Icons.local_fire_department,
        ElementType.water => Icons.water_drop,
        ElementType.leaf => Icons.eco,
        ElementType.thunder => Icons.bolt,
        ElementType.shadow => Icons.dark_mode,
        ElementType.rainbow => Icons.auto_awesome,
      };

/// Overlay that plays [cue] between the two fighters. [centerOf] gives each
/// fighter's centre in this layer's coordinates (null while not laid out).
class MoveEffectLayer extends StatefulWidget {
  const MoveEffectLayer({
    super.key,
    required this.cue,
    required this.centerOf,
    required this.elementOf,
    this.drawn = const {},
    this.size = 96,
    this.duration = const Duration(milliseconds: 700),
  });

  final MoveEffectCue? cue;
  final Offset? Function(int side) centerOf;
  final ElementType Function(int side) elementOf;
  final Map<int, Map<DrawnMove, Uint8List>> drawn;
  final double size;
  final Duration duration;

  @override
  State<MoveEffectLayer> createState() => _MoveEffectLayerState();
}

class _MoveEffectLayerState extends State<MoveEffectLayer>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  MoveEffectCue? _playing;
  Offset? _from, _to;
  int _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _maybeStart();
  }

  @override
  void didUpdateWidget(MoveEffectLayer old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  void _maybeStart() {
    final cue = widget.cue;
    if (cue == null || cue.tick == _lastTick) return;
    _lastTick = cue.tick;
    // Positions are known after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final from = widget.centerOf(cue.side);
      final to = widget.centerOf(1 - cue.side);
      if (from == null || to == null) return;
      setState(() {
        _playing = cue;
        _from = from;
        _to = to;
      });
      _c.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted) setState(() => _playing = null);
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cue = _playing;
    if (cue == null || _from == null || _to == null) {
      return const SizedBox.expand();
    }
    final custom = widget.drawn[cue.side]?[cue.move];
    final element = widget.elementOf(cue.side);
    final Widget sprite = custom != null
        ? Image.memory(
            custom,
            key: const Key('move-effect-custom'),
            fit: BoxFit.contain,
            gaplessPlayback: true,
          )
        : Icon(
            defaultEffectIcon(element, cue.move),
            key: const Key('move-effect-default'),
            size: widget.size * 0.8,
            color: cue.move == DrawnMove.special
                ? AppColors.gold
                : AppColors.element(element),
            shadows: const [Shadow(color: Colors.white, blurRadius: 8)],
          );
    // The opponent of side b is below-left: mirror the drawing so it
    // "faces" its direction of travel.
    final mirror = (_to!.dx - _from!.dx) < 0;
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final m = effectMotion(_c.value);
          final p = Offset.lerp(_from, _to, m.travel)!;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: p.dx - widget.size / 2,
                top: p.dy - widget.size / 2,
                width: widget.size,
                height: widget.size,
                child: Opacity(
                  opacity: m.opacity.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: m.spin * math.pi * (mirror ? -1 : 1),
                    child: Transform.scale(
                      scaleX: m.scale * (mirror ? -1 : 1),
                      scaleY: m.scale,
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: sprite,
      ),
    );
  }
}
