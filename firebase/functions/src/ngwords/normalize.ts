/**
 * Text normaliser shared (by contract) with the Flutter app's offline filter.
 *
 * The exact algorithm is specified by `shared/ng_words/normalize_vectors.json`
 * (`algorithm` + test vectors). Any change here MUST bump `normalizerVersion`
 * in both JSON files and be ported to Dart.
 */

export const NORMALIZER_VERSION = 1;

/** Small kana -> full-size kana (applied after katakana -> hiragana). */
const SMALL_KANA: Readonly<Record<string, string>> = {
  ぁ: "あ",
  ぃ: "い",
  ぅ: "う",
  ぇ: "え",
  ぉ: "お",
  っ: "つ",
  ゃ: "や",
  ゅ: "ゆ",
  ょ: "よ",
  ゎ: "わ",
  ゕ: "か",
  ゖ: "け",
};

/** Leetspeak / look-alike symbols -> latin letters. */
const LEET: Readonly<Record<string, string>> = {
  "0": "o",
  "1": "i",
  "3": "e",
  "4": "a",
  "5": "s",
  "7": "t",
  "8": "b",
  "@": "a",
  $: "s",
  "!": "i",
};

/** ヷヸヹヺ have no hiragana counterpart: map to the unvoiced base kana. */
const RARE_KATAKANA = ["わ", "ゐ", "ゑ", "を"] as const;

const KANJI_DIGITS: Readonly<Record<string, string>> = {
  〇: "0",
  零: "0",
  一: "1",
  二: "2",
  三: "3",
  四: "4",
  五: "5",
  六: "6",
  七: "7",
  八: "8",
  九: "9",
};

function katakanaToHiragana(ch: string): string {
  const cp = ch.codePointAt(0) ?? 0;
  if (cp >= 0x30a1 && cp <= 0x30f6) return String.fromCodePoint(cp - 0x60);
  if (cp >= 0x30f7 && cp <= 0x30fa) return RARE_KATAKANA[cp - 0x30f7] ?? ch;
  return ch;
}

/** Characters that survive the match-form strip step. */
function isKept(ch: string): boolean {
  const cp = ch.codePointAt(0) ?? 0;
  return (
    (cp >= 0x61 && cp <= 0x7a) || // a-z
    (cp >= 0x30 && cp <= 0x39) || // 0-9 (only 2, 6, 9 survive leet)
    (cp >= 0x3041 && cp <= 0x3096) || // hiragana
    cp === 0x3005 || // 々
    (cp >= 0x3400 && cp <= 0x4dbf) || // CJK ext A
    (cp >= 0x4e00 && cp <= 0x9fff) || // CJK unified
    (cp >= 0xf900 && cp <= 0xfaff) || // CJK compatibility
    (cp >= 0x20000 && cp <= 0x3134f) // CJK ext B..G
  );
}

const LEET_RUN_CHAR = /[a-z0-9@$!]/;
const ASCII_LETTER = /[a-z]/;

/**
 * Applies leetspeak only inside maximal runs of `[a-z0-9@$!]` that contain at
 * least one letter, so "sh1t" -> "shit" but "ばか!" and "090" are untouched.
 */
function applyLeet(chars: string[]): string[] {
  const out = chars.slice();
  let i = 0;
  while (i < out.length) {
    if (!LEET_RUN_CHAR.test(out[i] ?? "")) {
      i++;
      continue;
    }
    let j = i;
    let hasLetter = false;
    while (j < out.length && LEET_RUN_CHAR.test(out[j] ?? "")) {
      if (ASCII_LETTER.test(out[j] ?? "")) hasLetter = true;
      j++;
    }
    if (hasLetter) {
      for (let k = i; k < j; k++) {
        const c = out[k] ?? "";
        out[k] = LEET[c] ?? c;
      }
    }
    i = j;
  }
  return out;
}

/**
 * Normalised form used for NG *word* matching.
 *
 * 1. Unicode NFKC (full-width -> ASCII, half-width kana -> full-width, ...)
 * 2. lower-case
 * 3. katakana -> hiragana (ヷヸヹヺ -> わゐゑを)
 * 4. small kana -> full-size kana (っ -> つ, ゃ -> や, ...)
 * 5. leetspeak, only inside maximal runs of [a-z0-9@$!] that contain at least
 *    one a-z letter: 0->o 1->i 3->e 4->a 5->s 7->t 8->b @->a $->s !->i
 * 6. strip everything except a-z, 0-9, hiragana, 々 and CJK ideographs
 *    (removes spaces, ー, 〜, punctuation, symbols, emoji, ゛゜)
 * 7. collapse runs of the same character to one character
 */
export function normalizeForMatch(input: string): string {
  const nfkc = input.normalize("NFKC").toLowerCase();
  const kana = Array.from(nfkc, (raw) => {
    const ch = katakanaToHiragana(raw);
    return SMALL_KANA[ch] ?? ch;
  });
  let out = "";
  let last = "";
  for (const ch of applyLeet(kana)) {
    if (!isKept(ch)) continue;
    if (ch === last) continue;
    out += ch;
    last = ch;
  }
  return out;
}

/** Separators removed before evaluating personal-info regex patterns. */
const PATTERN_SEPARATORS = /[\s\-‐‑‒–—―−ー－~〜()（）[\]【】「」・_/|]/gu;

/**
 * Normalised form used for personal-info *pattern* matching (phone numbers,
 * URLs, e-mail). Digits are preserved (no leetspeak) and kanji numerals become
 * ASCII digits.
 *
 * 1. Unicode NFKC, 2. lower-case, 3. kanji numerals 〇零一二三四五六七八九 -> 0-9,
 * 4. remove whitespace and separators: - ‐ ‑ ‒ – — ― − ー － ~ 〜 ( ) （ ） [ ] 【 】 「 」 ・ _ / |
 */
export function normalizeForPatterns(input: string): string {
  const nfkc = input.normalize("NFKC").toLowerCase();
  let out = "";
  for (const ch of nfkc) out += KANJI_DIGITS[ch] ?? ch;
  return out.replace(PATTERN_SEPARATORS, "");
}
