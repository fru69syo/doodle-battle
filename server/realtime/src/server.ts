/**
 * HTTP + WebSocket front door.
 *
 *   GET /healthz  -> {"ok":true,...}   (Cloud Run probes, uptime check)
 *   GET /v2       -> WebSocket upgrade (docs/REALTIME_PROTOCOL.md)
 *
 * Per connection: the first message must be `hello` (within 5 s) with a Firebase ID token and an
 * App Check token. Messages are size- and rate-limited before they reach the hub.
 */
import { createServer, type IncomingMessage, type Server } from "node:http";
import type { Duplex } from "node:stream";
import { WebSocketServer, type RawData, type WebSocket } from "ws";
import { AuthError, type Verifier } from "./auth";
import type { Config } from "./config";
import { Hub, HubError, type Conn } from "./hub";
import type { Logger } from "./log";
import { TickLoop } from "./loop";
import { ClientMessage, Hello, MAX_HELLO_BYTES, MAX_MESSAGE_BYTES, PATH, PROTOCOL_VERSION, type ErrorCode, type ServerMsg } from "./protocol";

export const CLOSE = {
  normal: 1000,
  goingAway: 1001,
  restart: 1012,
  badMessage: 4400,
  unauthenticated: 4401,
  forbidden: 4403,
  helloTimeout: 4408,
  replaced: 4409,
  rateLimited: 4429,
  busy: 4503,
} as const;

