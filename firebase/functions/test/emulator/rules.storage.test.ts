import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import { getBytes, ref, uploadBytes, type FirebaseStorage } from "firebase/storage";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { BUCKET, PROJECT_ID } from "../helpers/setupEmulator";
import { makePng } from "../helpers/png";

let env: RulesTestEnvironment;
const png = new Uint8Array(makePng(32, 32));

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8") },
    storage: { rules: readFileSync(resolve(__dirname, "../../../storage.rules"), "utf8") },
  });
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "snapshots/active1"), { ownerUid: "bob", status: "active" });
    await setDoc(doc(ctx.firestore(), "snapshots/hidden1"), { ownerUid: "bob", status: "hidden" });
    const st = ctx.storage(`gs://${BUCKET}`);
    await uploadBytes(ref(st, "snapshotImages/active1/image.png"), png, { contentType: "image/png" });
    await uploadBytes(ref(st, "snapshotImages/hidden1/image.png"), png, { contentType: "image/png" });
    await uploadBytes(ref(st, "other/file.png"), png, { contentType: "image/png" });
  });
});

const st = (uid: string | null): FirebaseStorage =>
  (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage(`gs://${BUCKET}`);

describe("storage.rules", () => {
  it("signed-in players can read images of active snapshots only", async () => {
    await assertSucceeds(getBytes(ref(st("alice"), "snapshotImages/active1/image.png")));
    await assertFails(getBytes(ref(st("alice"), "snapshotImages/hidden1/image.png")));
    await assertFails(getBytes(ref(st(null), "snapshotImages/active1/image.png")));
    await assertFails(getBytes(ref(st("alice"), "snapshotImages/missing/image.png")));
  });

  it("owners can still read their hidden snapshot", async () => {
    await assertSucceeds(getBytes(ref(st("bob"), "snapshotImages/hidden1/image.png")));
  });

  it("clients can never write, and other paths are closed", async () => {
    await assertFails(uploadBytes(ref(st("bob"), "snapshotImages/active1/image.png"), png));
    await assertFails(uploadBytes(ref(st("bob"), "snapshotImages/new/image.png"), png));
    await assertFails(uploadBytes(ref(st("bob"), "users/bob/x.png"), png));
    await assertFails(getBytes(ref(st("bob"), "other/file.png")));
  });
});
