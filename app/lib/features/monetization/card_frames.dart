import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Cosmetic card frames of the フレームパック (`frame_pack_1`). Purely visual,
/// local only; they never change stats.
enum CardFrame {
  hoshi('hoshi', 'ほし'),
  hana('hana', 'はな'),
  niji('niji', 'にじ');

  const CardFrame(this.id, this.label);
  final String id;
  final String label;

  static CardFrame? byId(String? id) {
    for (final f in values) {
      if (f.id == id) return f;
    }
    return null;
  }
}

const _rainbow = [
  Color(0xFFE8452C),
  Color(0xFFFF9F1C),
  Color(0xFFF2B700),
  Color(0xFF2E9E44),
  Color(0xFF1E7FE0),
  Color(0xFF7B3FE4),
  Color(0xFFE84393),
];

/// Draws [frame] around [child] (which keeps its own evolution frame inside).
class CardFrameBorder extends StatelessWidget {
  const CardFrameBorder({
    super.key,
    required this.frame,
    required this.size,
    required this.child,
  });

  final CardFrame frame;
  final double size;

  /// Built at [innerSize].
  final Widget child;

  static double innerSizeOf(double size) => size * 0.86;

  @override
  Widget build(BuildContext context) {
    final ring = size * 0.07;
    final decoration = switch (frame) {
      CardFrame.hoshi => BoxDecoration(
        color: const Color(0xFFFFE066),
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: AppColors.gold, width: 3),
      ),
      CardFrame.hana => BoxDecoration(
        color: const Color(0xFFFFC2DC),
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: AppColors.pink, width: 3),
      ),
      CardFrame.niji => BoxDecoration(
        gradient: const SweepGradient(colors: [..._rainbow, Color(0xFFE8452C)]),
        borderRadius: BorderRadius.circular(size * 0.18),
      ),
    };
    final (IconData icon, Color color) = switch (frame) {
      CardFrame.hoshi => (Icons.star, const Color(0xFFFF9F1C)),
      CardFrame.hana => (Icons.local_florist, AppColors.pink),
      CardFrame.niji => (Icons.auto_awesome, Colors.white),
    };
    final ornament = size * 0.16;
    Widget corner(Alignment a) => Align(
      alignment: a,
      child: Icon(
        icon,
        size: ornament,
        color: color,
        shadows: const [Shadow(blurRadius: 2, color: Colors.black26)],
      ),
    );
    return SizedBox(
      key: Key('card-frame-${frame.id}'),
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: decoration,
              child: Padding(
                padding: EdgeInsets.all(ring),
                child: Center(child: child),
              ),
            ),
          ),
          corner(Alignment.topLeft),
          corner(Alignment.topRight),
          corner(Alignment.bottomLeft),
          corner(Alignment.bottomRight),
        ],
      ),
    );
  }
}
