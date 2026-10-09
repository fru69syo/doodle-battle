import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { SharedEngine, SPEC, TIMEOUT_ACTION, type ActionId, type FighterInput } from "../../src/battle/engine";
import { chooseGhostAction } from "../../src/battle/ghostAi";
import { computeResults } from "../../src/battle/results";
import { hash32, turnSeed } from "../../src/battle/rng";
import type { MatchDoc, SideInfo } from "../../src/model";
import { xpForBattle, type BattleState } from "../../src/vendor/battle_engine";

const fire: FighterInput = { element: "fire", stats: { hp: 60, atk: 70, def: 50, spd: 60 }, level: 5 };
const leaf: FighterInput = { element: "leaf", stats: { hp: 60, atk: 60, def: 60, spd: 50 }, level: 5 };
const repo = join(__dirname, "..", "..", "..", "..");

describe("seed helpers", () => {
  it("are deterministic", () => {
    expect(hash32("abc")).toBe(hash32("abc"));
    expect(turnSeed(1, 2)).not.toBe(turnSeed(1, 3));
  });
});

describe("shared spec", () => {
  it("vendored battle_spec.json equals the spec embedded in the engine", () => {
    const json: unknown = JSON.parse(readFileSync(join(__dirname, "..", "..", "src", "vendor", "battle_spec", "battle_spec.json"), "utf8"));
    expect(SPEC).toEqual(json);
    expect(TIMEOUT_ACTION).toBe("tackle");
  });
});

describe("SharedEngine", () => {
  const engine = new SharedEngine();

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

  it("id follows the spec version; HP is hp x hpMultiplier", () => {
    expect(engine.id).toBe(`shared-${SPEC.specVersion}`);
    const v = engine.view(engine.init(fire, leaf, 1));
    expect(v.a).toEqual({ hp: 60 * SPEC.hpMultiplier, maxHp: 60 * SPEC.hpMultiplier, gauge: 0 });
    expect(v.finished).toBe(false);
    expect(v.endReason).toBeNull();
  });

  it("is deterministic for the same seed and actions, and survives a JSON round trip", () => {
    const pick = (): [ActionId, ActionId] => ["element", "tackle"];
    expect(play(7, pick)).toEqual(play(7, pick));
    let s = engine.init(fire, leaf, 7);
    for (let i = 0; i < 3; i++) {
      s = JSON.parse(JSON.stringify(engine.resolveTurn(s, "element", "tackle").state)) as typeof s;
    }
    let t = engine.init(fire, leaf, 7);
    for (let i = 0; i < 3; i++) t = engine.resolveTurn(t, "element", "tackle").state;
    expect(s).toEqual(t);
  });

  it("does not mutate the input state and finishes with a winner", () => {
    const s0 = engine.init(fire, leaf, 3);
    const copy = structuredClone(s0);
    engine.resolveTurn(s0, "tackle", "tackle");
    expect(s0).toEqual(copy);
    const { state } = play(3, () => ["element", "element"]);
    const v = engine.view(state);
    expect(v.finished).toBe(true);
    expect(["a", "b"]).toContain(v.winner);
    expect(v.endReason).toBe("ko");
    expect(engine.legalActions(state, "a")).toEqual([]);
    expect(engine.resolveTurn(state, "tackle", "tackle").events).toEqual([]);
  });

  it("ends at the turn cap by HP ratio (turn_limit)", () => {
    const { state } = play(5, () => ["guard", "guard"]);
    const v = engine.view(state);
    expect(v.turn).toBe(SPEC.turnCap);
    expect(v.endReason).toBe("turn_limit");
    expect(["a", "b"]).toContain(v.winner);
  });

  it("special is only legal with a full gauge", () => {
    let s = engine.init(fire, leaf, 9);
    expect(engine.legalActions(s, "a")).not.toContain("special");
    for (let i = 0; i < 6 && !engine.legalActions(s, "a").includes("special"); i++) {
      s = engine.resolveTurn(s, "tackle", "guard").state;
    }
    expect(engine.legalActions(s, "a")).toContain("special");
  });

  it("rejects states of another engine version", () => {
    const other = new SharedEngine({ ...SPEC, specVersion: 999 });
    expect(() => other.view(engine.init(fire, leaf, 1))).toThrow(/shared-999/);
  });

  it("replays every shared golden battle vector exactly", () => {
    const golden = JSON.parse(readFileSync(join(repo, "shared", "battle_spec", "golden_vectors.json"), "utf8")) as {
      vectors: { kind: string; name: string; seed: number; initial: BattleState; turns: [string, string][]; expected: any }[];
    };
    const battles = golden.vectors.filter((v) => v.kind === "battle");
    expect(battles.length).toBeGreaterThanOrEqual(40);
    for (const v of battles) {
      let state = engine.fromInner(structuredClone(v.initial), v.seed, v.seed);
      v.turns.forEach(([a, b], i) => {
        const act = (x: string): ActionId => (x === "timeout" ? TIMEOUT_ACTION : (x as ActionId));
        const r = engine.resolveTurn(state, act(a), act(b), { a: a === "timeout", b: b === "timeout" });
        expect(r.events, `${v.name} turn ${i + 1}`).toEqual(v.expected.events[i]);
        state = r.state;
      });
      expect(state.inner, v.name).toEqual(v.expected.final);
      expect(state.rngState, v.name).toBe(v.expected.rngState);
    }
  });
});

describe("ghost AI", () => {
  const engine = new SharedEngine();
  it("is deterministic and legal", () => {
    const s = engine.init(fire, leaf, 5);
    const a = chooseGhostAction(engine, s, "b");
    expect(chooseGhostAction(engine, s, "b")).toBe(a);
    expect(engine.legalActions(s, "b")).toContain(a);
  });
  it("is the shared ふつう AI: tackles when type-disadvantaged, specials when ready", () => {
    let s = engine.init(fire, leaf, 5);
    const picks = new Set<ActionId>();
    for (let seed = 0; seed < 40; seed++) picks.add(chooseGhostAction(engine, { ...s, seed }, "b"));
    expect([...picks].sort()).toEqual(["guard", "tackle"]);
    for (let i = 0; i < 8 && !engine.legalActions(s, "b").includes("special"); i++) {
      s = engine.resolveTurn(s, "tackle", "guard").state;
    }
    expect(chooseGhostAction(engine, s, "b")).toBe("special");
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
  it("agree with the shared xpForBattle", () => {
    for (const isShobo of [false, true]) {
      const r = computeResults(match({ isShobo }, { isShobo }), "a");
      expect(r.a.xp).toBe(xpForBattle(SPEC, { won: true, isShobo }));
      expect(r.b.xp).toBe(xpForBattle(SPEC, { won: false, isShobo }));
    }
  });
  it("draws, ghosts and aborted matches", () => {
    expect(computeResults(match({}, {}), "draw").a).toEqual({ xp: 40, ratingDelta: 0, outcome: "draw" });
    const g = computeResults(match({}, { uid: null, isGhost: true }, "ghost"), "a");
    expect(g.a).toEqual({ xp: 100, ratingDelta: 8, outcome: "win" });
    expect(g.b).toEqual({ xp: 0, ratingDelta: 0, outcome: "none" });
    expect(computeResults(match({}, {}), null).a.outcome).toBe("none");
  });
});
