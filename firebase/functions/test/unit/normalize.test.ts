import { describe, expect, it } from "vitest";
import vectorsFile from "../../../../shared/ng_words/normalize_vectors.json";
import { NORMALIZER_VERSION, normalizeForMatch, normalizeForPatterns } from "../../src/ngwords/normalize";

describe("normaliser golden vectors (shared with the Dart port)", () => {
  it("has the same normalizer version", () => {
    expect(vectorsFile.normalizerVersion).toBe(NORMALIZER_VERSION);
  });
  for (const v of vectorsFile.vectors) {
    it(`${JSON.stringify(v.input)} (${v.note})`, () => {
      expect(normalizeForMatch(v.input)).toBe(v.match);
      expect(normalizeForPatterns(v.input)).toBe(v.pattern);
    });
  }
});

describe("normalizeForMatch", () => {
  it("is idempotent", () => {
    for (const v of vectorsFile.vectors) expect(normalizeForMatch(v.match)).toBe(v.match);
  });
  it("only applies leet inside runs that contain a letter", () => {
    expect(normalizeForMatch("b4k4")).toBe("baka");
    expect(normalizeForMatch("ばか4")).toBe("ばか4");
  });
  it("handles astral-plane characters without breaking surrogate pairs", () => {
    expect(normalizeForMatch("𠮷𠮷野家")).toBe("𠮷野家");
  });
});
