/** Wire-format types shared with the Dart engine (same JSON shapes). */

export type ElementType = 'fire' | 'water' | 'leaf' | 'thunder' | 'shadow' | 'rainbow';
export const ELEMENTS: readonly ElementType[] = ['fire', 'water', 'leaf', 'thunder', 'shadow', 'rainbow'];

export type Side = 'a' | 'b';
export const other = (s: Side): Side => (s === 'a' ? 'b' : 'a');

/** Attack / guard moves. */
export type BattleMove = 'tackle' | 'element' | 'guard' | 'special';
/** Player input: a move, or 'timeout' (resolved as spec.timeoutAction). */
export type BattleAction = BattleMove | 'timeout';
export type AttackMove = 'tackle' | 'element' | 'special';
export const isAttack = (m: BattleAction): m is AttackMove =>
  m === 'tackle' || m === 'element' || m === 'special';

export type AiTier = 'weak' | 'normal' | 'strong';
export type EndReason = 'ko' | 'turnCap';
export type StatKind = 'hp' | 'atk' | 'def' | 'spd';
export type EvolutionStage = 'normal' | 'kagayaki' | 'densetsu';

export interface Stats {
  hp: number;
  atk: number;
  def: number;
  spd: number;
}

export interface MoveUsage {
  tackle: number;
  element: number;
  guard: number;
  special: number;
}

export interface FighterState {
  element: ElementType;
  level: number;
  maxHp: number;
  hp: number;
  atk: number;
  def: number;
  spd: number;
  specialPower: number;
  gauge: number;
  guardStreak: number;
  usage: MoveUsage;
  lastAction: BattleMove | null;
}

export interface BattleState {
  turn: number;
  a: FighterState;
  b: FighterState;
  winner: Side | null;
  endReason: EndReason | null;
}

export interface FighterSetup {
  element: ElementType;
  level: number;
  /** Current stats (after growth; see statsAtLevel). */
  stats: Stats;
}

export type BattleEvent =
  | { type: 'turnStart'; turn: number }
  | { type: 'timeout'; side: Side }
  | { type: 'specialNotReady'; side: Side }
  | { type: 'guard'; side: Side; damageTakenPct: number; weakened: boolean }
  | { type: 'move'; side: Side; move: AttackMove; element: ElementType | null }
  | { type: 'miss'; side: Side }
  | { type: 'crit'; side: Side }
  | { type: 'effectiveness'; side: Side; multiplierPct: number; text: string }
  | { type: 'damage'; target: Side; amount: number; hp: number; guarded: boolean }
  | { type: 'gauge'; side: Side; delta: number; value: number }
  | { type: 'faint'; side: Side }
  | { type: 'battleEnd'; winner: Side; reason: EndReason };

export interface TurnResult {
  state: BattleState;
  events: BattleEvent[];
}
