# Realtime battle server

Cloud Run WebSocket server for online rated battles (server-authoritative 10 Hz ATB).
Protocol: [`docs/REALTIME_PROTOCOL.md`](../../docs/REALTIME_PROTOCOL.md) ·
GCP setup and operations: [`docs/LEARN_GCP.md`](../../docs/LEARN_GCP.md) ·
Infrastructure: [`infra/terraform/modules/realtime_service`](../../infra/terraform/modules/realtime_service).

```bash
(cd ../../shared/battle_engine_v3_ts && npm ci)   # Engine v3 is a file: dependency; build it first
npm ci
npm run lint          # tsc --noEmit + eslint (strict type-checked)
npm test              # unit + integration (two ws clients play full matches; offline)
npm run build         # -> lib/
npm run test:firestore  # FirestoreStore against the Firestore emulator (Java 21 + firebase CLI)
```

Run locally against the Firestore emulator (Engine v3, dev tokens `dev:<uid>`; snapshots must be
v2 ones written by `registerCharacter` schema 2):

```bash
# terminal 1 (from firebase/functions): npx firebase emulators:start --config ../firebase.json --project demo-doodle-battle --only firestore
PORT=8081 FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCP_PROJECT_ID=demo-doodle-battle npm run dev
# a client then sends {"t":"hello","proto":1,"idToken":"dev:alice"} to ws://localhost:8081/v2
```
(`AUTH_MODE=insecure-dev` is refused when `NODE_ENV=production`.)

| Path | What |
|---|---|
| `src/server.ts` | HTTP `/healthz`, WebSocket upgrade, hello/auth, size + rate limits, keep-alive |
| `src/hub.ts` | connections (one per uid), queue, match creation (PvP / ghost / mirror), settlement, SIGTERM drain |
| `src/matchmaker.ts` | rating band, ghost timing from cost mode, same-pair cooldown |
| `src/match.ts` | one match: さきどり, 5 s (+3 tick) おまかせ, ghost AI, disconnect rules, event log |
| `src/rating.ts` / `src/results.ts` | Elo, badges, XP cap; pure settlement |
| `src/engine.ts` | engine interface; `src/engines/v3Engine.ts` adapts the shared Engine v3 (protocol §9); `src/engines/devEngine.ts` is a local-only stand-in (refused with `NODE_ENV=production`) |
| `src/firestoreStore.ts` | users, snapshots, ghosts, `rtMatches`, `replays` (Admin SDK) |
| `protocol.schema.json` | JSON Schema of every message (tested against the server) |
| `Dockerfile` | build from the repo root: `docker build -f server/realtime/Dockerfile .` |

Environment: `PORT`, `GCP_PROJECT_ID`, `BATTLE_ENGINE` (`v3` default; `dev` = stand-in, local only), `REQUIRE_APP_CHECK`,
`LOG_LEVEL`, `AUTH_MODE` (dev only), `TICK_MS`, `MAX_CONNECTIONS`, `IDLE_TIMEOUT_MS`,
`MAX_CONNECTION_MS`, `SHUTDOWN_GRACE_MS` (see `src/config.ts`).
