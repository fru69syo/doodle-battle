import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stage_events.dart';

/// Reusable battle overlay widgets (the integration team wires them to the
/// real screens). They only take plain values, so they work with any
/// engine adapter.
const _ink = Color(0xFF1F1A3D);

/// Element / attribute colour of a move button.
enum MoveTint {
  gu(Color(0xFFE5533D), 'グー'),
  choki(Color(0xFF2F8FE0), 'チョキ'),
  pa(Color(0xFF2EAE5B), 'パー'),
  none(Color(0xFF8E5BE8), 'むぞくせい'),
  special(Color(0xFFE6A100), 'ひっさつ');

  const MoveTint(this.color, this.label);
  final Color color;
  final String label;
}

/// What a move button shows.
class MoveButtonData {
  const MoveButtonData({
    required this.name,
    required this.tint,
    this.spCost = 0,
    this.icon,
  });
  final String name;
  final MoveTint tint;
  final int spCost;

  /// Optional icon for pre-readers (fist, beam, heart...).
  final IconData? icon;
}

/// Icon for a move by its `vfx` (helps children who can not read yet).
IconData moveIconFor(String vfx) => switch (vfx) {
  'punch' || 'burst' => Icons.back_hand,
  'slash' => Icons.content_cut,
  'beam' || 'wave' => Icons.flash_on,
  'orb' || 'glow' => Icons.blur_circular,
  'rain' || 'bubbles' => Icons.water_drop,
  'spiral' => Icons.cyclone,
  'stars' => Icons.star,
  'hearts' => Icons.favorite,
  'leaves' => Icons.eco,
  'sparks' => Icons.bolt,
  'shield' => Icons.shield,
  _ => Icons.auto_awesome,
};

/// Rounded progress bar.
class StageBar extends StatelessWidget {
  const StageBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 12,
    this.glow = false,
  });
  final double value;
  final Color color;
  final double height;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: const Color(0x22000000),
      borderRadius: BorderRadius.circular(height),
      boxShadow: glow
          ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)]
          : null,
    ),
    child: FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: value.clamp(0.0, 1.0),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height),
        ),
      ),
    ),
  );
}

/// ATB gauge: purple while filling, glowing orange when full.
class AtbGauge extends StatelessWidget {
  const AtbGauge({super.key, required this.value, required this.ready});
  final double value;
  final bool ready;

  @override
  Widget build(BuildContext context) => Semantics(
    label: ready ? 'ゲージ まんたん' : 'ゲージ',
    value: '${(value * 100).round()}%',
    child: StageBar(
      key: const Key('atb-gauge'),
      value: value,
      color: ready ? const Color(0xFFFF9A2E) : const Color(0xFF8E44FF),
      height: 10,
      glow: ready,
    ),
  );
}

/// Name, level, HP (green → yellow → red), ATB gauge and status icons.
class FighterStatusPanel extends StatelessWidget {
  const FighterStatusPanel({
    super.key,
    required this.name,
    required this.level,
    required this.hp,
    required this.state,
    this.isPlayer = false,
  });

  final String name;
  final int level;

  /// HP as shown (drops at the visual impact).
  final double hp;
  final StageFighterState state;
  final bool isPlayer;

  @override
  Widget build(BuildContext context) {
    final frac = (hp / math.max(1, state.maxHp)).clamp(0.0, 1.0);
    final hpColor = frac > 0.5
        ? const Color(0xFF43C443)
        : frac > 0.25
        ? const Color(0xFFFFC107)
        : const Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlayer ? const Color(0xFFFF6B35) : const Color(0xFF1E88E5),
          width: 3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isPlayer ? '$name（きみ）' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                'Lv$level',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            label: 'HP',
            value: '${hp.round()}',
            child: StageBar(value: frac, color: hpColor),
          ),
          const SizedBox(height: 5),
          AtbGauge(value: state.gauge, ready: state.ready),
          StatusIcons(state: state),
        ],
      ),
    );
  }
}

