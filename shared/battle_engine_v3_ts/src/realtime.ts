/**
 * Server-facing wrapper for the realtime battle server (`server/realtime/`,
 * docs/REALTIME_PROTOCOL.md §9). Shapes follow `server/realtime/src/engine.ts`
 * so the server's `engines/v3Engine.ts` adapter is a thin pass-through:
 *
 * - `step([slotA, slotB])` advances one tick; an input is used only in the
 *   decision phase, only if that side is ready and the move is usable.
 * - The engine never auto-picks (`decisionTicks` disabled): the server owns
 *   the 5 s timer and passes the おまかせ choice (`chooseMove`) as an input.
 *   A replay is therefore seed + the logged `(tick, side, slot)` inputs
 *   (golden battles carry theirs as `expected.inputLog`).
 * - `chooseMove` consumes only the side's AI stream.
 */
import { chooseMove, type AiTier } from './ai';
import { Battle, type BattleEvent, type FighterSetup } from './engine';
import { Genome, maxHpOf, parseFeatures } from './genome';
import { ratedSetup } from './loadout';
import { DEFAULT_SPEC, type V3Spec } from './spec';

export const ENGINE_ID = 'v3.0';

/** The spec the server runs: the normative one with the timer disabled. */
export function serverSpec(s: V3Spec = DEFAULT_SPEC): V3Spec {
  return { ...s, decisionTicks: Number.MAX_SAFE_INTEGER };
}

export interface SideView {
  hp: number;
  maxHp: number;
  sp: number;
  gauge: number;
  ready: boolean;
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

  isReady(side: 0 | 1): boolean {
    return this.battle.fighters[side].phase === 'ready';
  }

  canUse(side: 0 | 1, slot: number): boolean {
    return this.battle.fighters[side].usable(slot);
  }

  chooseMove(side: 0 | 1, tier: AiTier): number {
    return chooseMove(this.battle, side, this.battle.aiRng[side], tier);
  }

  view(side: 0 | 1): SideView {
    const f = this.battle.fighters[side];
    return { hp: f.hp, maxHp: f.maxHp, sp: f.sp, gauge: f.gauge, ready: f.phase === 'ready', casting: f.phase === 'casting' };
  }

  stateHash(): string {
    return this.battle.stateHash().toString(16).padStart(8, '0');
  }
}

/** Kid-visible part of a fighter's move list. */
export function publicMoves(f: FighterSetup): { slot: number; name: string; templateId: string; attr: string; spCost: number }[] {
  return f.moves.map((m, slot) => ({ slot, name: m.name, templateId: m.template, attr: m.attr, spCost: m.spCost }));
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

