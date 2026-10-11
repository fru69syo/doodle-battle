import { describe, expect, it } from "vitest";
import { loadConfig } from "../../src/config";
import { CachedCostMode, COST_MODES, costModeFrom } from "../../src/costMode";
import { createLogger } from "../../src/log";
import { TickLoop } from "../../src/loop";
import { ClientMessage, Hello } from "../../src/protocol";
import { RateLimiter } from "../../src/server";

describe("cost mode", () => {
  it("unknown values fall back to normal", () => {
    expect(costModeFrom("minimal").flags).toEqual(COST_MODES.minimal);
    expect(costModeFrom("broken").mode).toBe("normal");
    expect(costModeFrom(undefined).mode).toBe("normal");
  });

  it("only saving/minimal degrade, and moderation is not a flag at all", () => {
    expect(COST_MODES.normal).toEqual({ cloudJudge: true, cloudMoveGen: true, pvp: true, ghostAfterSec: 20 });
    expect(COST_MODES.saving.cloudJudge).toBe(false);
    expect(COST_MODES.minimal.pvp).toBe(false);
    expect(COST_MODES.minimal.ghostAfterSec).toBeLessThan(COST_MODES.saving.ghostAfterSec);
  });

  it("CachedCostMode refreshes at most once per TTL and keeps the last value on errors", async () => {
    let now = 0;
    let calls = 0;
    let value: unknown = "saving";
    let fail = false;
    const c = new CachedCostMode(
      () => {
        calls++;
        return fail ? Promise.reject(new Error("x")) : Promise.resolve(value);
      },
      1000,
      () => now,
    );
    expect(c.current().mode).toBe("normal"); // first call starts a refresh
    await c.refresh();
    expect(c.current().mode).toBe("saving");
    const before = calls;
    now = 500;
    c.current();
    expect(calls).toBe(before);
    fail = true;
    value = "minimal";
    now = 2000;
    await c.refresh();
    expect(c.current().mode).toBe("saving");
  });
});

describe("protocol schemas", () => {
  it("accepts a valid hello and rejects extra fields", () => {
    expect(Hello.safeParse({ t: "hello", proto: 1, idToken: "dev:alice123" }).success).toBe(true);
    expect(Hello.safeParse({ t: "hello", proto: 1, idToken: "dev:alice123", admin: true }).success).toBe(false);
    expect(Hello.safeParse({ t: "hello", proto: 2, idToken: "dev:alice123" }).success).toBe(false);
  });
  it("select: slot 0..3, integer seq", () => {
    expect(ClientMessage.safeParse({ t: "select", seq: 1, slot: 3 }).success).toBe(true);
    expect(ClientMessage.safeParse({ t: "select", seq: 1, slot: 4 }).success).toBe(false);
    expect(ClientMessage.safeParse({ t: "select", seq: 1.5, slot: 0 }).success).toBe(false);
    expect(ClientMessage.safeParse({ t: "queue", snapshotId: "../etc" }).success).toBe(false);
  });
});

describe("rate limiter", () => {
  it("allows bursts of 10 then 5 per second", () => {
    let now = 0;
    const rl = new RateLimiter(5, 10, () => now);
    let ok = 0;
    for (let i = 0; i < 20; i++) if (rl.take()) ok++;
    expect(ok).toBe(10);
    now = 1000;
    ok = 0;
    for (let i = 0; i < 20; i++) if (rl.take()) ok++;
    expect(ok).toBe(5);
  });
});

describe("config", () => {
  it("refuses the insecure dev auth in production", () => {
    expect(() => loadConfig({ NODE_ENV: "production", AUTH_MODE: "insecure-dev" })).toThrow();
    expect(loadConfig({ NODE_ENV: "production" })).toMatchObject({ requireAppCheck: true, engine: "v3", authMode: "firebase", tickMs: 100 });
    expect(loadConfig({ BATTLE_ENGINE: "dev", REQUIRE_APP_CHECK: "false" })).toMatchObject({ engine: "dev", requireAppCheck: false });
  });
});

describe("logger", () => {
  it("writes one JSON object per line with severity and never throws on errors", () => {
    const lines: string[] = [];
    const log = createLogger({ sink: (l) => lines.push(l), level: "INFO" });
    log.debug("hidden");
    log.info("hello", { event: "x", n: 1 });
    log.error("boom", { err: new Error("bad") });
    expect(lines).toHaveLength(2);
    const first = JSON.parse(lines[0] ?? "{}") as Record<string, unknown>;
    expect(first).toMatchObject({ severity: "INFO", message: "hello", event: "x", n: 1 });
    expect((JSON.parse(lines[1] ?? "{}") as { err: { message: string } }).err.message).toBe("bad");
  });
});

describe("TickLoop", () => {
  it("catches up missed ticks (bounded) and reports lag", async () => {
    let t = 0;
    let ticks = 0;
    const lags: number[] = [];
    const loop = new TickLoop(100, () => ticks++, (ms) => lags.push(ms), 5, () => t);
    loop.start();
    t = 350; // 3 ticks due, timer fires "late"
    await new Promise((r) => setTimeout(r, 150)); // the real timer was set for 100 ms
    loop.stop();
    expect(ticks).toBe(3);
    expect(lags[0]).toBe(250);
  });
});
