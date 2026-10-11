/**
 * FirestoreStore against the Firestore emulator (`npm run test:firestore`). Uses the
 * demo-doodle-battle project id, so it can never touch a real project.
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { FirestoreStore } from "../../src/firestoreStore";
import { initialRated } from "../../src/rating";
import { settle, type MatchSummary } from "../../src/results";

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("FIRESTORE_EMULATOR_HOST not set: run `npm run test:firestore`");

let app: App;
let db: Firestore;
let store: FirestoreStore;

beforeAll(() => {
  app = initializeApp({ projectId: "demo-doodle-battle" }, "firestore-store-test");
  db = getFirestore(app);
  store = new FirestoreStore(db, () => 0.5);
});

afterAll(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-doodle-battle/databases/(default)/documents`, { method: "DELETE" });
});

describe("FirestoreStore", () => {
  it("loads a player with consent, display name and rated state", async () => {
    await db.doc("users/u1").set({ consent: { online: true, cloudJudge: false, policyVersion: 1 }, displayName: { text: "げんきな うさぎ" }, rated: { rating: 1100, games: 3, best: 1120 } });
    expect(await store.loadPlayer("u1")).toMatchObject({ consentOnline: true, displayName: "げんきな うさぎ", rated: { rating: 1100, games: 3, best: 1120 } });
    expect(await store.loadPlayer("nobody")).toBeNull();
  });

  it("loads snapshots and picks ghosts near the rating, never the player's own", async () => {
    await db.doc("snapshots/own").set({ ownerUid: "u1", status: "active", level: 20, name: "じぶん", ghostRating: 1000, randomKey: 0.1 });
    await db.doc("snapshots/near").set({ ownerUid: "u2", status: "active", level: 30, name: "ちかい", ownerDisplayName: "あおい くま", ghostRating: 1050, randomKey: 0.2, imagePath: "snapshotImages/near/image.png" });
    await db.doc("snapshots/far").set({ ownerUid: "u3", status: "active", level: 30, name: "とおい", ghostRating: 1700, randomKey: 0.3 });
    await db.doc("snapshots/hidden").set({ ownerUid: "u4", status: "hidden", level: 30, name: "かくれ", ghostRating: 1000, randomKey: 0.4 });
    const own = await store.loadSnapshot("own");
    expect(own).toMatchObject({ snapshotId: "own", ownerUid: "u1", level: 20, display: { characterName: "じぶん" } });

    const g = await store.pickGhost({ rating: 1000, excludeUid: "u1", excludeSnapshotIds: [] });
    expect(g).toMatchObject({ rating: 1050, displayName: "あおい くま", source: { snapshotId: "near" } });

    // Nothing near (excluded): random active fallback, still never own/hidden.
    const g2 = await store.pickGhost({ rating: 1000, excludeUid: "u1", excludeSnapshotIds: ["near"] });
    expect(g2?.source.snapshotId).toBe("far");
  });

  it("settles a match in one transaction: ratings, ghostRating, rtMatches, replay with TTL", async () => {
    await db.doc("users/a").set({ consent: { online: true }, rated: initialRated() });
    await db.doc("users/b").set({ consent: { online: true } });
    await db.doc("snapshots/sa").set({ ownerUid: "a", status: "active", level: 10 });
    await db.doc("snapshots/sb").set({ ownerUid: "b", status: "active", level: 10 });
    const summary: MatchSummary = {
      matchId: "m1",
      mode: "pvp",
      engineId: "dev-0",
      seed: 99,
      startedAtMs: 1_000,
      endedAtMs: 61_000,
      ticks: 400,
      sides: [
        { uid: "a", snapshotId: "sa", level: 10, isGhost: false, ratingAtStart: 1000 },
        { uid: "b", snapshotId: "sb", level: 10, isGhost: false, ratingAtStart: 1000 },
      ],
      winner: 0,
      reason: "ko",
      forfeitSide: null,
      inputs: [{ tick: 36, side: 0, slot: 0, src: "player" }],
      finalHash: "abcd",
      tailEvents: [],
    };
    const r = await store.settleMatch(summary, (rated) => settle(summary, rated));
    expect(r.players.map((p) => p.ratingDelta)).toEqual([24, -24]);
    expect((await db.doc("users/a").get()).data()?.rated).toMatchObject({ rating: 1024, games: 1 });
    expect((await db.doc("users/b").get()).data()?.rated).toMatchObject({ rating: 976, best: 1000 });
    expect((await db.doc("snapshots/sa").get()).data()?.ghostRating).toBe(1024);
    const m = (await db.doc("rtMatches/m1").get()).data();
    expect(m).toMatchObject({ mode: "pvp", playerUids: ["a", "b"], winner: "a", sides: { a: { outcome: "win" } } });
    expect(JSON.stringify(m)).not.toContain("rating");
    const rep = (await db.doc("replays/m1").get()).data();
    expect(rep).toMatchObject({ seed: 99, finalHash: "abcd", ratingDeltas: { a: 24, b: -24 } });
    expect((rep?.expireAt as { toMillis(): number }).toMillis()).toBe(61_000 + 30 * 86_400_000);
  });

  it("reads config/costMode", async () => {
    expect(await store.readCostMode()).toBeUndefined();
    await db.doc("config/costMode").set({ mode: "saving" });
    expect(await store.readCostMode()).toBe("saving");
  });
});
