/**
 * Character → battle setup (level, rated sync, family). Port of
 * app/lib/domain/battle_v3/loadout.dart.
 */
import type { FighterSetup } from './engine';
import type { Genome } from './genome';
import type { Move } from './moves';
import { generateOfflineMoves } from './offlineMoves';
import { ratedSync, unlockedSlots } from './progression';
import { type Attr, idiv, type V3Spec } from './spec';
import { type NgCheck, validateAiMove } from './validator';

export function moveStreamAt(g: Genome, level: number): number {
  return g.rebornAt(level) ? 14 : 12;
}

export interface MoveOptions {
  attr?: Attr | null;
  aiProposals?: readonly (Record<string, unknown> | null | undefined)[];
  nameOverrides?: readonly (string | null | undefined)[];
  preForm?: boolean;
  ngCheck?: NgCheck;
  /** Overrides the genome's max bars (simulator / tests). */
  maxBars?: number | null;
}

/** The four slot moves at `level` (AI proposals re-validated, else offline). */
export function movesAt(s: V3Spec, g: Genome, level: number, o: MoveOptions = {}): Move[] {
  const factor = o.preForm ? s.bloomerPreMoveFactorPct : g.moveFactorPct(level);
  const stream = o.preForm ? 12 : moveStreamAt(g, level);
  const own = o.attr ?? g.attr;
  const bars = o.maxBars ?? g.maxBarsAt(level, o.preForm ?? false);
  const offline = generateOfflineMoves(s, g, { moveFactorPct: factor, stream, attr: own, maxBars: bars });
  return offline.map((m0, i) => {
    let m = m0;
    const p = o.aiProposals?.[i];
    if (p) {
      const v = validateAiMove(s, p, { slot: i, own, moveFactorPct: factor, maxBars: bars, ...(o.ngCheck ? { ngCheck: o.ngCheck } : {}) });
      if (!v.rejected) m = v.move!;
    }
    const n = o.nameOverrides?.[i];
    if (n) m = { ...m, name: n };
    return m;
  });
}

export function setupAt(
  s: V3Spec,
  g: Genome,
  level: number,
  o: MoveOptions & { label?: string; powerPct?: number } = {},
): FighterSetup {
  const moves = movesAt(s, g, level, o);
  const pct = o.powerPct ?? 100;
  return {
    stats: g.statsAt(level).map((v) => idiv(v * pct, 100)),
    attr: o.attr ?? g.attr,
    maxBars: o.maxBars ?? g.maxBarsAt(level),
    moves: moves.slice(0, unlockedSlots(s, level)),
    label: o.label ?? '',
  };
}

/** Rated play: stats synced to Lv50, slots of the actual level. */
export function ratedSetup(s: V3Spec, g: Genome, actualLevel: number, o: MoveOptions & { label?: string } = {}): FighterSetup {
  const r = ratedSync(s, { actualLevel, isBloomer: g.isBloomer });
  const moves = movesAt(s, g, r.statLevel, { ...o, attr: null, preForm: r.preForm });
  return {
    stats: g.statsAt(r.statLevel, r.preForm),
    attr: g.attr,
    maxBars: g.maxBarsAt(r.statLevel, r.preForm),
    moves: moves.slice(0, r.slotCount),
    label: o.label ?? '',
  };
}

/** Family battle at `battleLevel` (handicap), hidden form preserved. */
export function familySetup(
  s: V3Spec,
  g: Genome,
  actualLevel: number,
  battleLevel: number,
  o: MoveOptions & { label?: string } = {},
): FighterSetup {
  const pre = g.isBloomer && actualLevel < s.rebirthLevel;
  const moves = movesAt(s, g, battleLevel, { ...o, attr: null, preForm: pre });
  return {
    stats: g.statsAt(battleLevel, pre),
    attr: g.attr,
    maxBars: g.maxBarsAt(battleLevel, pre),
    moves: moves.slice(0, unlockedSlots(s, battleLevel)),
    label: o.label ?? '',
  };
}
