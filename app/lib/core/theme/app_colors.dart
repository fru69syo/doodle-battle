import 'package:flutter/material.dart';

import '../../domain/element_type.dart';

/// Bright, high-contrast palette for young children.
abstract final class AppColors {
  static const background = Color(0xFFFFF8E7); // warm paper
  static const ink = Color(0xFF1F1A3D); // near-black text (contrast > 12:1)
  static const primary = Color(0xFFFF6B35); // orange
  static const secondary = Color(0xFF1E88E5); // blue
  static const success = Color(0xFF2E9E44);
  static const danger = Color(0xFFD7263D);
  static const gold = Color(0xFFFFB800);
  static const purple = Color(0xFF7B3FE4);
  static const pink = Color(0xFFE84393);
  static const card = Colors.white;
  static const disabled = Color(0xFFBDBDBD);
  static const hpHigh = Color(0xFF43C443);
  static const hpMid = Color(0xFFFFC107);
  static const hpLow = Color(0xFFE53935);
  static const gauge = Color(0xFF8E44FF);

  static Color element(ElementType e) => switch (e) {
    ElementType.fire => const Color(0xFFE8452C),
    ElementType.water => const Color(0xFF1E7FE0),
    ElementType.leaf => const Color(0xFF2E9E44),
    ElementType.thunder => const Color(0xFFF2B700),
    ElementType.shadow => const Color(0xFF5B3F8C),
    ElementType.rainbow => const Color(0xFFE84393),
  };
}
