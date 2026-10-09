import words from "./display_name_words.json";

export interface Word {
  id: string;
  text: string;
}
export interface DisplayName {
  adjectiveId: string;
  nounId: string;
  text: string;
}

export const ADJECTIVES: readonly Word[] = words.adjectives;
export const NOUNS: readonly Word[] = words.nouns;

const adjById = new Map(ADJECTIVES.map((w) => [w.id, w]));
const nounById = new Map(NOUNS.map((w) => [w.id, w]));

/** Builds a display name from preset ids, or returns null for unknown ids. */
export function composeDisplayName(adjectiveId: string, nounId: string): DisplayName | null {
  const a = adjById.get(adjectiveId);
  const n = nounById.get(nounId);
  if (!a || !n) return null;
  return { adjectiveId: a.id, nounId: n.id, text: `${a.text} ${n.text}` };
}

/** Random preset display name (`rand` returns [0, 1)). */
export function randomDisplayName(rand: () => number = Math.random): DisplayName {
  const a = ADJECTIVES[Math.floor(rand() * ADJECTIVES.length)] ?? ADJECTIVES[0];
  const n = NOUNS[Math.floor(rand() * NOUNS.length)] ?? NOUNS[0];
  if (!a || !n) throw new Error("display name word lists are empty");
  return { adjectiveId: a.id, nounId: n.id, text: `${a.text} ${n.text}` };
}
