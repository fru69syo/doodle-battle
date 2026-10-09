import { describe, expect, it } from "vitest";
import { StubEngine, typeMultiplier, type ActionId, type FighterInput } from "../../src/battle/engine";
import { chooseGhostAction } from "../../src/battle/ghostAi";
import { computeResults } from "../../src/battle/results";
import { hash32, mulberry32, turnSeed } from "../../src/battle/rng";
import type { MatchDoc, SideInfo } from "../../src/model";

const fire: FighterInput = { element: "fire", stats: { hp: 60, atk: 70, def: 50, spd: 60 }, level: 5 };
const leaf: FighterInput = { element: "leaf", stats: { hp: 60, atk: 60, def: 60, spd: 50 }, level: 5 };

describe("rng", () => {
  it("is deterministic", () => {
    expect(hash32("abc")).toBe(hash32("abc"));
    expect(turnSeed(1, 2)).not.toBe(turnSeed(1, 3));
    const a = mulberry32(42);
    const b = mulberry32(42);
    for (let i = 0; i < 5; i++) {
      const x = a();
      expect(x).toBe(b());
      expect(x).toBeGreaterThanOrEqual(0);
      expect(x).toBeLessThan(1);
    }
  });
});

describe("type chart (SPEC §4.1)", () => {
  it("4-way cycle and shadow/rainbow", () => {
    expect(typeMultiplier("fire", "leaf")).toBe(1.5);
    expect(typeMultiplier("leaf", "thunder")).toBe(1.5);
    expect(typeMultiplier("thunder", "water")).toBe(1.5);
    expect(typeMultiplier("water", "fire")).toBe(1.5);
    expect(typeMultiplier("leaf", "fire")).toBe(0.75);
    expect(typeMultiplier("shadow", "rainbow")).toBe(1.5);
    expect(typeMultiplier("rainbow", "shadow")).toBe(1.5);
    expect(typeMultiplier("shadow", "fire")).toBe(1);
    expect(typeMultiplier("fire", "fire")).toBe(1);
  });
});

describe("StubEngine", () => {
  const engine = new StubEngine();

  function play(seed: number, pick: (turn: number) => [ActionId, ActionId]) {
    let state = engine.init(fire, leaf, seed);
    const log: unknown[] = [];
    for (let t = 1; t <= 60 && !engine.view(state).finished; t++) {
      const [a, b] = pick(t);
      const r = engine.resolveTurn(state, a, b);
      state = r.state;
      log.push(r.events);
    }
    return { state, log };
  }

  it("HP is 3x the hp stat", () => {
    const v = engine.view(engine.init(fire, leaf, 1));
    expect(v.a).toEqual({ hp: 180, maxHp: 180, gauge: 0 });
    expect(v.finished).toBe(false);
  });

  it("is deterministic for the same seed and actions", () => {
    const pick = (): [ActionId, ActionId] => ["element", "tackle"];
    expect(play(7, pick)).toEqual(play(7, pick));
  });

  it("does not mutate the input state and eventually finishes with a winner", () => {
    const s0 = engine.init(fire, leaf, 3);
    const copy = structuredClone(s0);
    engine.resolveTurn(s0, "tackle", "tackle");
    expect(s0).toEqual(copy);
    const { state } = play(3, () => ["element", "element"]);
    const v = engine.view(state);
    expect(v.finished).toBe(true);
    expect(["a", "b"]).toContain(v.winner);
    expect(engine.resolveTurn(state, "tackle", "tackle").events).toEqual([]);
  });

  it("special is only legal with a full gauge; illegal actions fall back to tackle", () => {
    let s = engine.init(fire, leaf, 9);
    expect(engine.legalActions(s, "a")).not.toContain("special");
    const r = engine.resolveTurn(s, "special", "guard");
    expect(r.events.find((e) => e.side === "a")).toMatchObject({ type: "attack", action: "tackle" });
    for (let i = 0; i < 5; i++) s = engine.resolveTurn(s, "tackle", "guard").state;
    expect(engine.legalActions(s, "a")).toContain("special");
  });

  it("guard halves damage, repeated guards weaken", () => {
    const s = engine.init(fire, leaf, 11);
    const r1 = engine.resolveTurn(s, "tackle", "guard");
    expect(r1.events.find((e) => e.type === "guard")).toMatchObject({ reduction: 0.5 });
    const r2 = engine.resolveTurn(r1.state, "tackle", "guard");
    expect(r2.events.find((e) => e.type === "guard")).toMatchObject({ reduction: 0.25 });
  });
});

describe("ghost AI", () => {
  const engine = new StubEngine();
  it("is deterministic and legal", () => {
    const s = engine.init(fire, leaf, 5);
    const a = chooseGhostAction(engine, s, "b", { a: "fire", b: "leaf" });
    expect(chooseGhostAction(engine, s, "b", { a: "fire", b: "leaf" })).toBe(a);
    expect(engine.legalActions(s, "b")).toContain(a);
  });
  it("uses the special as soon as it is ready", () => {
    let s = engine.init(fire, leaf, 5);
    for (let i = 0; i < 5; i++) s = engine.resolveTurn(s, "guard", "tackle").state;
    expect(chooseGhostAction(engine, s, "b", { a: "fire", b: "leaf" })).toBe("special");
  });
});

describe("results", () => {
  const side = (over: Partial<SideInfo>): SideInfo => ({
    uid: "u",
    isGhost: false,
    snapshotId: "s",
    displayName: "あおい ドラゴン",
    characterName: "ねこ",
    element: "fire",
    level: 5,
    isShobo: false,
    evolution: "normal",
    stats: { hp: 1, atk: 1, def: 1, spd: 1 },
    imagePath: "x",
    moveNames: { element: null, special: null },
    rating: 1000,
    ...over,
  });
  const match = (a: Partial<SideInfo>, b: Partial<SideInfo>, mode: MatchDoc["mode"] = "pvp") => ({
    mode,
    sides: { a: side(a), b: side(b) },
  });

  it("win 100 / lose 40 and +-16 Elo at equal ratings", () => {
    expect(computeResults(match({}, {}), "a")).toEqual({
      a: { xp: 100, ratingDelta: 16, outcome: "win" },
      b: { xp: 40, ratingDelta: -16, outcome: "lose" },
    });
  });
  it("しょぼキャラ get +50% xp", () => {
    expect(computeResults(match({ isShobo: true }, { isShobo: true }), "b")).toMatchObject({
      a: { xp: 60 },
      b: { xp: 150 },
    });
  });
  it("draws, ghosts and aborted matches", () => {
    expect(computeResults(match({}, {}), "draw").a).toEqual({ xp: 70, ratingDelta: 0, outcome: "draw" });
    const g = computeResults(match({}, { uid: null, isGhost: true }, "ghost"), "a");
    expect(g.a).toEqual({ xp: 100, ratingDelta: 8, outcome: "win" });
    expect(g.b).toEqual({ xp: 0, ratingDelta: 0, outcome: "none" });
    expect(computeResults(match({}, {}), null).a.outcome).toBe("none");
  });
});
