import WebSocket from "ws";
import type { ServerMsg } from "../../src/protocol";

/** Minimal test client: records every server message, lets tests await a matching one. */
export class TestClient {
  readonly messages: ServerMsg[] = [];
  closed: { code: number; reason: string } | null = null;
  private waiters: { pred: (m: ServerMsg) => boolean; resolve: (m: ServerMsg) => void }[] = [];
  private closeWaiters: (() => void)[] = [];
  onMessage: ((m: ServerMsg, c: TestClient) => void) | null = null;

  private constructor(readonly ws: WebSocket) {
    ws.on("message", (data: WebSocket.RawData) => {
      const text = Buffer.isBuffer(data) ? data.toString("utf8") : Array.isArray(data) ? Buffer.concat(data).toString("utf8") : Buffer.from(data).toString("utf8");
      const msg = JSON.parse(text) as ServerMsg;
      this.messages.push(msg);
      this.onMessage?.(msg, this);
      this.waiters = this.waiters.filter((w) => {
        if (!w.pred(msg)) return true;
        w.resolve(msg);
        return false;
      });
    });
    ws.on("close", (code, reason) => {
      this.closed = { code, reason: reason.toString() };
      for (const w of this.closeWaiters) w();
    });
  }

  static open(url: string): Promise<TestClient> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url);
      const c = new TestClient(ws);
      ws.once("open", () => { resolve(c); });
      ws.once("error", reject);
    });
  }

  send(obj: unknown): void {
    this.ws.send(JSON.stringify(obj));
  }

  hello(uid: string, extra: Record<string, unknown> = {}): void {
    this.send({ t: "hello", proto: 1, idToken: `dev:${uid}`, ...extra });
  }

  waitFor<T extends ServerMsg["t"]>(t: T, pred: (m: Extract<ServerMsg, { t: T }>) => boolean = () => true, timeoutMs = 10_000): Promise<Extract<ServerMsg, { t: T }>> {
    const existing = this.messages.find((m) => m.t === t && pred(m as Extract<ServerMsg, { t: T }>));
    if (existing) return Promise.resolve(existing as Extract<ServerMsg, { t: T }>);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { reject(new Error(`timeout waiting for ${t}; got ${this.messages.map((m) => m.t).join(",")}`)); }, timeoutMs);
      this.waiters.push({
        pred: (m) => m.t === t && pred(m as Extract<ServerMsg, { t: T }>),
        resolve: (m) => {
          clearTimeout(timer);
          resolve(m as Extract<ServerMsg, { t: T }>);
        },
      });
    });
  }

  waitClose(timeoutMs = 5000): Promise<{ code: number; reason: string }> {
    if (this.closed) return Promise.resolve(this.closed);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { reject(new Error("timeout waiting for close")); }, timeoutMs);
      this.closeWaiters.push(() => {
        clearTimeout(timer);
        if (this.closed) resolve(this.closed);
      });
    });
  }

  close(): void {
    this.ws.close();
  }

  /** Plays like a child who taps a move as soon as the gauge is full (or pre-selects). */
  autoplay(slot = 0): void {
    let seq = 0;
    this.onMessage = (m) => {
      if (m.t === "match") {
        seq = 0;
        this.send({ t: "select", seq: ++seq, slot });
      }
      if (m.t === "ev") {
        const me = this.messages.findLast((x) => x.t === "match");
        const mySide = me?.t === "match" ? (me.you === "a" ? 0 : 1) : -1;
        // dev engine: `act`; Engine v3: `select` (the move was chosen, queue the next one).
        if (m.events.some((e) => (e.type === "act" || e.type === "select") && e.side === mySide)) this.send({ t: "select", seq: ++seq, slot });
      }
    };
  }
}
