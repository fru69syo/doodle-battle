/**
 * Server-side validation for `registerCharacter` (v2 characters) and for
 * AI move proposals. The server never trusts client numbers: it recomputes
 * stats from the quantised features + level, re-validates every move
 * proposal against the slot budget and checks the rig blob's size / shape.
 *
 * Nothing returned here reveals the hidden late-bloomer state: callers may
 * store `snapshot` as-is (stats are simply what the engine computes).
 */
import { BLOOMER_ORIGINS, Genome, maxHpOf, parseFeatures, type FeatureVector } from './genome';
import { setupToJson } from './engine';
import { ratedSetup, setupAt } from './loadout';
import { moveToJson } from './moves';
import { barBudget, slotMaxBarsFor } from './moves';
import { unlockedSlots, xpToNext } from './progression';
import { rigProblem, validateRigJson } from './rig';
import { type Attr, DEFAULT_SPEC, type V3Spec } from './spec';
import { type NgCheck, validateAiMove } from './validator';

export interface CharacterClaimV2 {
  features: unknown;
  energy10: unknown;
  skill10: unknown;
  imageHash: unknown;
  /** Device trust verdict (`digital` / `printed` / `screen`), if any. */
  verdict?: unknown;
  level: unknown;
  xp?: unknown;
  /** Optional: the stats the device shows (must match the recomputation). */
  stats?: unknown;
  /** Per slot: a normalised AI proposal, or null for the offline move. */
  moves?: unknown;
  rig?: unknown;
}

export type ClaimProblem =
  | 'FEATURES_INVALID'
  | 'SCORES_INVALID'
  | 'IMAGE_HASH_INVALID'
  | 'LEVEL_INVALID'
  | 'XP_INVALID'
  | 'VERDICT_INVALID'
  | 'STATS_MISMATCH'
  | 'MOVES_INVALID';

export interface ValidatedCharacterV2 {
  ok: boolean;
  problems: ClaimProblem[];
  /** Per-slot outcome codes for the server log (never shown to children). */
  moveLog: string[];
  /** Why the rig was dropped, if it was. */
  rigDropped: string | null;
  snapshot: {
    features: FeatureVector;
    energy10: number;
    skill10: number;
    imageHash: string;
    level: number;
    attribute: Attr;
    stats: number[];
    maxHp: number;
    /** Normalised proposals to store (null = offline move for that slot). */
    proposals: (Record<string, unknown> | null)[];
    /** The fighter at its level (moves resolved, unlocked slots only). */
    setup: Record<string, unknown>;
    /** The rated-play fighter (synced to Lv50). */
    rated: Record<string, unknown>;
    rig: Record<string, unknown> | null;
  } | null;
}

const isInt = (x: unknown): x is number => typeof x === 'number' && Number.isInteger(x);
const HASH = /^[0-9a-f]{64}$/;

/**
 * Validates a v2 character claim. `serverOrigin` is the moderation verdict
 * (`ai_generated` makes a hidden bloomer, like the device verdicts).
 */
