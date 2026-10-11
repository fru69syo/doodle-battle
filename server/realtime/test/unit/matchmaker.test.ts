import { describe, expect, it } from "vitest";
import { COST_MODES } from "../../src/costMode";
import { Matchmaker, SAME_PAIR_COOLDOWN_MS } from "../../src/matchmaker";

const normal = COST_MODES.normal;
const entry = (uid: string, rating: number, joinedAtMs = 0) => ({ uid, rating, joinedAtMs, payload: uid });

describe("Matchmaker", () => {
  it("pairs two children within ±100 immediately", () => {
    const mm = new Matchmaker<string>();
    mm.add(entry("a", 1000));
    mm.add(entry("b", 1090));
    const acts = mm.run(0, normal);
    expect(acts).toHaveLength(1);
    expect(acts[0]).toMatchObject({ kind: "pvp", a: { uid: "a" }, b: { uid: "b" } });
    expect(mm.size).toBe(0);
  });

  it("waits while the band is too narrow, then widens by 50 every 5 s", () => {
    const mm = new Matchmaker<string>();
    mm.add(entry("a", 1000));
    mm.add(entry("b", 1240));
    expect(mm.run(0, normal)).toEqual([]);
    expect(mm.run(14_999, normal)).toEqual([]); // band 200
    expect(mm.run(15_000, normal)[0]?.kind).toBe("pvp"); // band 250
  });

  it("both bands must accept: a newcomer's narrow band protects them", () => {
    const mm = new Matchmaker<string>();
    mm.add(entry("old", 1000, 0));
    mm.add(entry("new", 1300, 17_000));
    expect(mm.run(17_000, normal).filter((a) => a.kind === "pvp")).toEqual([]);
  });

  it("prefers the closest rating", () => {
    const mm = new Matchmaker<string>();
    mm.add(entry("a", 1000, 0));
    mm.add(entry("far", 1090, 1));
    mm.add(entry("near", 1010, 2));
    const acts = mm.run(10, normal);
    expect(acts[0]).toMatchObject({ kind: "pvp", a: { uid: "a" }, b: { uid: "near" } });
    expect(mm.has("far")).toBe(true);
  });

  it("falls back to a ghost after 20 s (normal), 8 s (saving), 3 s (minimal)", () => {
    for (const [mode, sec] of [["normal", 20], ["saving", 8], ["minimal", 3]] as const) {
      const mm = new Matchmaker<string>();
      mm.add(entry("a", 1000));
      expect(mm.run(sec * 1000 - 1, COST_MODES[mode])).toEqual([]);
      expect(mm.run(sec * 1000, COST_MODES[mode])).toEqual([{ kind: "ghost", entry: entry("a", 1000) }]);
    }
  });

  it("makes no PvP pairs in minimal mode", () => {
    const mm = new Matchmaker<string>();
    mm.add(entry("a", 1000));
    mm.add(entry("b", 1000));
    expect(mm.run(0, COST_MODES.minimal)).toEqual([]);
    const acts = mm.run(3000, COST_MODES.minimal);
    expect(acts.map((a) => a.kind)).toEqual(["ghost", "ghost"]);
  });

  it("does not pair the same two children again within 60 minutes", () => {
    const mm = new Matchmaker<string>();
    mm.notePair("a", "b", 0);
    mm.add(entry("a", 1000, 1000));
    mm.add(entry("b", 1000, 1000));
    expect(mm.run(1000, normal)).toEqual([]);
    expect(mm.run(21_000, normal).map((a) => a.kind)).toEqual(["ghost", "ghost"]);
    mm.add(entry("a", 1000, SAME_PAIR_COOLDOWN_MS));
    mm.add(entry("b", 1000, SAME_PAIR_COOLDOWN_MS));
    expect(mm.run(SAME_PAIR_COOLDOWN_MS, normal)[0]?.kind).toBe("pvp");
  });

  it("remove() takes a child out of the queue", () => {
    const mm = new Matchmaker<string>();
    mm.add(entry("a", 1000));
    expect(mm.remove("a")?.uid).toBe("a");
    expect(mm.run(60_000, normal)).toEqual([]);
  });
});