/** Token bucket: 5 messages/s sustained, bursts of 10. */
export class RateLimiter {
  private tokens: number;
  private last: number;
  constructor(
    private readonly perSec = 5,
    private readonly burst = 10,
    private readonly now: () => number = Date.now,
  ) {
    this.tokens = burst;
    this.last = now();
  }
  take(): boolean {
    const t = this.now();
    this.tokens = Math.min(this.burst, this.tokens + ((t - this.last) / 1000) * this.perSec);
    this.last = t;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

export interface ServerDeps {
  config: Pick<Config, "port" | "tickMs" | "maxConnections" | "helloTimeoutMs" | "idleTimeoutMs" | "maxConnectionMs" | "shutdownGraceMs" | "engine">;
  hub: Hub;
  verifier: Verifier;
  log: Logger;
  heartbeatMs?: number;
}

export class RealtimeServer {
  readonly http: Server;
  private readonly wss: WebSocketServer;
  private readonly loop: TickLoop;
  private readonly sockets = new Set<WebSocket>();
  private nextConnId = 1;
  private readonly startedAt = Date.now();
  private heartbeat: NodeJS.Timeout | null = null;

  constructor(private readonly d: ServerDeps) {
    this.http = createServer((req, res) => {
      if (req.method === "GET" && (req.url === "/healthz" || req.url === "/")) {
        res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
        res.end(JSON.stringify({ ok: true, draining: d.hub.draining, engine: d.config.engine, uptimeS: Math.round((Date.now() - this.startedAt) / 1000) }));
        return;
      }
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
    });
    this.wss = new WebSocketServer({ noServer: true, maxPayload: MAX_HELLO_BYTES, perMessageDeflate: false });
    this.http.on("upgrade", (req: IncomingMessage, socket: Duplex, head: Buffer) => { this.onUpgrade(req, socket, head); });
    this.loop = new TickLoop(d.config.tickMs, () => { d.hub.tick(); }, (ms) => { d.hub.noteTickLag(ms); });
  }

  listen(port = this.d.config.port, host?: string): Promise<number> {
    return new Promise((resolve) => {
      this.http.listen(port, host, () => {
        const addr = this.http.address();
        const p = typeof addr === "object" && addr ? addr.port : port;
        this.loop.start();
        this.heartbeat = setInterval(() => { this.sweep(); }, this.d.heartbeatMs ?? 15_000);
        this.heartbeat.unref();
        this.d.log.info("listening", { event: "server_start", port: p, engine: this.d.config.engine });
        resolve(p);
      });
    });
  }

  private onUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer): void {
    const path = (req.url ?? "").split("?")[0];
    if (path !== PATH) {
      socket.end("HTTP/1.1 404 Not Found\r\n\r\n");
      return;
    }
    if (this.d.hub.draining || this.sockets.size >= this.d.config.maxConnections) {
      socket.end("HTTP/1.1 503 Service Unavailable\r\nRetry-After: 2\r\n\r\n");
      return;
    }
    this.wss.handleUpgrade(req, socket, head, (ws) => { this.onSocket(ws); });
  }

  private onSocket(ws: WebSocket): void {
    this.sockets.add(ws);
    const id = this.nextConnId++;
    const opened = Date.now();
    let lastActivity = opened;
    let uid: string | null = null;
    let helloPending = false;
    let alive = true;
    let violations = 0;
    const limiter = new RateLimiter();

    const send = (msg: ServerMsg) => {
      if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
    };
    const conn: Conn = { id, send, close: (code, reason) => { ws.close(code, reason); } };
    const fail = (code: ErrorCode, closeCode?: number, message?: string) => {
      send({ t: "error", code, ...(message ? { message } : {}) });
      if (closeCode !== undefined) ws.close(closeCode, code);
    };

    const helloTimer = setTimeout(() => {
      if (uid === null) fail("UNAUTHENTICATED", CLOSE.helloTimeout, "hello timeout");
    }, this.d.config.helloTimeoutMs);

    (ws as WebSocket & { meta?: unknown }).meta = {
      check: (now: number) => {
        if (!alive) {
          ws.terminate();
          return;
        }
        alive = false;
        ws.ping();
        if (uid === null) return;
        const busy = this.d.hub.isBusy(uid);
        if (!busy && now - lastActivity > this.d.config.idleTimeoutMs) {
          send({ t: "bye", reason: "idle", reconnect: false });
          ws.close(CLOSE.normal, "idle");
        } else if (!busy && now - opened > this.d.config.maxConnectionMs) {
          // Cloud Run ends every request at its timeout (15 min); leave earlier, cleanly.
          send({ t: "bye", reason: "lifetime", reconnect: true });
          ws.close(CLOSE.normal, "lifetime");
        }
      },
    };
    ws.on("pong", () => {
      alive = true;
    });

    ws.on("message", (data: RawData, isBinary: boolean) => {
      lastActivity = Date.now();
      const size = Array.isArray(data) ? data.reduce((n, b) => n + b.length, 0) : data instanceof ArrayBuffer ? data.byteLength : data.length;
      if (isBinary || size > (uid === null ? MAX_HELLO_BYTES : MAX_MESSAGE_BYTES)) {
        fail("BAD_MESSAGE", CLOSE.badMessage, "too large or binary");
        return;
      }
      if (!limiter.take()) {
        violations++;
        fail("RATE_LIMITED", violations > 20 ? CLOSE.rateLimited : undefined);
        return;
      }
      let json: unknown;
      try {
        const text = Buffer.isBuffer(data) ? data.toString("utf8") : Array.isArray(data) ? Buffer.concat(data).toString("utf8") : Buffer.from(data).toString("utf8");
        json = JSON.parse(text);
      } catch {
        fail("BAD_MESSAGE", CLOSE.badMessage, "invalid json");
        return;
      }
      if (uid === null) {
        if (helloPending) return;
        helloPending = true;
        void this.onHello(json, conn, fail).then((u) => {
          helloPending = false;
          if (u) {
            uid = u;
            clearTimeout(helloTimer);
          }
        });
        return;
      }
      const parsed = ClientMessage.safeParse(json);
      if (!parsed.success) {
        fail("BAD_MESSAGE", undefined, "unknown message");
        return;
      }
      const msg = parsed.data;
      const me = uid;
      switch (msg.t) {
        case "queue":
          this.d.hub.queue(me, conn, msg.snapshotId).catch((err: unknown) => { this.hubError(err, fail); });
          break;
        case "cancel":
          this.d.hub.cancel(me, conn);
          break;
        case "select":
          this.d.hub.select(me, conn, msg.seq, msg.slot);
          break;
        case "ping":
          send({ t: "pong", serverTimeMs: Date.now() });
          break;
      }
    });

    ws.on("close", () => {
      clearTimeout(helloTimer);
      this.sockets.delete(ws);
      if (uid !== null) this.d.hub.disconnect(uid, conn);
    });
    ws.on("error", (err) => { this.d.log.warn("socket error", { err: err.message }); });
  }

  private async onHello(json: unknown, conn: Conn, fail: (c: ErrorCode, close?: number, m?: string) => void): Promise<string | null> {
    const versionOnly = (json as { proto?: unknown } | null)?.proto;
    const hello = Hello.safeParse(json);
    if (!hello.success) {
      if (typeof versionOnly === "number" && versionOnly !== PROTOCOL_VERSION) fail("PROTOCOL_VERSION", CLOSE.badMessage, `server speaks ${PROTOCOL_VERSION}`);
      else fail("BAD_MESSAGE", CLOSE.badMessage, "expected hello");
      return null;
    }
    let uid: string;
    try {
      uid = (await this.d.verifier.verify(hello.data.idToken, hello.data.appCheckToken)).uid;
    } catch (err) {
      const code = err instanceof AuthError ? err.code : "UNAUTHENTICATED";
      this.d.log.warn("auth rejected", { event: "auth_rejected", reason: code });
      fail(code, CLOSE.unauthenticated);
      return null;
    }
    try {
      await this.d.hub.connect(uid, conn, hello.data.lastSeq);
    } catch (err) {
      this.hubError(err, fail, CLOSE.forbidden);
      if (err instanceof HubError && err.code === "CONSENT_REQUIRED") this.d.log.info("auth rejected", { event: "auth_rejected", reason: "CONSENT_REQUIRED" });
      return null;
    }
    return uid;
  }

  private hubError(err: unknown, fail: (c: ErrorCode, close?: number, m?: string) => void, closeCode?: number): void {
    if (err instanceof HubError) {
      fail(err.code, closeCode, err.message);
      return;
    }
    this.d.log.error("unexpected error", { err });
    fail("INTERNAL", closeCode);
  }

  private sweep(): void {
    const now = Date.now();
    for (const ws of this.sockets) (ws as WebSocket & { meta?: { check(n: number): void } }).meta?.check(now);
  }

  /** Graceful stop (SIGTERM): drain the hub, close sockets, stop the HTTP server. */
  async close(): Promise<void> {
    this.d.log.info("shutting down", { event: "server_stop", ...this.d.hub.stats() });
    await this.d.hub.shutdown(Math.max(0, this.d.config.shutdownGraceMs - 1000));
    this.loop.stop();
    if (this.heartbeat) clearInterval(this.heartbeat);
    // Give the close handshakes (and the `bye` messages before them) a moment to flush.
    await new Promise((r) => setTimeout(r, 200));
    for (const ws of this.sockets) ws.terminate();
    await new Promise<void>((resolve) => {
      this.wss.close(() => {
        this.http.close(() => { resolve(); });
        this.http.closeAllConnections();
      });
    });
  }
}