/// Round status badges (icon + colour, no reading needed).
class StatusIcons extends StatelessWidget {
  const StatusIcons({super.key, required this.state, this.size = 22});
  final StageFighterState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, Color, String)>[
      if (state.poisoned) (Icons.water_drop, const Color(0xFFB45CFF), 'ねばねば'),
      if (state.paralyzed) (Icons.bolt, const Color(0xFFE6B800), 'ビリビリ'),
      if (state.shield > 0) (Icons.shield, const Color(0xFF3AA0E0), 'まもり'),
      if (state.statUp)
        (Icons.arrow_upward, const Color(0xFFFF7A1A), 'つよく なった'),
      if (state.statDown)
        (Icons.arrow_downward, const Color(0xFF5B7BD5), 'よわく なった'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: [
          for (final (icon, col, label) in items)
            Tooltip(
              message: label,
              child: Semantics(
                label: label,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                  child: Icon(icon, size: size * 0.7, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 5-second ring shown while the player's gauge is full.
class DecisionTimerRing extends StatelessWidget {
  const DecisionTimerRing({
    super.key,
    required this.fraction,
    required this.secondsLeft,
    this.size = 40,
  });
  final double fraction;
  final double secondsLeft;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('decision-ring'),
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            strokeWidth: size / 7,
            color: const Color(0xFFFF6B35),
            backgroundColor: const Color(0x22000000),
          ),
        ),
        Text(
          '${secondsLeft.ceil()}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: size * 0.42,
            color: _ink,
          ),
        ),
      ],
    ),
  );
}

/// おまかせ switch (big, with a robot icon).
class OmakaseToggle extends StatelessWidget {
  const OmakaseToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: 'おまかせ',
    child: InkWell(
      key: const Key('omakase'),
      borderRadius: BorderRadius.circular(24),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFFFE9A8) : const Color(0x11000000),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy,
              color: value ? const Color(0xFFE68A00) : const Color(0xFF8A8A8A),
            ),
            const SizedBox(width: 4),
            const ExcludeSemantics(
              child: Text(
                'おまかせ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    ),
  );
}

/// One move button. [selected]: tapped (さきどり while the gauge fills —
/// yellow frame and 「つぎ！」; 「これ！」 when the gauge is full).
class MoveButton extends StatelessWidget {
  const MoveButton({
    super.key,
    required this.data,
    required this.onTap,
    this.enabled = true,
    this.selected = false,
    this.ready = false,
    this.cooldownSeconds = 0,
  });

  final MoveButtonData data;
  final VoidCallback? onTap;
  final bool enabled, selected, ready;
  final double cooldownSeconds;

