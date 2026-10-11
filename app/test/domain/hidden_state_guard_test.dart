// The hidden late-bloomer mechanic (GAME_DESIGN_V2 §4.4) must never reach
// UI code: only domain logic, the analyser's admission rule and debug /
// simulation tooling may name it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI features never read the hidden state', () {
    final pattern = RegExp(r'isBloomer|rebornAt|preForm|\.kid\b');
    final allowed = {
      'lib/features/drawing_analysis/v2_admission.dart',
      // Debug-only 2.5D spike page (randomised demo fighters).
      'lib/features/spike25d/battle/battle_session25.dart',
    };
    for (final f in Directory('lib/features').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final rel = f.path.replaceAll('\\', '/');
      if (allowed.any(rel.endsWith)) continue;
      expect(
        pattern.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '$rel mentions the hidden state',
      );
    }
  });
}
