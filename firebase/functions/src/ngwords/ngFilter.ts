import ngWordsJson from "../vendor/ng_words/ng_words.json";
import { normalizeForMatch, normalizeForPatterns } from "./normalize";

export type NgCategory = "slur" | "sexual" | "violence" | "insult" | "personal_info";

export interface NgHit {
  category: NgCategory;
  kind: "substring" | "exact" | "pattern";
  /** Normalised NG term or pattern id (for logs only; never shown to users). */
  term: string;
}

interface LangLists {
  substring: string[];
  exact: string[];
}
interface NgWordsFile {
  version: number;
  normalizerVersion: number;
  categories: Record<string, Record<string, LangLists>>;
  patterns: { id: string; category: string; regex: string }[];
  allowExact: string[];
}

interface CompiledList {
  substring: { term: string; category: NgCategory }[];
  exact: Map<string, NgCategory>;
  patterns: { id: string; category: NgCategory; re: RegExp }[];
  allowExact: Set<string>;
}

const CATEGORIES: readonly NgCategory[] = ["slur", "sexual", "violence", "insult", "personal_info"];

function asCategory(c: string): NgCategory {
  if ((CATEGORIES as readonly string[]).includes(c)) return c as NgCategory;
  throw new Error(`Unknown NG category: ${c}`);
}

export function compileNgList(file: NgWordsFile): CompiledList {
  const substring: CompiledList["substring"] = [];
  const exact = new Map<string, NgCategory>();
  for (const [catName, langs] of Object.entries(file.categories)) {
    const category = asCategory(catName);
    for (const lists of Object.values(langs)) {
      for (const w of lists.substring) {
        const term = normalizeForMatch(w);
        if (term.length > 0) substring.push({ term, category });
      }
      for (const w of lists.exact) {
        const term = normalizeForMatch(w);
        if (term.length > 0) exact.set(term, category);
      }
    }
  }
  const patterns = file.patterns.map((p) => ({
    id: p.id,
    category: asCategory(p.category),
    re: new RegExp(p.regex, "u"),
  }));
  return {
    substring,
    exact,
    patterns,
    allowExact: new Set(file.allowExact.map(normalizeForMatch)),
  };
}

const defaultList = compileNgList(ngWordsJson);

/** Returns the first NG hit for `text`, or null when the text is clean. */
export function findNgWord(text: string, list: CompiledList = defaultList): NgHit | null {
  const patternForm = normalizeForPatterns(text);
  for (const p of list.patterns) {
    if (p.re.test(patternForm)) return { category: p.category, kind: "pattern", term: p.id };
  }
  const m = normalizeForMatch(text);
  if (m.length === 0 || list.allowExact.has(m)) return null;
  const exactCat = list.exact.get(m);
  if (exactCat) return { category: exactCat, kind: "exact", term: m };
  for (const s of list.substring) {
    if (m.includes(s.term)) return { category: s.category, kind: "substring", term: s.term };
  }
  return null;
}

export function isClean(text: string): boolean {
  return findNgWord(text) === null;
}

export const NG_WORDS_VERSION: number = (ngWordsJson as NgWordsFile).version;