  @override
  Widget build(BuildContext context) {
    final col = data.tint.color;
    final on = enabled && onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      selected: selected,
      label: data.name,
      child: GestureDetector(
        onTap: on ? onTap : null,
        child: AnimatedScale(
          scale: selected ? 1.04 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            decoration: BoxDecoration(
              color: on ? col : const Color(0xFFBDBDBD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? const Color(0xFFFFD83A) : Colors.white,
                width: selected ? 5 : 2,
              ),
              boxShadow: [
                if (ready && on)
                  BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 10),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Stack(
              children: [
                Row(
                  children: [
                    if (data.icon != null) ...[
                      Icon(data.icon, color: Colors.white, size: 26),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            data.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              shadows: [
                                Shadow(blurRadius: 2, color: Color(0x88000000)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _tag(data.tint.label),
                              const SizedBox(width: 4),
                              if (data.spCost > 0) _tag('SP${data.spCost}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _tag(
                      ready ? 'これ！' : 'つぎ！',
                      bg: const Color(0xFFFFD83A),
                      fg: _ink,
                    ),
                  ),
                if (cooldownSeconds > 0)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Text(
                      '${cooldownSeconds.ceil()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _tag(
  String t, {
  Color bg = const Color(0x33FFFFFF),
  Color fg = Colors.white,
}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
  child: Text(
    t,
    style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w900),
  ),
);

/// Placeholder for a slot not unlocked yet (Lv10 / Lv50).
class LockedMoveSlot extends StatelessWidget {
  const LockedMoveSlot({super.key, required this.unlockLevel});
  final int unlockLevel;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 60),
    decoration: BoxDecoration(
      color: const Color(0x22000000),
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: Alignment.center,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock, size: 18, color: Color(0x991F1A3D)),
        const SizedBox(width: 4),
        Text(
          'Lv$unlockLevel で おぼえるよ',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0x991F1A3D),
          ),
        ),
      ],
    ),
  );
}

/// The 2×2 move pad: unlocked moves, then locked slots (Lv10, Lv50).
class MovePad extends StatelessWidget {
  const MovePad({
    super.key,
    required this.moves,
    required this.onTap,
    this.selected,
    this.ready = false,
    this.enabled = true,
    this.usable,
    this.cooldownSeconds,
  });

  /// Unlocked moves (2–4).
  final List<MoveButtonData> moves;
  final ValueChanged<int> onTap;

  /// Slot tapped (さきどり / chosen), if any.
  final int? selected;

  /// The gauge is full (buttons glow).
  final bool ready;
  final bool enabled;

  /// Per slot: SP / cooldown allow it now.
  final bool Function(int slot)? usable;
  final double Function(int slot)? cooldownSeconds;

  static const unlockLevels = [1, 1, 10, 50];

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 2.55,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    children: [
      for (var i = 0; i < 4; i++)
        i < moves.length
            ? MoveButton(
                key: Key('move-$i'),
                data: moves[i],
                enabled: enabled && (usable?.call(i) ?? true),
                selected: selected == i,
                ready: ready,
                cooldownSeconds: cooldownSeconds?.call(i) ?? 0,
                onTap: () => onTap(i),
              )
            : LockedMoveSlot(unlockLevel: unlockLevels[i]),
    ],
  );
}

/// The bottom panel: prompt, 5 s ring, おまかせ and the move pad — the
/// spike's layout as one convenience widget.
class BattleControls extends StatelessWidget {
  const BattleControls({
    super.key,
    required this.moves,
    required this.onTap,
    required this.omakase,
    required this.onOmakase,
    this.selected,
    this.choiceLeft,
    this.decisionSeconds = 5,
    this.casting = false,
    this.usable,
    this.cooldownSeconds,
  });

  final List<MoveButtonData> moves;
  final ValueChanged<int> onTap;
  final bool omakase;
  final ValueChanged<bool> onOmakase;
  final int? selected;

  /// Seconds left while the gauge is full (null otherwise).
  final double? choiceLeft;
  final double decisionSeconds;
  final bool casting;
  final bool Function(int slot)? usable;
  final double Function(int slot)? cooldownSeconds;

  @override
  Widget build(BuildContext context) {
    final left = choiceLeft;
    final String prompt;
    if (omakase) {
      prompt = 'おまかせで たたかうよ';
    } else if (left != null) {
      prompt = 'わざを えらんでね！';
    } else if (selected != null) {
      prompt = 'たまったら すぐ だすよ';
    } else if (casting) {
      prompt = 'ためているよ…';
    } else {
      prompt = 'つぎの わざを えらんでおけるよ';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (left != null) ...[
                DecisionTimerRing(
                  fraction: left / decisionSeconds,
                  secondsLeft: left,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  prompt,
                  key: const Key('battle-prompt'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
              ),
              OmakaseToggle(value: omakase, onChanged: onOmakase),
            ],
          ),
          const SizedBox(height: 6),
          MovePad(
            moves: moves,
            onTap: onTap,
            selected: selected,
            ready: left != null,
            enabled: !omakase && !casting,
            usable: usable,
            cooldownSeconds: cooldownSeconds,
          ),
        ],
      ),
    );
  }
}
