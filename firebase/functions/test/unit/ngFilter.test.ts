import { describe, expect, it } from "vitest";
import ngCheck from "../../../../shared/ng_words/ng_check_vectors.json";
import ngWords from "../../../../shared/ng_words/ng_words.json";
import { compileNgList, findNgWord, isClean, NG_WORDS_VERSION } from "../../src/ngwords/ngFilter";
import { NORMALIZER_VERSION, normalizeForMatch } from "../../src/ngwords/normalize";
import { ADJECTIVES, NOUNS } from "../../src/names/displayName";
import { PRESET_CHARACTER_NAMES } from "../../src/names/presetNames";

describe("NG filter golden vectors", () => {
  it("versions match", () => {
    expect(ngCheck.ngWordsVersion).toBe(NG_WORDS_VERSION);
    expect(ngWords.normalizerVersion).toBe(NORMALIZER_VERSION);
  });
  for (const v of ngCheck.vectors) {
    it(`${JSON.stringify(v.input)} -> ${v.blocked ? v.category : "clean"}`, () => {
      const hit = findNgWord(v.input);
      expect(hit !== null).toBe(v.blocked);
      expect(hit?.category ?? null).toBe(v.category);
    });
  }
});

describe("ng_words.json", () => {
  it("every entry survives normalisation (non-empty) and patterns compile", () => {
    for (const langs of Object.values(ngWords.categories)) {
      for (const lists of Object.values(langs)) {
        for (const w of [...lists.substring, ...lists.exact]) expect(normalizeForMatch(w), w).not.toBe("");
      }
    }
    expect(() => compileNgList(ngWords)).not.toThrow();
  });

  it("supports allowExact overrides", () => {
    const list = compileNgList({ ...ngWords, allowExact: ["ばか"] });
    expect(findNgWord("ばか", list)).toBeNull();
    expect(findNgWord("ばかやろう", list)).not.toBeNull();
  });

  it("rejects unknown categories", () => {
    expect(() =>
      compileNgList({ ...ngWords, categories: { nope: { ja: { substring: ["x"], exact: [] } } } }),
    ).toThrow(/Unknown NG category/);
  });
});

describe("preset vocabularies are clean", () => {
  it("all preset character names pass", () => {
    for (const n of PRESET_CHARACTER_NAMES) expect(isClean(n), n).toBe(true);
  });
  it("every display-name combination passes", () => {
    for (const a of ADJECTIVES) for (const n of NOUNS) expect(isClean(`${a.text} ${n.text}`), `${a.text} ${n.text}`).toBe(true);
  });
});