export function validateCharacterClaimV2(
  claim: CharacterClaimV2,
  opts: { spec?: V3Spec; ngCheck?: NgCheck; serverOrigin?: string | null; maxLevel?: number } = {},
): ValidatedCharacterV2 {
  const s = opts.spec ?? DEFAULT_SPEC;
  const problems: ClaimProblem[] = [];
  const fail = (): ValidatedCharacterV2 => ({ ok: false, problems, moveLog: [], rigDropped: null, snapshot: null });

  const features = parseFeatures(claim.features);
  if (features === null) problems.push('FEATURES_INVALID');
  const e10 = claim.energy10;
  const s10 = claim.skill10;
  if (!isInt(e10) || !isInt(s10) || e10 < 0 || e10 > 1000 || s10 < 0 || s10 > 1000) problems.push('SCORES_INVALID');
  if (typeof claim.imageHash !== 'string' || !HASH.test(claim.imageHash)) problems.push('IMAGE_HASH_INVALID');
  const maxLevel = Math.min(opts.maxLevel ?? s.maxLevel, s.maxLevel);
  const level = claim.level;
  if (!isInt(level) || level < 1 || level > maxLevel) problems.push('LEVEL_INVALID');
  const xp = claim.xp ?? 0;
  if (!isInt(xp) || xp < 0 || (isInt(level) && level >= 1 && level < s.maxLevel && xp >= xpToNext(s, level))) {
    problems.push('XP_INVALID');
  }
  const verdict = claim.verdict ?? null;
  if (verdict !== null && !(typeof verdict === 'string' && BLOOMER_ORIGINS.has(verdict))) problems.push('VERDICT_INVALID');
  const moves = claim.moves ?? [];
  if (!Array.isArray(moves) || moves.length > 4 || moves.some((m) => m !== null && (typeof m !== 'object' || Array.isArray(m)))) {
    problems.push('MOVES_INVALID');
  }
  if (problems.length > 0) return fail();

  const origin =
    opts.serverOrigin && BLOOMER_ORIGINS.has(opts.serverOrigin) ? opts.serverOrigin : (verdict as string | null);
  const g = new Genome(s, {
    features: features!,
    energy10: e10 as number,
    skill10: s10 as number,
    imageHash: claim.imageHash as string,
    origin,
  });
  const lv = level as number;
  const stats = g.statsAt(lv);
  if (claim.stats !== undefined) {
    const c = claim.stats;
    if (!Array.isArray(c) || c.length !== 10 || c.some((v, i) => v !== stats[i])) {
      problems.push('STATS_MISMATCH');
      return fail();
    }
  }

  // Proposals of a pre-rebirth set are not used once the rebirth set is due.
  const stale = g.rebornAt(lv);
  const factor = g.moveFactorPct(lv);
  const moveLog: string[] = [];
  const proposals = (moves as (Record<string, unknown> | null)[]).map((p, slot) => {
    if (!p) {
      moveLog.push(`${slot}:offline`);
      return null;
    }
    if (stale) {
      moveLog.push(`${slot}:stale`);
      return null;
    }
    const v = validateAiMove(s, p, { slot, own: g.attr, moveFactorPct: factor, maxBars: g.maxBarsAt(lv), ...(opts.ngCheck ? { ngCheck: opts.ngCheck } : {}) });
    if (v.rejected) {
      moveLog.push(`${slot}:rejected:${v.reason}`);
      return null;
    }
    moveLog.push(v.warnings.length ? `${slot}:ok:${v.warnings.length}w` : `${slot}:ok`);
    return moveToJson(v.move!);
  });
  while (proposals.length < 4) proposals.push(null);

  const rigDropped = claim.rig === undefined || claim.rig === null ? null : rigProblem(claim.rig);
  const setup = setupAt(s, g, lv, { aiProposals: proposals });
  const rated = ratedSetup(s, g, lv, { aiProposals: proposals });
  return {
    ok: true,
    problems,
    moveLog,
    rigDropped,
    snapshot: {
      features: features!,
      energy10: e10 as number,
      skill10: s10 as number,
      imageHash: claim.imageHash as string,
      level: lv,
      attribute: g.attr,
      stats,
      maxHp: maxHpOf(s, stats),
      proposals,
      setup: { ...setupToJson(setup), slots: unlockedSlots(s, lv) },
      rated: setupToJson(rated),
      rig: claim.rig === undefined ? null : validateRigJson(claim.rig),
    },
  };
}

/** Genome facts the server needs to build an AI move prompt / validate. */
export function moveContextOf(
  claim: Pick<CharacterClaimV2, 'features' | 'energy10' | 'skill10' | 'imageHash' | 'verdict'>,
  opts: { spec?: V3Spec; serverOrigin?: string | null; level?: number } = {},
): {
  attribute: Attr;
  moveFactorPct: number;
  maxBars: number;
  /** Points a move may be worth per cost in bars (index = bars − 1, up to maxBars). */
  barBudgets: number[];
  /** Most bars per slot (slot 1 = 1; others capped by maxBars). */
  slotMaxBars: number[];
  /** Points budget per slot (= barBudgets[slotMaxBars − 1]). */
  slotBudgets: number[];
} | null {
  const s = opts.spec ?? DEFAULT_SPEC;
  const features = parseFeatures(claim.features);
  if (
    features === null ||
    !isInt(claim.energy10) ||
    !isInt(claim.skill10) ||
    typeof claim.imageHash !== 'string' ||
    claim.imageHash.length === 0
  ) {
    return null;
  }
  const v = typeof claim.verdict === 'string' && BLOOMER_ORIGINS.has(claim.verdict) ? claim.verdict : null;
  const origin = opts.serverOrigin && BLOOMER_ORIGINS.has(opts.serverOrigin) ? opts.serverOrigin : v;
  const g = new Genome(s, {
    features,
    energy10: claim.energy10,
    skill10: claim.skill10,
    imageHash: claim.imageHash,
    origin,
  });
  const lv = opts.level ?? 1;
  const factor = g.moveFactorPct(lv);
  const maxBars = g.maxBarsAt(lv);
  const slotMax = [0, 1, 2, 3].map((slot) => slotMaxBarsFor(s, slot, maxBars));
  return {
    attribute: g.attr,
    moveFactorPct: factor,
    maxBars,
    barBudgets: Array.from({ length: maxBars }, (_, i) => barBudget(s, i + 1, factor)),
    slotMaxBars: slotMax,
    slotBudgets: slotMax.map((b) => barBudget(s, b, factor)),
  };
}
