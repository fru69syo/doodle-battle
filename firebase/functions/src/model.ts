/** Firestore document shapes (see docs/BACKEND.md "Data model"). */
import type { ActionId, BattleEvent, BattleView, EngineState, Side } from "./battle/engine";
import type { Element, Stats } from "./stats/statLimits";

export type SnapshotStatus = "active" | "hidden" | "removed" | "superseded" | "withdrawn";

/** `snapshots/{snapshotId}`: immutable registered character (+ moderation counters). */
export interface SnapshotDoc {
  ownerUid: string;
  localCharacterId: string;
  status: SnapshotStatus;
  name: string;
  moveNames: { element: string | null; special: string | null };
  ownerDisplayName: string;
  element: Element;
  baseStats: Stats;
  stats: Stats;
  energy: number;
  skill: number;
  isShobo: boolean;
  level: number;
  xp: number;
  seedAllocations: Partial<Stats>;
  evolution: "normal" | "kagayaki" | "densetsu";
  subject: string | null;
  features: Record<string, number>;
  imagePath: string;
  imageSha256: string;
  moderation: { aiSkillEstimate: number; suspectSkill: boolean; ngWordsVersion: number };
  reportCount: number;
  reportReasons: Record<string, number>;
  randomKey: number;
  createdAtMs: number;
  statusChangedAtMs?: number;
}

/**
 * `snapshots/{id}` written by the v2 `registerCharacter` (engine v3,
 * docs/BATTLE_V3.md §Server). Same collection and lifecycle as v1, marked
 * with `schema: 2`; the v1 turn-based matchmaking skips these and the
 * realtime server (server/realtime) battles them. `engine` is the engine
 * input (server-only: every number is recomputed from it); the rest is
 * display / moderation data.
 */
export interface SnapshotDocV2 {
  schema: 2;
  engineId: string;
  ownerUid: string;
  localCharacterId: string;
  status: SnapshotStatus;
  name: string;
  /** Kana names of the moves per slot (display; null = offline name). */
  moveNames: (string | null)[];
  ownerDisplayName: string;
  /** グー / チョキ / パー. */
  attribute: string;
  level: number;
  xp: number;
  /** Stats at `level` and synced to Lv50 for rated play (server-computed). */
  stats: number[];
  ratedStats: number[];
  maxHp: number;
  evolution: string | null;
  subject: string | null;
  /** Validated 2.5D rig blob (null = the opponent's app auto-rigs). */
  rig: Record<string, unknown> | null;
  engine: {
    features: Record<string, number>;
    energy10: number;
    skill10: number;
    imageHash: string;
    /** Trust verdict (internal; never returned to clients). */
    trust: string | null;
    /** Normalised AI move proposals per slot (null = offline move). */
    proposals: (Record<string, unknown> | null)[];
  };
  imagePath: string;
  imageSha256: string;
  moderation: { aiSkillEstimate: number; suspectSkill: boolean; ngWordsVersion: number };
  reportCount: number;
  reportReasons: Record<string, number>;
  randomKey: number;
  createdAtMs: number;
  statusChangedAtMs?: number;
}

/** True for a v2 (engine v3) snapshot. */
export function isV2Snapshot(doc: object): boolean {
  return (doc as { schema?: unknown }).schema === 2;
}

export type QueueStatus = "waiting" | "matched";

/** `queue/{uid}` */
export interface QueueDoc {
  uid: string;
  snapshotId: string;
  level: number;
  status: QueueStatus;
  matchId: string | null;
  joinedAtMs: number;
  lastSeenMs: number;
}

/** Public per-side info embedded in the match doc (what the opponent sees). */
export interface SideInfo {
  uid: string | null;
  isGhost: boolean;
  snapshotId: string;
  displayName: string;
  characterName: string;
  element: Element;
  level: number;
  isShobo: boolean;
  evolution: SnapshotDoc["evolution"];
  stats: Stats;
  imagePath: string;
  moveNames: SnapshotDoc["moveNames"];
  rating: number;
}

export type MatchStatus = "active" | "finished" | "aborted";
export type EndReason = "ko" | "turn_limit" | "forfeit_timeout" | "aborted";

export interface SideResult {
  xp: number;
  ratingDelta: number;
  outcome: "win" | "lose" | "draw" | "none";
}

/** `matches/{matchId}`: written only by functions, readable by its players. */
export interface MatchDoc {
  mode: "pvp" | "ghost";
  playerUids: string[];
  snapshotIds: string[];
  sides: Record<Side, SideInfo>;
  engineId: string;
  seed: number;
  /** Turn number currently waiting for actions (1-based). */
  turn: number;
  state: EngineState;
  view: BattleView;
  submitted: Record<Side, boolean>;
  turnDeadlineMs: number;
  timeouts: Record<Side, number>;
  status: MatchStatus;
  winner: Side | "draw" | null;
  endReason: EndReason | null;
  result: Record<Side, SideResult> | null;
  createdAtMs: number;
  updatedAtMs: number;
  finishedAtMs: number | null;
}

/** `matches/{matchId}/private/actions`: hidden pending actions. */
export interface PendingActions {
  turn: number;
  a: ActionId | null;
  b: ActionId | null;
}

/** `matches/{matchId}/turns/{turn}`: resolved turn log. */
export interface TurnDoc {
  turn: number;
  actions: Record<Side, ActionId>;
  timedOut: Record<Side, boolean>;
  events: BattleEvent[];
  view: BattleView;
  resolvedAtMs: number;
}
