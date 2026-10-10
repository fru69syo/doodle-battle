import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/element_badge.dart';
import '../../domain/battle/battle.dart';
import '../drawing_loop/effects/move_effect_layer.dart';
import 'battle_display.dart';

/// The battle field: opponent top, player bottom, message box. ぞくせいわざ
/// and ひっさつ play a flying effect: the child's drawn one from
/// [effectImages] when there is one, otherwise a default (docs/LOOP.md §3).
class BattleArena extends StatefulWidget {
  const BattleArena({
    super.key,
    required this.display,
    required this.pictures,
    required this.gaugeMax,
    this.playerSide = Side.a,
    this.effectImages = const {},
  });

  final BattleDisplay display;
  final Map<Side, Widget> pictures;
  final int gaugeMax;
  final Side playerSide;

  /// Drawn move effects by side and move (missing → default effect).
  final Map<Side, Map<BattleAction, Uint8List>> effectImages;

  @override
  State<BattleArena> createState() => _BattleArenaState();
}

class _BattleArenaState extends State<BattleArena> {
  final _stackKey = GlobalKey();
  final _spriteKeys = {Side.a: GlobalKey(), Side.b: GlobalKey()};

  Offset? _centerOf(Side side) {
    final sprite = _spriteKeys[side]!.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (sprite is! RenderBox || stack is! RenderBox) return null;
    if (!sprite.hasSize || !stack.hasSize) return null;
    return stack.globalToLocal(
      sprite.localToGlobal(sprite.size.center(Offset.zero)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.display;
    final me = widget.playerSide;
    final opp = me.other;
    return Stack(
      key: _stackKey,
      children: [
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: FighterStatus(
                    side: opp,
                    f: display[opp],
                    gaugeMax: widget.gaugeMax,
                  ),
                ),
                FighterSprite(
                  key: _spriteKeys[opp],
                  f: display[opp],
                  picture: widget.pictures[opp]!,
                  size: 130,
                ),
              ],
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(height: 8, width: double.infinity),
                if (display.banner != null)
                  Text(
                    display.banner!,
                    key: const Key('battle-banner'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                FighterSprite(
                  key: _spriteKeys[me],
                  f: display[me],
                  picture: widget.pictures[me]!,
                  size: 150,
                ),
                Expanded(
                  child: FighterStatus(
                    side: me,
                    f: display[me],
                    gaugeMax: widget.gaugeMax,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MessageBox(text: display.message),
          ],
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: MoveEffectLayer(
              cue: display.effectCue,
              centerOf: _centerOf,
              elementOf: (s) => display[s].element,
              drawn: widget.effectImages,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 72),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.ink, width: 3),
    ),
    child: Text(
      text,
      key: const Key('battle-message'),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
  );
}

/// Name, level, HP bar and ひっさつ gauge.
class FighterStatus extends StatelessWidget {
  const FighterStatus({
    super.key,
    required this.side,
    required this.f,
    required this.gaugeMax,
  });

  final Side side;
  final FighterDisplay f;
  final int gaugeMax;

  @override
  Widget build(BuildContext context) {
    final ratio = f.maxHp == 0 ? 0.0 : f.hp / f.maxHp;
    final hpColor = ratio > 0.5
        ? AppColors.hpHigh
        : ratio > 0.2
        ? AppColors.hpMid
        : AppColors.hpLow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Lv${f.level}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                ElementBadge(f.element),
                if (f.guarding)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.shield, color: AppColors.secondary),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _Bar(value: ratio, color: hpColor, height: 16),
            Text(
              '${f.hp} / ${f.maxHp}',
              key: Key('hp-${side.name}'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('ゲージ ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: _Bar(
                    value: f.gauge / gaugeMax,
                    color: AppColors.gauge,
                    height: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.height});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 500),
      builder: (context, v, _) => LinearProgressIndicator(
        value: v,
        minHeight: height,
        color: color,
        backgroundColor: const Color(0xFFE6E0D4),
      ),
    ),
  );
}

/// The drawing with hop (attack), shake (hit), damage number and faint.
class FighterSprite extends StatefulWidget {
  const FighterSprite({
    super.key,
    required this.f,
    required this.picture,
    required this.size,
  });

  final FighterDisplay f;
  final Widget picture;
  final double size;

  @override
  State<FighterSprite> createState() => _FighterSpriteState();
}

class _FighterSpriteState extends State<FighterSprite>
    with TickerProviderStateMixin {
  late final _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late int _hopTick = widget.f.hopTick;
  late int _shakeTick = widget.f.shakeTick;

  @override
  void didUpdateWidget(FighterSprite old) {
    super.didUpdateWidget(old);
    if (widget.f.hopTick != _hopTick) {
      _hopTick = widget.f.hopTick;
      _hop.forward(from: 0);
    }
    if (widget.f.shakeTick != _shakeTick) {
      _shakeTick = widget.f.shakeTick;
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_hop, _shake]),
            builder: (context, child) => Transform.translate(
              offset: Offset(
                sin(_shake.value * pi * 6) * 10 * (1 - _shake.value),
                -sin(_hop.value * pi) * 24,
              ),
              child: child,
            ),
            child: AnimatedOpacity(
              opacity: f.fainted ? 0.15 : 1,
              duration: const Duration(milliseconds: 600),
              child: AnimatedRotation(
                turns: f.fainted ? 0.25 : 0,
                duration: const Duration(milliseconds: 600),
                child: widget.picture,
              ),
            ),
          ),
          if (f.lastDamage != null)
            Positioned(
              top: -8,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(f.damageTick),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                builder: (context, v, _) => Opacity(
                  opacity: (1 - v).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -30 * v),
                    child: Text(
                      '-${f.lastDamage}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                        shadows: [Shadow(color: Colors.white, blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The four move buttons (2 × 2).
class MoveButtons extends StatelessWidget {
  const MoveButtons({
    super.key,
    required this.labels,
    required this.enabled,
    required this.specialReady,
    required this.onMove,
  });

  final String Function(BattleAction) labels;
  final bool enabled;
  final bool specialReady;
  final ValueChanged<BattleAction> onMove;

  static const _colors = {
    BattleAction.tackle: AppColors.primary,
    BattleAction.element: AppColors.secondary,
    BattleAction.guard: AppColors.success,
    BattleAction.special: AppColors.purple,
  };

  @override
  Widget build(BuildContext context) {
    Widget button(BattleAction a) {
      final on = enabled && (a != BattleAction.special || specialReady);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FilledButton(
            key: Key('move-${a.name}'),
            style: FilledButton.styleFrom(
              backgroundColor: _colors[a],
              minimumSize: const Size(56, 64),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: on ? () => onMove(a) : null,
            child: FittedBox(child: Text(labels(a))),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [button(BattleAction.tackle), button(BattleAction.element)],
        ),
        Row(
          children: [button(BattleAction.guard), button(BattleAction.special)],
        ),
      ],
    );
  }
}
