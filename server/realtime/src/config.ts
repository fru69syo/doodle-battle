/** Runtime configuration from environment variables (set by Terraform on Cloud Run). */

export interface Config {
  port: number;
  projectId: string | undefined;
  production: boolean;
  engine: "v3" | "dev";
  authMode: "firebase" | "insecure-dev";
  requireAppCheck: boolean;
  logLevel: string | undefined;
  logPretty: boolean;
  /** Real-time tick length; 100 ms = 10 Hz. Tests shorten it. */
  tickMs: number;
  maxConnections: number;
  helloTimeoutMs: number;
  idleTimeoutMs: number;
  /** Close connections that are not in a match before Cloud Run's request timeout (900 s). */
  maxConnectionMs: number;
  /** Seconds Cloud Run waits after SIGTERM before killing the container is 10; stay below. */
  shutdownGraceMs: number;
}

function bool(v: string | undefined, def: boolean): boolean {
  if (v === undefined || v === "") return def;
  return v === "1" || v.toLowerCase() === "true";
}

function num(v: string | undefined, def: number): number {
  const n = Number(v);
  return v !== undefined && v !== "" && Number.isFinite(n) ? n : def;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const production = env.NODE_ENV === "production";
  const engine = env.BATTLE_ENGINE === "dev" ? "dev" : "v3";
  const authMode = env.AUTH_MODE === "insecure-dev" ? "insecure-dev" : "firebase";
  if (production && authMode === "insecure-dev") {
    throw new Error("AUTH_MODE=insecure-dev is not allowed with NODE_ENV=production");
  }
  return {
    port: num(env.PORT, 8080),
    projectId: env.GCP_PROJECT_ID ?? env.GOOGLE_CLOUD_PROJECT,
    production,
    engine,
    authMode,
    requireAppCheck: bool(env.REQUIRE_APP_CHECK, production),
    logLevel: env.LOG_LEVEL,
    logPretty: bool(env.LOG_PRETTY, false),
    tickMs: num(env.TICK_MS, 100),
    maxConnections: num(env.MAX_CONNECTIONS, 240),
    helloTimeoutMs: num(env.HELLO_TIMEOUT_MS, 5_000),
    idleTimeoutMs: num(env.IDLE_TIMEOUT_MS, 10 * 60_000),
    maxConnectionMs: num(env.MAX_CONNECTION_MS, 14 * 60_000),
    shutdownGraceMs: num(env.SHUTDOWN_GRACE_MS, 8_000),
  };
}
