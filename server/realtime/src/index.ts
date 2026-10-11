/**
 * Entry point on Cloud Run: wires config, Firebase Admin, the engine and the hub, then serves.
 * Cloud Run sends SIGTERM before stopping an instance (scale-in, new revision) and kills it
 * 10 seconds later; we drain within `shutdownGraceMs`.
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { FirebaseVerifier, InsecureDevVerifier, type Verifier } from "./auth";
import { loadConfig } from "./config";
import { CachedCostMode } from "./costMode";
import { loadEngine } from "./engines";
import { FirestoreStore } from "./firestoreStore";
import { Hub } from "./hub";
import { createLogger, parseSeverity } from "./log";
import { RealtimeServer } from "./server";

async function main(): Promise<void> {
  const config = loadConfig();
  const log = createLogger({ level: parseSeverity(config.logLevel), pretty: config.logPretty });
  const app = initializeApp(config.projectId ? { projectId: config.projectId } : undefined);
  const db = getFirestore(app);
  db.settings({ ignoreUndefinedProperties: true });
  const store = new FirestoreStore(db);
  const engine = loadEngine(config.engine);
  if (config.engine === "dev") log.warn("running the DEV stand-in battle engine", { event: "dev_engine" });
  const verifier: Verifier = config.authMode === "insecure-dev" ? new InsecureDevVerifier() : new FirebaseVerifier(app, config.requireAppCheck);
  const costMode = new CachedCostMode(
    () => store.readCostMode(),
    60_000,
    Date.now,
    (err) => { log.warn("costMode read failed", { err }); },
  );
  void costMode.refresh();
  const hub = new Hub({ engine, store, costMode, log });
  const server = new RealtimeServer({ config, hub, verifier, log });
  await server.listen(config.port);

  let stopping = false;
  const stop = (signal: string) => {
    if (stopping) return;
    stopping = true;
    log.info("signal received", { signal });
    server
      .close()
      .then(() => process.exit(0))
      .catch((err: unknown) => {
        log.error("shutdown failed", { err });
        process.exit(1);
      });
  };
  process.on("SIGTERM", () => { stop("SIGTERM"); });
  process.on("SIGINT", () => { stop("SIGINT"); });
}

main().catch((err: unknown) => {
  createLogger().error("startup failed", { err });
  process.exit(1);
});
