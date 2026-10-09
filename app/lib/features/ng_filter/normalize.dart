/// Dart port of the shared NG-word text normaliser
/// (`firebase/functions/src/ngwords/normalize.ts`).
///
/// The normative algorithm and golden vectors live in
/// `shared/ng_words/normalize_vectors.json`; `test/features/ng_filter/`
/// checks every vector. Any change MUST bump `normalizerVersion` there and be
/// mirrored in the TypeScript implementation.
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Must equal `normalizerVersion` in the shared JSON files.
const int normalizerVersion = 1;

/// Small kana -> full-size kana (applied after katakana -> hiragana).
const Map<String, String> _smallKana = {
  'ぁ': 'あ',
  'ぃ': 'い',
  'ぅ': 'う',
  'ぇ': 'え',
  'ぉ': 'お',
  'っ': 'つ',
  'ゃ': 'や',
  'ゅ': 'ゆ',
  'ょ': 'よ',
  'ゎ': 'わ',
  'ゕ': 'か',
  'ゖ': 'け',
};

/// Leetspeak / look-alike symbols -> latin letters.
const Map<String, String> _leet = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '8': 'b',
  '@': 'a',
  r'$': 's',
  '!': 'i',
};

/// ヷヸヹヺ have no hiragana counterpart: map to the unvoiced base kana.
const List<String> _rareKatakana = ['わ', 'ゐ', 'ゑ', 'を'];

const Map<String, String> _kanjiDigits = {
  '〇': '0',
  '零': '0',
  '一': '1',
  '二': '2',
  '三': '3',
  '四': '4',
  '五': '5',
  '六': '6',
  '七': '7',
  '八': '8',
  '九': '9',
};

String _nfkcLower(String input) => unorm.nfkc(input).toLowerCase();

/// Splits into Unicode scalar values (like JS `Array.from(str)`).
List<String> _codePoints(String s) => [
  for (final r in s.runes) String.fromCharCode(r),
];

String _katakanaToHiragana(String ch) {
  final cp = ch.runes.first;
  if (cp >= 0x30a1 && cp <= 0x30f6) return String.fromCharCode(cp - 0x60);
  if (cp >= 0x30f7 && cp <= 0x30fa) return _rareKatakana[cp - 0x30f7];
  return ch;
}

/// Characters that survive the match-form strip step.
bool _isKept(String ch) {
  final cp = ch.runes.first;
  return (cp >= 0x61 && cp <= 0x7a) || // a-z
      (cp >= 0x30 && cp <= 0x39) || // 0-9
      (cp >= 0x3041 && cp <= 0x3096) || // hiragana
      cp == 0x3005 || // 々
      (cp >= 0x3400 && cp <= 0x4dbf) || // CJK ext A
      (cp >= 0x4e00 && cp <= 0x9fff) || // CJK unified
      (cp >= 0xf900 && cp <= 0xfaff) || // CJK compatibility
      (cp >= 0x20000 && cp <= 0x3134f); // CJK ext B..G
}

final RegExp _leetRunChar = RegExp(r'^[a-z0-9@$!]$');
final RegExp _asciiLetter = RegExp(r'^[a-z]$');

/// Applies leetspeak only inside maximal runs of `[a-z0-9@$!]` that contain
/// at least one letter, so "sh1t" -> "shit" but "ばか!" and "090" stay.
List<String> _applyLeet(List<String> chars) {
  final out = List.of(chars);
  var i = 0;
  while (i < out.length) {
    if (!_leetRunChar.hasMatch(out[i])) {
      i++;
      continue;
    }
    var j = i;
    var hasLetter = false;
    while (j < out.length && _leetRunChar.hasMatch(out[j])) {
      if (_asciiLetter.hasMatch(out[j])) hasLetter = true;
      j++;
    }
    if (hasLetter) {
      for (var k = i; k < j; k++) {
        out[k] = _leet[out[k]] ?? out[k];
      }
    }
    i = j;
  }
  return out;
}

/// Normalised form used for NG *word* matching (see the shared algorithm):
/// NFKC → lower-case → katakana→hiragana → small kana → leet (ASCII runs with
/// a letter) → keep a-z/0-9/hiragana/々/kanji → collapse repeats.
String normalizeForMatch(String input) {
  final kana = [
    for (final raw in _codePoints(_nfkcLower(input)))
      () {
        final ch = _katakanaToHiragana(raw);
        return _smallKana[ch] ?? ch;
      }(),
  ];
  final out = StringBuffer();
  var last = '';
  for (final ch in _applyLeet(kana)) {
    if (!_isKept(ch)) continue;
    if (ch == last) continue;
    out.write(ch);
    last = ch;
  }
  return out.toString();
}

/// Separators removed before evaluating personal-info regex patterns.
final RegExp _patternSeparators = RegExp(
  r'[\s\-‐‑‒–—―−ー－~〜()（）\[\]【】「」・_/|]',
  unicode: true,
);

/// Normalised form used for personal-info *pattern* matching: NFKC →
/// lower-case → kanji numerals → strip whitespace and separators.
String normalizeForPatterns(String input) {
  final out = StringBuffer();
  for (final ch in _codePoints(_nfkcLower(input))) {
    out.write(_kanjiDigits[ch] ?? ch);
  }
  return out.toString().replaceAll(_patternSeparators, '');
}
