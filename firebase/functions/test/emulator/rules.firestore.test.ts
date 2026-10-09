import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc, type Firestore } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { PROJECT_ID } from "../helpers/setupEmulator";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8") },
  });
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/bob"), { consent: { cloudJudge: true, online: true, policyVersion: 1 }, rating: 1000 });
    await setDoc(doc(db, "snapshots/s-bob"), { ownerUid: "bob", status: "active" });
    await setDoc(doc(db, "queue/bob"), { uid: "bob", status: "waiting" });
    await setDoc(doc(db, "matches/m1"), { playerUids: ["alice", "bob"], status: "active" });
    await setDoc(doc(db, "matches/m1/turns/1"), { turn: 1 });
    await setDoc(doc(db, "matches/m1/private/actions"), { a: "tackle", b: null });
    await setDoc(doc(db, "reports/x"), { reporterUid: "alice" });
    await setDoc(doc(db, "moderationQueue/s-bob"), { state: "pending" });
    await setDoc(doc(db, "rateLimits/alice"), { buckets: {} });
  });
});

const fs = (uid: string | null): Firestore =>
  (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore() as unknown as Firestore;
const consent = (o: Record<string, unknown> = {}) => ({ cloudJudge: true, online: false, policyVersion: 1, ...o });

describe("users/{uid}", () => {
  it("a user can create only their own consent document", async () => {
    await assertSucceeds(
      setDoc(doc(fs("alice"), "users/alice"), {
        consent: consent(),
        consentUpdatedAt: serverTimestamp(),
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(fs("alice"), "users/carol"), { consent: consent(), consentUpdatedAt: serverTimestamp(), createdAt: serverTimestamp() }),
    );
    await assertFails(
      setDoc(doc(fs(null), "users/alice"), { consent: consent(), consentUpdatedAt: serverTimestamp(), createdAt: serverTimestamp() }),
    );
  });

  it("rejects server-managed or malformed fields", async () => {
    const base = { consentUpdatedAt: serverTimestamp(), createdAt: serverTimestamp() };
    await assertFails(setDoc(doc(fs("alice"), "users/alice"), { ...base, consent: consent(), rating: 9999 }));
    await assertFails(
      setDoc(doc(fs("alice"), "users/alice"), {
        ...base,
        consent: consent(),
        displayName: { text: "free text name" },
      }),
    );
    await assertFails(setDoc(doc(fs("alice"), "users/alice"), { ...base, consent: consent({ online: "yes" }) }));
    await assertFails(setDoc(doc(fs("alice"), "users/alice"), { ...base, consent: consent({ extra: true }) }));
    await assertFails(setDoc(doc(fs("alice"), "users/alice"), { ...base, consent: { cloudJudge: true } }));
    await assertFails(
      setDoc(doc(fs("alice"), "users/alice"), { consent: consent(), consentUpdatedAt: new Date(0), createdAt: serverTimestamp() }),
    );
  });

  it("allows updating consent only", async () => {
    await assertSucceeds(
      updateDoc(doc(fs("bob"), "users/bob"), { consent: consent({ online: false }), consentUpdatedAt: serverTimestamp() }),
    );
    await assertFails(updateDoc(doc(fs("bob"), "users/bob"), { rating: 5000 }));
    await assertFails(updateDoc(doc(fs("bob"), "users/bob"), { activeMatchId: null }));
    await assertFails(
      updateDoc(doc(fs("bob"), "users/bob"), {
        consent: consent(),
        consentUpdatedAt: serverTimestamp(),
        displayName: { adjectiveId: "a01", nounId: "n01", text: "x" },
      }),
    );
    await assertFails(deleteDoc(doc(fs("bob"), "users/bob")));
  });

  it("profiles are private", async () => {
    await assertSucceeds(getDoc(doc(fs("bob"), "users/bob")));
    await assertFails(getDoc(doc(fs("alice"), "users/bob")));
    await assertFails(getDoc(doc(fs(null), "users/bob")));
  });
});

describe("server-owned collections", () => {
  it("snapshots: owner read only, no client writes", async () => {
    await assertSucceeds(getDoc(doc(fs("bob"), "snapshots/s-bob")));
    await assertFails(getDoc(doc(fs("alice"), "snapshots/s-bob")));
    await assertFails(setDoc(doc(fs("bob"), "snapshots/new"), { ownerUid: "bob", status: "active" }));
    await assertFails(updateDoc(doc(fs("bob"), "snapshots/s-bob"), { status: "active", reportCount: 0 }));
  });

  it("queue: own entry readable, never writable", async () => {
    await assertSucceeds(getDoc(doc(fs("bob"), "queue/bob")));
    await assertFails(getDoc(doc(fs("alice"), "queue/bob")));
    await assertFails(setDoc(doc(fs("alice"), "queue/alice"), { uid: "alice", status: "waiting" }));
  });

  it("matches: players read the match and turn log; pending actions stay hidden", async () => {
    await assertSucceeds(getDoc(doc(fs("alice"), "matches/m1")));
    await assertSucceeds(getDoc(doc(fs("alice"), "matches/m1/turns/1")));
    await assertFails(getDoc(doc(fs("carol"), "matches/m1")));
    await assertFails(getDoc(doc(fs("carol"), "matches/m1/turns/1")));
    await assertFails(getDoc(doc(fs("alice"), "matches/m1/private/actions")));
    await assertFails(updateDoc(doc(fs("alice"), "matches/m1"), { status: "finished" }));
    await assertFails(setDoc(doc(fs("alice"), "matches/m1/private/actions"), { a: "special" }));
    await assertFails(setDoc(doc(fs("alice"), "matches/m1/turns/2"), { turn: 2 }));
  });

  it("reports, moderation queue, rate limits and unknown collections are server-only", async () => {
    for (const path of ["reports/x", "moderationQueue/s-bob", "rateLimits/alice", "anything/else"]) {
      await assertFails(getDoc(doc(fs("alice"), path)));
      await assertFails(setDoc(doc(fs("alice"), path), { a: 1 }));
    }
  });
});
