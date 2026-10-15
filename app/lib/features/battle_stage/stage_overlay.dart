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
    this.bars = 1,
    this.icon,
  });
  final String name;
  final MoveTint tint;

  /// Cost in gauge bars (shown as pips).
  final int bars;

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

/// The gauge: [maxBars] segments, each filling in turn (partial fill
/// shown). Full segments turn orange; all full = glow (it stopped filling).
/// Plain rectangles only, cheap on old Android.
class AtbGauge extends StatelessWidget {
  const AtbGauge({super.key, required this.bars, required this.maxBars});

  /// 0..[maxBars] (2.4 = two full bars and 40 % of the third).
  final double bars;
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    final full = bars.floor().clamp(0, maxBars);
    final all = full >= maxBars;
    return Semantics(
      label: all ? 'ゲージ まんたん' : 'ゲージ',
      value: '$full/$maxBars',
      child: Row(
        key: const Key('atb-gauge'),
        children: [
          for (var i = 0; i < maxBars; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: StageBar(
                key: Key('atb-bar-$i'),
                value: (bars - i).clamp(0.0, 1.0),
                color: i < full
                    ? const Color(0xFFFF9A2E)
                    : const Color(0xFF8E44FF),
                height: 10,
                glow: all,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small bar pips: the cost of a move in bars.
class BarPips extends StatelessWidget {
  const BarPips({
    super.key,
    required this.count,
    this.color = Colors.white,
    this.size = 9,
  });
  final int count;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ゲージ $count',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: size * 1.5,
            height: size,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(size / 3),
              border: Border.all(color: const Color(0x55000000)),
            ),
          ),
      ],
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
          AtbGauge(bars: state.gauge, maxBars: state.maxBars),
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

/// One move button with its cost as bar pips. [selected]: tapped (さきどり
/// — yellow frame and 「つぎ！」 until its bars are there). [affordable]:
/// enough bars and no cooldown right now; an unaffordable move is dimmed
/// but can still be tapped (it fires once the bars are there).
class MoveButton extends StatelessWidget {
  const MoveButton({
    super.key,
    required this.data,
    required this.onTap,
    this.enabled = true,
    this.affordable = true,
    this.selected = false,
    this.cooldownSeconds = 0,
  });

  final MoveButtonData data;
  final VoidCallback? onTap;
  final bool enabled, affordable, selected;
  final double cooldownSeconds;

  @override
  Widget build(BuildContext context) {
    final col = data.tint.color;
    final on = enabled && onTap != null;
    final bright = on && affordable;
    return Semantics(
      button: true,
      enabled: on,
      selected: selected,
      label: '${data.name} ゲージ${data.bars}',
      child: GestureDetector(
        onTap: on ? onTap : null,
        child: AnimatedScale(
          scale: selected ? 1.04 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            decoration: BoxDecoration(
              color: !on
                  ? const Color(0xFFBDBDBD)
                  : (bright ? col : Color.lerp(col, Colors.white, 0.45)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? const Color(0xFFFFD83A) : Colors.white,
                width: selected ? 5 : 2,
              ),
              boxShadow: [
                if (bright)
                  BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 10),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Stack(
              clipBehavior: Clip.none,
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
                          // Scales down on narrow phones / big text.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BarPips(
                                  key: const Key('move-pips'),
                                  count: data.bars,
                                ),
                                const SizedBox(width: 4),
                                _tag(data.tint.label),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    right: -6,
                    top: -16,
                    child: _tag('つぎ！', bg: const Color(0xFFFFD83A), fg: _ink),
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
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
    this.enabled = true,
    this.usable,
    this.queueable,
    this.cooldownSeconds,
  });

  /// Unlocked moves (2–4).
  final List<MoveButtonData> moves;
  final ValueChanged<int> onTap;

  /// Slot tapped (さきどり / chosen), if any.
  final int? selected;
  final bool enabled;

  /// Per slot: enough bars and no cooldown now (else dimmed).
  final bool Function(int slot)? usable;

  /// Per slot: may be tapped for さきどり (its cost fits the max bars).
  final bool Function(int slot)? queueable;
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
                enabled: enabled && (queueable?.call(i) ?? true),
                affordable: usable?.call(i) ?? true,
                selected: selected == i,
                cooldownSeconds: cooldownSeconds?.call(i) ?? 0,
                onTap: () => onTap(i),
              )
            : LockedMoveSlot(unlockLevel: unlockLevels[i]),
    ],
  );
}

/// The bottom panel: prompt, おまかせ and the move pad — one convenience
/// widget. There is no countdown: the gauge just stops when every bar is
/// full.
class BattleControls extends StatelessWidget {
  const BattleControls({
    super.key,
    required this.moves,
    required this.onTap,
    required this.omakase,
    required this.onOmakase,
    this.selected,
    this.bars = 0,
    this.full = false,
    this.casting = false,
    this.usable,
    this.queueable,
    this.cooldownSeconds,
  });

  final List<MoveButtonData> moves;
  final ValueChanged<int> onTap;
  final bool omakase;
  final ValueChanged<bool> onOmakase;
  final int? selected;

  /// The player's full bars now, and whether every bar is full.
  final int bars;
  final bool full;
  final bool casting;
  final bool Function(int slot)? usable;
  final bool Function(int slot)? queueable;
  final double Function(int slot)? cooldownSeconds;

  @override
  Widget build(BuildContext context) {
    final String prompt;
    if (omakase) {
      prompt = 'おまかせで たたかうよ';
    } else if (casting) {
      prompt = 'ためているよ…';
    } else if (selected != null) {
      prompt = 'たまったら すぐ だすよ';
    } else if (full) {
      prompt = 'ゲージ まんたん！ わざを えらんでね';
    } else if (bars > 0) {
      prompt = 'わざを えらんでね！';
    } else {
      prompt = 'ゲージを ためているよ';
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
            enabled: !omakase && !casting,
            usable: usable,
            queueable: queueable,
            cooldownSeconds: cooldownSeconds,
          ),
        ],
      ),
    );
  }
}
