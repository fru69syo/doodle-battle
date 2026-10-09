import 'package:doodle_battle/core/theme/app_colors.dart';
import 'package:doodle_battle/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every text style uses the bundled font and the ink colour', () {
    final t = buildAppTheme().textTheme;
    for (final s in [
      t.bodyLarge,
      t.bodyMedium,
      t.bodySmall,
      t.titleLarge,
      t.labelLarge,
      t.headlineMedium,
    ]) {
      expect(s?.fontFamily, appFontFamily);
      expect(s?.color, AppColors.ink);
    }
    expect(t.bodyMedium?.fontSize, 16);
  });
}
