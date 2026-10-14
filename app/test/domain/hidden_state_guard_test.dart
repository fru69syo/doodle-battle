// The hidden late-bloomer mechanic (GAME_DESIGN_V2 §4.4, SPEC §3.5) must
// never reach UI code, UI text, stored or sent data: only domain logic, the
// analyser's admission rule and debug / simulation tooling may name it.
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/data/backend/backend_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Kid- or parent-facing words for the hidden state.
final _hiddenWords = RegExp(
  r'大器晩成|たいき ?ばんせい|ブルーマー|late ?bloomer',
  caseSensitive: false,
);

void main() {
  test('UI, data and core code never read the hidden state', () {
    final pattern = RegExp(r'isBloomer|rebornAt|preForm|\.kid\b');
    final allowed = {
      'lib/features/drawing_analysis/v2_admission.dart',
      // Debug-only 2.5D demo battle (randomised demo fighters).
      'lib/features/battle_stage/debug/demo_battle.dart',
    };
    for (final dir in ['lib/features', 'lib/core', 'lib/data']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.replaceAll('\\', '/');
        if (allowed.any(rel.endsWith)) continue;
        expect(
          pattern.hasMatch(f.readAsStringSync()),
          isFalse,
          reason: '$rel mentions the hidden state',
        );
      }
    }
  });

  test('no string literal in the app names the hidden state', () {
    final literal = RegExp(r"'[^'\n]*'");
    for (final dir in ['lib/features', 'lib/core', 'lib/data']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in literal.allMatches(f.readAsStringSync())) {
          expect(
            _hiddenWords.hasMatch(m.group(0)!),
            isFalse,
            reason: '${f.path}: ${m.group(0)}',
          );
        }
      }
    }
  });

  test('stored and uploaded character data carry no hidden flag', () {
    final bloomer = testCharacter(skill: 95, level: 30);
    for (final json in [
      jsonEncode(bloomer.toJson()),
      jsonEncode(
        RegisterCharacterRequest(character: bloomer, png: testPng()).toJson(),
      ),
    ]) {
      expect(json.toLowerCase(), isNot(contains('bloomer')));
      expect(json, isNot(contains('"kid"')));
      expect(json, isNot(contains('rebirth')));
    }
  });

  testWidgets('a late bloomer\'s pages look like anyone else\'s', (
    tester,
  ) async {
    for (final skill in [20.0, 95.0]) {
      await pumpApp(
        tester,
        characters: [testCharacter(skill: skill, level: 12)],
      );
      await tapVisible(tester, find.byKey(const Key('home-zukan')));
      await tapVisible(tester, find.byKey(const Key('zukan-card-c_1')));
      expect(find.byKey(const Key('detail-level')), findsOneWidget);
      expect(find.textContaining(_hiddenWords), findsNothing);
      for (final w in ['しょぼ', 'よわい えだから', 'じょうず', 'ひみつ']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
      await unmount(tester);
    }
  });
}
