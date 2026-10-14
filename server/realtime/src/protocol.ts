/**
 * WebSocket protocol v1, revision 2 (docs/REALTIME_PROTOCOL.md is the human-readable version;
 * keep both in sync). JSON text frames, one message per frame, discriminated by `t`.
 *
 * `proto` (major) changes only for breaking changes. `rev` (sent in `welcome`) counts additive
 * revisions: rev 2 added `omakase`, `FighterInfo.snapshotId` and the `deadline` event.
 */
import { z } from "zod";
import type { BadgeId } from "./rating";
import type { BattleEvent, MovePublic, SideView } from "./engine";

export const PROTOCOL_VERSION = 1;
/** Additive revision of protocol v1 (welcome.rev). 1 = the original v1, 2 = omakase + deadline + snapshotId. */
export const PROTOCOL_REVISION = 2;
export const PATH = "/v2";

/** Max size of the first message (tokens are ~1–2 KB each) and of every later message. */
export const MAX_HELLO_BYTES = 8192;
export const MAX_MESSAGE_BYTES = 512;

const id = z.string().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);

export const Hello = z
  .object({
    t: z.literal("hello"),
    proto: z.literal(PROTOCOL_VERSION),
    idToken: z.string().min(1).max(4096),
    appCheckToken: z.string().min(1).max(4096).optional(),
    /** Last event `seq` the client applied, to resend what it missed after a reconnect. */
    lastSeq: z.number().int().min(0).max(1_000_000).optional(),
  })
  .strict();

export const Queue = z.object({ t: z.literal("queue"), snapshotId: id }).strict();
export const Cancel = z.object({ t: z.literal("cancel") }).strict();
export const Select = z
  .object({
    t: z.literal("select"),
    /** Client counter, strictly increasing per match; the ack echoes it. */
    seq: z.number().int().min(0).max(1_000_000),
    slot: z.number().int().min(0).max(3),
  })
  .strict();
export const Ping = z.object({ t: z.literal("ping") }).strict();
/** The child's おまかせ switch (rev 2): while on, the server's AI picks for that side. */
export const Omakase = z.object({ t: z.literal("omakase"), on: z.boolean() }).strict();

export const ClientMessage = z.discriminatedUnion("t", [Queue, Cancel, Select, Ping, Omakase]);
export type HelloMsg = z.infer<typeof Hello>;
export type ClientMsg = z.infer<typeof ClientMessage>;

// --- server -> client ---------------------------------------------------------------------------

export type ErrorCode =
  | "BAD_MESSAGE"
  | "UNAUTHENTICATED"
  | "APP_CHECK_FAILED"
  | "CONSENT_REQUIRED"
  | "PROTOCOL_VERSION"
  | "RATE_LIMITED"
  | "NOT_FOUND"
  | "NOT_OWNER"
  | "LEVEL_TOO_LOW"
  | "ALREADY_IN_MATCH"
  | "NOT_IN_MATCH"
  | "SERVER_BUSY"
  | "DRAINING"
  | "INTERNAL";

export interface FighterInfo {
  /**
   * The registered character (snapshots/{id}) — the public id the app passes to
   * `reportCharacter` (SPEC §9.4). For a mirror ghost it is the child's own snapshot.
   */
  snapshotId: string;
  /** Opponent's display name (preset words) or the player's own. Never a uid. */
  displayName: string;
  characterName: string;
  imagePath: string | null;
  rig?: unknown;
  attr: string;
  moves: readonly MovePublic[];
  maxHp: number;
  /** Rated play is always at Lv50 (GAME_DESIGN_V2 §8). */
  level: number;
  badge: BadgeId;
  isGhost: boolean;
}

export type ServerMsg =
  | { t: "welcome"; proto: number; rev: number; serverTimeMs: number; inMatch: boolean }
  | { t: "queued"; snapshotId: string }
  | { t: "cancelled" }
  | {
      t: "match";
      matchId: string;
      you: "a" | "b";
      tickHz: number;
      decisionTicks: number;
      a: FighterInfo;
      b: FighterInfo;
      resumed: boolean;
    }
  | { t: "ev"; seq: number; tick: number; events: BattleEvent[] }
  | { t: "snap"; tick: number; a: SideView; b: SideView; hash: string }
  | { t: "sel"; seq: number; slot: number; accepted: boolean; queued: boolean; reason?: "unusable" | "stale" }
  | {
      t: "end";
      matchId: string;
      winner: "a" | "b" | null;
      reason: "ko" | "timeout" | "forfeit" | "aborted";
      you: { outcome: "win" | "lose" | "none"; xp: number; badge: BadgeId; badgeUp: boolean };
    }
  | { t: "omakase"; on: boolean }
  | { t: "pong"; serverTimeMs: number }
  | { t: "error"; code: ErrorCode; message?: string }
  | { t: "bye"; reason: "replaced" | "shutdown" | "idle" | "lifetime" | "protocol"; reconnect: boolean };

export function sideName(side: 0 | 1): "a" | "b" {
  return side === 0 ? "a" : "b";
}
