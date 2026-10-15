/**
 * Server-facing wrapper for the realtime battle server (`server/realtime/`,
 * docs/REALTIME_PROTOCOL.md §9). Shapes follow `server/realtime/src/engine.ts`
 * so the server's `engines/v3Engine.ts` adapter is a thin pass-through:
 *
 * - `step([slotA, slotB])` advances one tick; an input is used only if that
 *   side is not casting and the move is usable now (enough bars, no
 *   cooldown); otherwise it is ignored. The server keeps a child's さきどり
 *   and passes it every tick, so it fires on the tick its bars are there.
 * - There is no decision timer: an idle side just caps at its max bars.
 * - `aiInput` (ghosts, an away child: the tiered AI) and `omakaseInput`
 *   (the child's おまかせ switch: random move, wait for its bars) consume only
 *   the side's AI stream. A replay is seed + the logged `(tick, side, slot)`
 *   inputs (golden battles carry theirs as `expected.inputLog`).
 */
import { aiDecide, type AiTier, omakasePick } from './ai';
import { Battle, type BattleEvent, type FighterSetup } from './engine';
import { Genome, maxHpOf, parseFeatures } from './genome';
import { ratedSetup } from './loadout';
import { DEFAULT_SPEC, type V3Spec } from './spec';

export const ENGINE_ID = 'v3.1';

/** The spec the server runs (the normative one; there is no timer to disable). */
export function serverSpec(s: V3Spec = DEFAULT_SPEC): V3Spec {
  return s;
}

export interface SideView {
  hp: number;
  maxHp: number;
  /** 0..maxBars·10000 (one bar = 10000). */
  gauge: number;
  /** Full bars now. */
  bars: number;
  maxBars: number;
  casting: boolean;
}

export interface RealtimeStep {
  events: (BattleEvent['data'] & { tick: number; type: string })[];
  acted: [boolean, boolean];
}

export class RealtimeBattle {
  readonly battle: Battle;

  constructor(a: FighterSetup, b: FighterSetup, seed: number, spec: V3Spec = DEFAULT_SPEC) {
    this.battle = new Battle(serverSpec(spec), a, b, seed);
  }

  get tick(): number {
    return this.battle.tick;
  }

  get finished(): boolean {
    return this.battle.finished;
  }

  get winner(): 0 | 1 | null {
    return this.battle.winner as 0 | 1 | null;
  }

  /** `ko`, or `timeout` for the 3-minute cap decided by HP ratio. */
  get endReason(): 'ko' | 'timeout' | null {
    const r = this.battle.endReason;
    return r === null ? null : r === 'ko' ? 'ko' : 'timeout';
  }

  step(inputs: readonly [number | null, number | null]): RealtimeStep {
    const ctl = (side: 0 | 1) => () => inputs[side];
    const ev = this.battle.step(ctl(0), ctl(1));
    const acted: [boolean, boolean] = [false, false];
    for (const e of ev) if (e.type === 'select') acted[e.data.side as 0 | 1] = true;
    return { events: ev.map((e) => ({ ...e.data, tick: e.tick, type: e.type })), acted };
  }

  /** The move can be used right now (not casting, enough bars, no cooldown). */
  canUse(side: 0 | 1, slot: number): boolean {
    const f = this.battle.fighters[side];
    return f.phase !== 'casting' && f.usable(slot);
  }

  /** The move can ever be used (valid slot, cost ≤ max bars): may be queued. */
  canQueue(side: 0 | 1, slot: number): boolean {
    return this.battle.fighters[side].canQueue(slot);
  }

  /** Tiered AI (ghost / away child): the slot to use this tick, or null. */
  aiInput(side: 0 | 1, tier: AiTier, thinkTicks: number): number | null {
    const f = this.battle.fighters[side];
    if (f.phase === 'casting') return null;
    return aiDecide(this.battle, side, tier, thinkTicks);
  }

  /** おまかせ switch: random eligible plan, used once its bars are there. */
  omakaseInput(side: 0 | 1): number | null {
    const f = this.battle.fighters[side];
    if (f.phase === 'casting') return null;
    if (f.aiPlan === null) f.aiPlan = omakasePick(this.battle, side, this.battle.aiRng[side]);
    return f.usable(f.aiPlan) ? f.aiPlan : null;
  }

  /** Forgets an AI plan (when the child takes control back). */
  clearPlan(side: 0 | 1): void {
    this.battle.fighters[side].aiPlan = null;
  }

  view(side: 0 | 1): SideView {
    const f = this.battle.fighters[side];
    return { hp: f.hp, maxHp: f.maxHp, gauge: f.gauge, bars: f.bars, maxBars: f.maxBars, casting: f.phase === 'casting' };
  }

  stateHash(): string {
    return this.battle.stateHash().toString(16).padStart(8, '0');
  }
}

/** Kid-visible part of a fighter's move list (the cost in bars included). */
export function publicMoves(f: FighterSetup): { slot: number; name: string; templateId: string; attr: string; bars: number }[] {
  return f.moves.map((m, slot) => ({ slot, name: m.name, templateId: m.template, attr: m.attr, bars: m.bars }));
}

/**
 * Rated fighter from a v2 snapshot's engine data (written by the v2
 * `registerCharacter`: `features`, `energy10`, `skill10`, `imageHash`,
 * `trust`, `proposals`) at the character's real level. Null when the data
 * is not a valid v2 snapshot.
 */
export function ratedFighterFromSnapshot(
  data: Record<string, unknown>,
  actualLevel: number,
  spec: V3Spec = DEFAULT_SPEC,
): { setup: FighterSetup; maxHp: number } | null {
  const features = parseFeatures(data.features);
  const e10 = data.energy10;
  const s10 = data.skill10;
  if (features === null || typeof e10 !== 'number' || typeof s10 !== 'number' || typeof data.imageHash !== 'string') {
    return null;
  }
  const trust = typeof data.trust === 'string' ? data.trust : null;
  const g = new Genome(spec, { features, energy10: e10, skill10: s10, imageHash: data.imageHash, origin: trust });
  const proposals = Array.isArray(data.proposals) ? (data.proposals as (Record<string, unknown> | null)[]) : [];
  const setup = ratedSetup(spec, g, actualLevel, { aiProposals: proposals });
  return { setup, maxHp: maxHpOf(spec, setup.stats) };
}

