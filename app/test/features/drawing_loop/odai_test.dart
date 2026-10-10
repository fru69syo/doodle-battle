import 'package:doodle_battle/features/drawing_loop/odai/daily_odai.dart';
import 'package:doodle_battle/features/drawing_loop/odai/odai_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final kanji = RegExp(r'[一-鿿㐀-䶿]');
  final allowed = RegExp(r'^[ぁ-ゖァ-ヺー゙-゜ ]+$');

  List<DateTime> daysOf(int year) => [
    for (
      var d = DateTime(year);
      d.year == year;
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];

  group('prompt list', () {
    test('has at least 120 everyday prompts, all distinct', () {
      expect(generalOdai.length, greaterThanOrEqualTo(120));
      expect(generalOdai.toSet().length, generalOdai.length);
    });

    test('everything is kana (no kanji), words separated by spaces', () {
      final all = [
        ...generalOdai,
        for (final p in seasonalOdai.values) ...p,
        for (final e in odaiEvents) ...e.prompts,
      ];
      expect(all.length, greaterThanOrEqualTo(160));
      for (final p in all) {
        expect(kanji.hasMatch(p), isFalse, reason: p);
        expect(allowed.hasMatch(p), isTrue, reason: p);
        expect(p.trim(), p);
        expect(p.contains('  '), isFalse, reason: p);
        expect(p.length, lessThanOrEqualTo(22), reason: 'fits the card: $p');
      }
    });

    test('event windows are valid dates and do not overlap', () {
      final seen = <String>{};
      for (final e in odaiEvents) {
        expect(e.prompts, isNotEmpty);
        for (var d = e.fromDay; d <= e.toDay; d++) {
          final date = DateTime(2028, e.month, d); // leap year
          expect(date.month, e.month, reason: '${e.id} $d');
          expect(seen.add('${e.month}-$d'), isTrue, reason: e.id);
        }
      }
    });
  });

  group('odaiFor', () {
    test('is deterministic for a date, whatever the time of day', () {
      final a = odaiFor(DateTime(2026, 10, 10, 0, 0, 1));
      final b = odaiFor(DateTime(2026, 10, 10, 23, 59, 59));
      final c = odaiFor(DateTime(2026, 10, 10, 12));
      expect(a, b);
      expect(a, c);
      expect(a.text, isNotEmpty);
    });

    test('pinned examples (changing them changes what children saw)', () {
      // 2026-10-10 is day 282 (a season day: 282 % 3 == 0).
      expect(odaiDayNumber(DateTime(2026, 10, 10)), 282);
      expect(odaiFor(DateTime(2026, 10, 10)).text, 'すずむしの がくだん');
      expect(odaiFor(DateTime(2026, 10, 11)).text, 'じてんしゃに のる ペンギン');
      expect(odaiFor(DateTime(2026, 10, 12)).id, 'g19');
      expect(odaiFor(DateTime(2026, 10, 31)).text, 'まじょの ねこ');
      expect(odaiFor(DateTime(2026, 10, 31)).event, 'halloween');
      expect(odaiFor(DateTime(2027, 1, 1)).event, 'oshogatsu');
      expect(odaiFor(DateTime(2026, 12, 24)).event, 'christmas');
      expect(odaiFor(DateTime(2026, 7, 7)).event, 'tanabata');
      expect(odaiFor(DateTime(2027, 5, 5)).event, 'kodomonohi');
    });

    test('day numbers ignore DST / time zones (local calendar date)', () {
      expect(odaiDayNumber(DateTime(2026)), 0);
      expect(odaiDayNumber(DateTime(2025, 12, 31)), -1);
      expect(odaiDayNumber(DateTime.utc(2026, 3, 29, 23)), 87);
      // Negative days (clock set in the past) still work.
      expect(odaiFor(DateTime(2020, 6, 1)).text, isNotEmpty);
    });

    test('consecutive days never repeat a prompt', () {
      for (final year in [2026, 2027, 2028]) {
        final days = daysOf(year);
        for (var i = 1; i < days.length; i++) {
          expect(
            odaiFor(days[i]).text,
            isNot(odaiFor(days[i - 1]).text),
            reason: '${days[i]}',
          );
        }
      }
    });

    test('the general pool is walked through completely', () {
      final seen = <String>{};
      for (final y in [2026, 2027, 2028]) {
        for (final d in daysOf(y)) {
          final t = odaiFor(d);
          if (t.id.startsWith('g')) seen.add(t.text);
        }
      }
      expect(seen.length, generalOdai.length);
    });

    test('seasonal pools follow the month', () {
      for (final d in daysOf(2026)) {
        final t = odaiFor(d);
        if (t.id.startsWith('s_')) {
          expect(t.id, startsWith('s_${seasonOf(d.month)}_'));
          expect(seasonalOdai[seasonOf(d.month)], contains(t.text));
        }
      }
    });

    test('ids map back to the same text', () {
      for (final d in daysOf(2026)) {
        final t = odaiFor(d);
        if (t.id.startsWith('g')) {
          expect(generalOdai[int.parse(t.id.substring(1))], t.text);
        }
      }
    });
  });

  test('date keys round-trip', () {
    expect(localDateKey(DateTime(2026, 3, 4, 23, 59)), '2026-03-04');
    expect(parseDateKey('2026-03-04'), DateTime(2026, 3, 4));
    expect(parseDateKey('2026-3-4'), isNull);
    final b = badgeFor(
      odaiFor(DateTime(2026, 10, 10, 8)),
      DateTime(2026, 10, 10, 8),
    );
    expect(b.date, '2026-10-10');
    expect(b.text, odaiFor(DateTime(2026, 10, 10)).text);
  });
}
