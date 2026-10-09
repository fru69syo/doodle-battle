import { getApps, initializeApp } from "firebase-admin/app";

export const PROJECT_ID = "demo-doodle-battle";
export const BUCKET = `${PROJECT_ID}.appspot.com`;

// Refuse to run anywhere but against local emulators.
for (const v of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]) {
  if (!process.env[v]) throw new Error(`${v} not set: run via "npm run test:emulator"`);
}
process.env.GCLOUD_PROJECT = PROJECT_ID;
// No GCE metadata server locally; skip the credential probe.
process.env.METADATA_SERVER_DETECTION = "none";
if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET });
