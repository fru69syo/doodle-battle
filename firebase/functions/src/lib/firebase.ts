import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

let firestore: Firestore | undefined;

function app() {
  return getApps()[0] ?? initializeApp();
}

export function db(): Firestore {
  if (!firestore) {
    firestore = getFirestore(app());
    firestore.settings({ ignoreUndefinedProperties: true });
  }
  return firestore;
}

export function bucket() {
  return getStorage(app()).bucket();
}

export function auth() {
  return getAuth(app());
}

/** Firestore collection names. */
export const COL = {
  users: "users",
  snapshots: "snapshots",
  queue: "queue",
  matches: "matches",
  turns: "turns",
  matchPrivate: "private",
  reports: "reports",
  moderationQueue: "moderationQueue",
  rateLimits: "rateLimits",
  moderationLog: "moderationLog",
  aiSuggestionReports: "aiSuggestionReports",
} as const;

export function snapshotImagePath(snapshotId: string): string {
  return `snapshotImages/${snapshotId}/image.png`;
}
