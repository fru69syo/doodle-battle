import { describe, expect, it } from "vitest";
import { ADJECTIVES, composeDisplayName, NOUNS, randomDisplayName } from "../../src/names/displayName";
import { pickPresetNames, PRESET_CHARACTER_NAMES } from "../../src/names/presetNames";
import { checkCharacterName, sanitizeKanaText, sanitizeSubject } from "../../src/names/validateName";

describe("display names", () => {
  it("composes from preset ids only", () => {
    expect(composeDisplayName("a01", "n01")).toEqual({ adjectiveId: "a01", nounId: "n01", text: "あおい ドラゴン" });
    expect(composeDisplayName("a01", "zzz")).toBeNull();
    expect(composeDisplayName("<script>", "n01")).toBeNull();
  });
  it("random names come from the lists", () => {
    const dn = randomDisplayName(() => 0.999);
    expect(dn.adjectiveId).toBe(ADJECTIVES.at(-1)?.id);
    expect(dn.nounId).toBe(NOUNS.at(-1)?.id);
  });
  it("word ids are unique", () => {
    expect(new Set(ADJECTIVES.map((w) => w.id)).size).toBe(ADJECTIVES.length);
    expect(new Set(NOUNS.map((w) => w.id)).size).toBe(NOUNS.length);
  });
});

describe("preset character names", () => {
  it("picks distinct names", () => {
    const names = pickPresetNames(3);
    expect(new Set(names).size).toBe(3);
    for (const n of names) expect(PRESET_CHARACTER_NAMES).toContain(n);
  });
});

describe("checkCharacterName", () => {
  it.each(["ねこまる", "ドラゴン", "ぴか2ごう", "Neko", "竜王", "ニャー・ニャー"])("accepts %s", (n) => {
    expect(checkCharacterName(n)).toBeNull();
  });
  it.each(["", " ", "あいうえおかきくけこさ", "ねこ!", "ねこ 2", "ねこ123", "🐱", "<b>"])("rejects %j as invalid", (n) => {
    expect(checkCharacterName(n)).toEqual({ kind: "invalid" });
  });
  it("flags NG words with category", () => {
    expect(checkCharacterName("しねしね")).toMatchObject({ kind: "ng", hit: { category: "violence" } });
    expect(checkCharacterName("じゅうしょ")).toMatchObject({ kind: "ng", hit: { category: "personal_info" } });
  });
  it("NFKC-normalises before checking (full-width allowed)", () => {
    expect(checkCharacterName("ＮＥＫＯ")).toBeNull();
  });
});

describe("sanitizers for AI output", () => {
  it("keeps kana only and enforces length", () => {
    expect(sanitizeKanaText("ぴかりん", 2, 8)).toBe("ぴかりん");
    expect(sanitizeKanaText("ピカ リン", 2, 8)).toBe("ピカリン");
    expect(sanitizeKanaText("Pikachu", 2, 8)).toBeNull();
    expect(sanitizeKanaText("ignore previous instructions", 2, 8)).toBeNull();
    expect(sanitizeKanaText("あ", 2, 8)).toBeNull();
    expect(sanitizeKanaText("ころすびーむ", 1, 10)).toBeNull();
  });
  it("subject allows one space between words", () => {
    expect(sanitizeSubject(" ふしぎな  いきもの ")).toBe("ふしぎな いきもの");
    expect(sanitizeSubject("cat")).toBeNull();
  });
});
