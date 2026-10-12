import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret, defineString } from "firebase-functions/params";

/** All functions run in Tokyo. */
export const REGION = "asia-northeast1";

// Applies to every function; config.ts is imported (directly or indirectly) by
// all function modules, so this runs before any trigger is defined.
setGlobalOptions({ region: REGION, maxInstances: 20 });

/** Anthropic API key, stored in Secret Manager. Never sent to clients. */
export const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

/**
 * Claude model identifier used for drawing judging and moderation.
 * Set it to the latest low-cost Haiku-class model (see docs/BACKEND.md).
 * Deliberately has no default so that no model id is hard-coded in the repo.
 */
export const CLAUDE_MODEL = defineString("CLAUDE_MODEL", {
  description: "Claude model id for judging/moderation (latest Haiku-class model)",
});

/** Tunables (kept in one place so docs/BACKEND.md can reference them). */
export const LIMITS = {
  /** Max decoded PNG size accepted by judgeDrawing/registerCharacter. */
  maxPngBytes: 600 * 1024,
  /** Max PNG width/height (the app downsizes the cut-out to 512px). */
  maxPngSide: 512,
  minPngSide: 16,
  /** Online play unlock level (SPEC §2.7 / §4.2). */
  onlineMinLevel: 5,
  maxLevel: 30,
  /** Matchmaking: level band and ghost fallback. */
  levelBand: 3,
  ghostAfterMs: 60_000,
  /** A waiting queue entry whose client stopped heart-beating is dropped. */
  queueStaleMs: 45_000,
  /** Battle turn limit (SPEC §5) plus server grace for network latency. */
  turnMs: 20_000,
  turnGraceMs: 3_000,
  maxTurns: 30,
  /** Consecutive timed-out turns after which a player forfeits. */
  forfeitAfterTimeouts: 3,
  /** Distinct reports after which a snapshot is auto-hidden. */
  reportHideThreshold: 3,
  /** Only opponents met in this many most recent matches can be reported. */
  reportLookbackMatches: 50,
} as const;

export const RATE_LIMITS = {
  judgeDrawing: [
    { key: "judge_h", limit: 30, windowMs: 3_600_000 },
    { key: "judge_d", limit: 100, windowMs: 86_400_000 },
  ],
  registerCharacter: [
    { key: "register_h", limit: 10, windowMs: 3_600_000 },
    { key: "register_d", limit: 30, windowMs: 86_400_000 },
  ],
  /** Lv10 / Lv50 move generation: a few per character, so generous but bounded. */
  generateMove: [
    { key: "genmove_h", limit: 10, windowMs: 3_600_000 },
    { key: "genmove_d", limit: 20, windowMs: 86_400_000 },
  ],
  reportCharacter: [{ key: "report_d", limit: 20, windowMs: 86_400_000 }],
  reportAiSuggestion: [{ key: "aireport_d", limit: 20, windowMs: 86_400_000 }],
  setDisplayName: [{ key: "dname_d", limit: 20, windowMs: 86_400_000 }],
  deleteMyData: [{ key: "delete_d", limit: 5, windowMs: 86_400_000 }],
} as const;
