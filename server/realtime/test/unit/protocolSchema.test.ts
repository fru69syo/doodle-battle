import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { z } from "zod";
import { Cancel, Hello, Omakase, PROTOCOL_REVISION, Ping, Queue, Select } from "../../src/protocol";
import { serverMessageValidator } from "../helpers/schema";

const schema = JSON.parse(readFileSync(resolve(process.cwd(), "protocol.schema.json"), "utf8")) as { $defs: Record<string, unknown> };

function strip(o: unknown): unknown {
  const rest = { ...(o as Record<string, unknown>) };
  delete rest.$schema;
  return rest;
}

describe("protocol.schema.json", () => {
  it("client messages match the zod schemas the server enforces", () => {
    expect(schema.$defs.Hello).toEqual(strip(z.toJSONSchema(Hello)));
    expect(schema.$defs.Queue).toEqual(strip(z.toJSONSchema(Queue)));
    expect(schema.$defs.Cancel).toEqual(strip(z.toJSONSchema(Cancel)));
    expect(schema.$defs.Select).toEqual(strip(z.toJSONSchema(Select)));
    expect(schema.$defs.Ping).toEqual(strip(z.toJSONSchema(Ping)));
    expect(schema.$defs.Omakase).toEqual(strip(z.toJSONSchema(Omakase)));
  });

  it("validates server messages", () => {
    const v = serverMessageValidator();
    expect(v({ t: "welcome", proto: 1, rev: PROTOCOL_REVISION, serverTimeMs: 1, inMatch: false })).toBe(true);
    expect(v({ t: "welcome", proto: 1, rev: 2, serverTimeMs: 1 })).toBe(false);
    expect(v({ t: "omakase", on: true })).toBe(true);
    expect(v({ t: "omakase", on: "yes" })).toBe(false);
    expect(v({ t: "end", matchId: "m", winner: null, reason: "aborted", you: { outcome: "none", xp: 0, badge: "egg", badgeUp: false } })).toBe(true);
    expect(v({ t: "end", matchId: "m", winner: "c", reason: "ko", you: { outcome: "win", xp: 1, badge: "egg", badgeUp: false } })).toBe(false);
  });
});
