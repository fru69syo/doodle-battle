/**
 * The narrow battle-engine interface the server is written against.
 *
 * The normative engine is Engine v3 (`shared/battle_engine_v3_ts/`, written by the Engine team,
 * bit-exact with `shared/battle_spec_v3/` and the Dart prototype in
 * `app/lib/domain/battle_v2/atb_engine.dart`). Until it lands the server runs with
 * `engines/devEngine.ts`, a simplified stand-in. Swapping = writing `engines/v3Engine.ts`, an
 * adapter of ~50 lines from Engine v3 to this interface (docs/REALTIME_PROTOCOL.md §9).
 *
 * Contract (mirrors the prototype's `step(Controller a, Controller b)` at a fixed 10 Hz tick):
 * - `step(inputs)` advances exactly one tick. `inputs[side]` is the slot the side wants to use,
 *   or null. The engine uses an input only in the tick's decision phase and only if that side
 *   is ready and the move is usable; otherwise it is ignored (GAME_DESIGN_V2 §6.1 step 4).
 *   Because the server passes a queued slot on every tick, a pre-selected move (さきどり) is used
 *   in the very tick the gauge fills.
 * - The engine must NOT auto-pick on its own: the server owns the 5 s timer (+3 tick network
 *   grace, GAME_DESIGN_V2 §6.7) and passes the おまかせ choice as a normal input. Engine v3's
 *   `decisionTicks` must therefore be disabled (e.g. Number.MAX_SAFE_INTEGER) in createBattle.
 *   Replays use the same setting, so a replay = seed + logged inputs.
 * - `chooseMove` is the shared おまかせ AI (`chooseMove` in ai_v2.dart). It consumes only the
 *   side's AI random stream, never the battle stream, so calling it does not change the battle.
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
  spCost: number;
}

/** A fighter ready for battle (stats already synced). Opaque except for what clients may see. */
export interface FighterSetup {
  readonly attr: string;
  readonly moves: readonly MovePublic[];
  readonly maxHp: number;
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
  /** SP in 1/100 units (0..10000). */
  sp: number;
  /** Gauge 0..10000. */
  gauge: number;
  ready: boolean;
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
  isReady(side: Side): boolean;
  canUse(side: Side, slot: number): boolean;
  chooseMove(side: Side, tier: AiTier): number;
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
