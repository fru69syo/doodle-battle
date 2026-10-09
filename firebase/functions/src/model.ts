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
