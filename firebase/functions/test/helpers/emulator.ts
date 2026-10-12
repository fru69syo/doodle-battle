import type { CallableRequest } from "firebase-functions/v2/https";
import { afterEach, beforeEach, vi } from "vitest";
import { setAiServiceForTesting, type AiService, type DrawingJudgement, type ModerationVerdict } from "../../src/ai";
import { resetCostModeCacheForTesting } from "../../src/cost/costMode";
import { codeOf } from "../../src/lib/errors";
import { clock } from "../../src/lib/clock";
import { bucket, COL, db } from "../../src/lib/firebase";
import { PROJECT_ID } from "./setupEmulator";
import { pngBase64 } from "./png";

export async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST ?? "";
  const res = await fetch(`http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
    method: "DELETE",
  });
  if (!res.ok) throw new Error(`clearFirestore failed: ${res.status}`);
}

export async function clearStorage(): Promise<void> {
  await bucket().deleteFiles({ force: true });
}

export async function storageFiles(): Promise<string[]> {
  const [files] = await bucket().getFiles();
  return files.map((f) => f.name);
}

export function req(uid: string | null, data: unknown): CallableRequest<unknown> {
  return {
    data,
    auth: uid ? { uid, token: { uid } as never, rawToken: "" } : undefined,
    rawRequest: {} as never,
    acceptsStreaming: false,
  };
}

export async function seedUser(
  uid: string,
  consent: { cloudJudge?: boolean; online?: boolean } = { cloudJudge: true, online: true },
  extra: Record<string, unknown> = {},
): Promise<void> {
  await db()
    .collection(COL.users)
    .doc(uid)
    .set({ consent: { cloudJudge: false, online: false, policyVersion: 1, ...consent }, ...extra });
}

/** Captures the error code thrown by `p` (HttpsError details.code). */
export async function errorCode(p: Promise<unknown>): Promise<string | undefined> {
  try {
    await p;
  } catch (e) {
    return codeOf(e) ?? `non-https: ${String(e)}`;
  }
  return undefined;
}

export const okJudgement: DrawingJudgement = {
  subject: "ねこ",
  suggestedNames: ["にゃんた", "みけまる", "ねこりん"],
  elementMoveName: "ほのおぱんち",
  specialMoveName: "にゃんにゃんびーむ",
  skillEstimate: 22,
  appropriate: true,
  concerns: [],
  origin: "hand_drawn",
};

export function okVerdict(names: readonly string[]): ModerationVerdict {
  return {
    imageCategory: "ok",
    isHandDrawn: true,
    origin: "hand_drawn",
    names: names.map(() => ({ ok: true, category: "ok" })), skillEstimate: 25 };
}

/** Mocked Claude-backed service. Never calls the network. */
export function fakeAi() {
  const judgeDrawing = vi.fn<AiService["judgeDrawing"]>(async () => okJudgement);
  const moderateCharacter = vi.fn<AiService["moderateCharacter"]>(async (_png, names) => okVerdict(names));
  const generateMove = vi.fn<AiService["generateMove"]>(async (_png, ctx) => ({
    template: ctx.slot === 3 ? "blast" : "strike",
    attribute: ctx.slot === 3 ? "none" : "gu",
    name: "きらきらスター",
    flavor: "ほしが きらきら ふってくる",
    vfx: "stars",
    colour: "yellow",
    atkFormula: ctx.slot === 3 ? "INT80_DEX20" : "STR80_AGI20",
    power: 300,
    hits: 1,
    accuracy: 100,
    critBonus: 0,
    spCost: 10,
    castTicks: 0,
    cooldownTicks: 0,
  }));
  const svc: AiService = { judgeDrawing, moderateCharacter, generateMove };
  return { svc, judgeDrawing, moderateCharacter, generateMove };
}

export function registerInput(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    localCharacterId: "c1",
    imageBase64: pngBase64(),
    name: "ねこまる",
    element: "fire",
    baseStats: { hp: 90, atk: 80, def: 65, spd: 65 },
    energy: 50,
    skill: 20,
    level: 6,
    xp: 10,
    seedAllocations: { atk: 3 },
    features: { inkCoverage: 0.3 },
    subject: "ねこ",
    moveNames: { element: "ほのおぱんち", special: "にゃんびーむ" },
    ...over,
  };
}

/** Standard per-test isolation: clean emulators, fake AI, real clock. */
export function useEmulatorEnv(): { ai: ReturnType<typeof fakeAi>; setNow: (ms: number) => void; advance: (ms: number) => void } {
  const state = { ai: fakeAi(), now: Date.now() };
  const api = {
    get ai() {
      return state.ai;
    },
    setNow: (ms: number) => {
      state.now = ms;
    },
    advance: (ms: number) => {
      state.now += ms;
    },
  };
  beforeEach(async () => {
    await Promise.all([clearFirestore(), clearStorage()]);
    state.ai = fakeAi();
    setAiServiceForTesting(state.ai.svc);
    state.now = 1_800_000_000_000;
    clock.now = () => state.now;
    resetCostModeCacheForTesting();
  });
  afterEach(() => {
    setAiServiceForTesting(undefined);
    clock.now = () => Date.now();
  });
  return api;
}
