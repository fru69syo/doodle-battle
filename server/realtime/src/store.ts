/**
 * Persistence boundary. Everything the server reads from or writes to Firestore goes through
 * this interface, so tests run against `MemoryStore` and production against `FirestoreStore`.
 */
import type { FighterSource, Side } from "./engine";
import type { RatedState } from "./rating";
import type { MatchSummary, Settlement } from "./results";

export interface PlayerProfile {
  uid: string;
  /** users/{uid}.consent.online — set by a parent behind the parental gate. */
  consentOnline: boolean;
  /** Preset-word display name (BACKEND.md §5 setDisplayName); never free text. */
  displayName: string;
  rated: RatedState;
}

export interface SnapshotRecord extends FighterSource {
  status: string;
  ownerDisplayName: string;
  ghostRating: number | null;
}

export interface GhostPick {
  source: FighterSource;
  rating: number;
  displayName: string;
}

export interface Store {
  loadPlayer(uid: string): Promise<PlayerProfile | null>;
  loadSnapshot(snapshotId: string): Promise<SnapshotRecord | null>;
  /** An active registered character near `rating`, not owned by `excludeUid`. */
  pickGhost(args: { rating: number; excludeUid: string; excludeSnapshotIds: readonly string[] }): Promise<GhostPick | null>;
  /**
   * Atomically: read the players' rated state, apply `settle`, write users/{uid}.rated,
   * snapshots/{id}.ghostRating, rtMatches/{id} and replays/{id}.
   */
  settleMatch(summary: MatchSummary, settle: (rated: Map<string, RatedState>) => Settlement): Promise<Settlement>;
  /** Raw config/costMode document (or undefined). */
  readCostMode(): Promise<unknown>;
}

export type { Side };
