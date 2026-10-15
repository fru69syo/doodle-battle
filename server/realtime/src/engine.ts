/**
 * The narrow battle-engine interface the server is written against.
 *
 * The normative engine is Engine v3 (`shared/battle_engine_v3_ts/`, bit-exact with
 * `shared/battle_spec_v3/` and the app's Dart engine `app/lib/domain/battle_v3/`), adapted by
 * `engines/v3Engine.ts`. `engines/devEngine.ts` is a simplified local stand-in.
 *
 * Contract (stackable gauge bars, spec v4; GAME_DESIGN_V2 §6):
 * - `step(inputs)` advances exactly one tick. `inputs[side]` is the slot the side wants to use,
 *   or null. The engine uses an input only if that side is not casting and the move is usable
 *   now (enough full bars, no cooldown); otherwise it is ignored. The server keeps a child's
 *   さきどり and passes it every tick, so it fires in the very tick its bars are there.
 * - There is no decision timer: an idle side just stops filling at its max bars.
 * - `aiInput` (ghosts, an away child: the tiered AI) and `omakaseInput` (the child's おまかせ
 *   switch: a random move, then wait for its bars) consume only the side's AI random stream,
 *   never the battle stream, so calling them does not change the battle. A replay = seed +
 *   logged inputs.
 */

export type Side = 0 | 1;
export type AiTier = "weak" | "normal" | "strong";

/** A registered character as stored in Firestore (snapshots/{id}); `data` is engine input. */
export interface FighterSource {
  snapshotId: string;
  ownerUid: string | null;
  /** Real level of the character (rated play syncs to 50, XP uses the real level). */
  level: number;
  /** What the opponent's app shows; never contains anything the engine needs. */
  display: {
    characterName: string;
    imagePath: string | null;
    /** Puppet rig the owner adjusted (SPEC §12.7), passed through untouched. */
    rig?: unknown;
  };
  /** Engine-specific fields (features, imageHash, moves, …) exactly as written by registerCharacter. */
  data: Record<string, unknown>;
}

export interface MovePublic {
  slot: number;
  name: string;
  templateId: string;
  attr: string;
  /** Cost in gauge bars (1..5, never above the fighter's maxBars). */
  bars: number;
}

/** A fighter ready for battle (stats already synced). Opaque except for what clients may see. */
export interface FighterSetup {
  readonly attr: string;
  readonly moves: readonly MovePublic[];
  readonly maxHp: number;
  /** Gauge bars this fighter can stack (2..5). */
  readonly maxBars: number;
  readonly engineData: unknown;
}

export interface BattleEvent {
  tick: number;
  type: string;
  side?: Side;
  [key: string]: unknown;
}

export interface SideView {
  hp: number;
  maxHp: number;
  /** Gauge 0..maxBars·10000 (one bar = 10000; partial fill included). */
  gauge: number;
  /** Full bars now. */
  bars: number;
  maxBars: number;
  casting: boolean;
}

export interface StepResult {
  events: BattleEvent[];
  /** acted[side] = the input of that side was used in this tick. */
  acted: [boolean, boolean];
}

export interface BattleSim {
  readonly tick: number;
  readonly finished: boolean;
  readonly winner: Side | null;
  /** Why the engine ended the battle: KO, or the 3 minute cap decided by HP ratio. */
  readonly endReason: "ko" | "timeout" | null;
  step(inputs: readonly [number | null, number | null]): StepResult;
  /** The move can be used right now (enough bars, no cooldown, not casting). */
  canUse(side: Side, slot: number): boolean;
  /** The move can ever be used (its cost fits the side's max bars): it may be queued. */
  canQueue(side: Side, slot: number): boolean;
  /** Tiered AI (ghost / away child): the slot to use this tick, or null (keep filling). */
  aiInput(side: Side, tier: AiTier, thinkTicks: number): number | null;
  /** The おまかせ switch: random eligible move, used once its bars are there; or null. */
  omakaseInput(side: Side): number | null;
  /** Drops an AI plan (when control of a side changes hands). */
  clearPlan(side: Side): void;
  view(side: Side): SideView;
  /** Short hash of the full state (clients can detect desync; replays are checked with it). */
  stateHash(): string;
}

/**
 * Thrown by `ratedFighter` when a snapshot cannot be battled by this engine (e.g. a v1 snapshot
 * under Engine v3). The hub answers `NOT_FOUND` (the app asks the child to register again).
 */
export class UnsupportedFighterError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UnsupportedFighterError";
  }
}

export interface BattleEngine {
  /** Stored with every replay, e.g. "v3.1" or "dev-0". */
  readonly engineId: string;
  readonly tickHz: number;
  /** The engine ends the battle at this tick at the latest (3 minutes). */
  readonly hardCapTick: number;
  /** Lv50 sync for rated play (GAME_DESIGN_V2 §8): the character's own growth, real move unlocks. */
  ratedFighter(source: FighterSource, syncLevel: number): FighterSetup;
  createBattle(a: FighterSetup, b: FighterSetup, opts: { seed: number }): BattleSim;
}
