import 'dart:math';

/// One multiplication question of the parental gate (SPEC §7: 2-digit ×
/// 1-digit, shown with digits and kanji — not hiragana).
class ParentalGateChallenge {
  const ParentalGateChallenge(this.a, this.b)
    : assert(a >= 10 && a <= 99),
      assert(b >= 2 && b <= 9);

  /// Two-digit operand (never a multiple of 10, which would be too easy).
  factory ParentalGateChallenge.random(Random random) {
    int a;
    do {
      a = 11 + random.nextInt(89);
    } while (a % 10 == 0);
    return ParentalGateChallenge(a, 3 + random.nextInt(7));
  }

  final int a;
  final int b;

  int get answer => a * b;

  /// e.g. 「23 × 7 ＝ ？」
  String get digitsText => '$a × $b ＝ ？';

  /// e.g. 「二十三 かける 七」
  String get kanjiText => '${kanjiNumber(a)} かける ${kanjiNumber(b)}';

  bool check(String input) => int.tryParse(input.trim()) == answer;
}

const _kanjiDigits = ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// Kanji numeral for 0..999 (e.g. 23 → 二十三, 105 → 百五).
String kanjiNumber(int n) {
  if (n < 0 || n > 999) throw RangeError.range(n, 0, 999);
  if (n == 0) return _kanjiDigits[0];
  final out = StringBuffer();
  final hundreds = n ~/ 100;
  final tens = (n ~/ 10) % 10;
  final ones = n % 10;
  if (hundreds > 0) {
    if (hundreds > 1) out.write(_kanjiDigits[hundreds]);
    out.write('百');
  }
  if (tens > 0) {
    if (tens > 1) out.write(_kanjiDigits[tens]);
    out.write('十');
  }
  if (ones > 0) out.write(_kanjiDigits[ones]);
  return out.toString();
}
