import { findNgWord, type NgHit } from "../ngwords/ngFilter";

/** Character name rules for online play. */
export const NAME_MIN_LEN = 1;
export const NAME_MAX_LEN = 10;
const MAX_DIGITS = 2;

/** hiragana, katakana, ー, ・, ASCII letters/digits, CJK ideographs, 々. */
const NAME_CHARS = /^[ぁ-ゖァ-ヺー・々a-zA-Z0-9一-鿿㐀-䶿]+$/u;
/** Kid-facing AI output: kana and ー only. */
const KANA_ONLY = /^[ぁ-ゖァ-ヺー]+$/u;

export type NameProblem = { kind: "invalid" } | { kind: "ng"; hit: NgHit };

/** Normalises an incoming name (NFKC, trims) for storage and checks. */
export function canonicalName(raw: string): string {
  return raw.normalize("NFKC").trim();
}

export function checkCharacterName(raw: string): NameProblem | null {
  const name = canonicalName(raw);
  const len = Array.from(name).length;
  if (len < NAME_MIN_LEN || len > NAME_MAX_LEN || !NAME_CHARS.test(name)) return { kind: "invalid" };
  if ((name.match(/[0-9]/g) ?? []).length > MAX_DIGITS) return { kind: "invalid" };
  const hit = findNgWord(name);
  return hit ? { kind: "ng", hit } : null;
}

/** Sanitises AI-generated kid-facing text; returns null if unusable. */
export function sanitizeKanaText(raw: string, minLen: number, maxLen: number): string | null {
  const s = raw.normalize("NFKC").replace(/\s+/g, "");
  const len = Array.from(s).length;
  if (len < minLen || len > maxLen || !KANA_ONLY.test(s)) return null;
  return findNgWord(s) ? null : s;
}

/** Like sanitizeKanaText but allows a single space between words (subject). */
export function sanitizeSubject(raw: string): string | null {
  const s = raw.normalize("NFKC").trim().replace(/\s+/g, " ");
  const len = Array.from(s).length;
  if (len < 1 || len > 12 || !/^[ぁ-ゖァ-ヺー ]+$/u.test(s)) return null;
  return findNgWord(s) ? null : s;
}
