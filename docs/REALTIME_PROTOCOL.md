# Realtime battle protocol v1 (online rated play)

Owner: GCP team (`server/realtime/`). Audience: the client team (Flutter / Puppet), the Engine
team, and whoever operates the server. Product rules come from `docs/SPEC.md` §12 and
`docs/GAME_DESIGN_V2.md` §6–§8; infrastructure choices from `docs/V2_INFRA.md` §3 and
`docs/LEARN_GCP.md`.

- Machine-readable contract: [`server/realtime/protocol.schema.json`](../server/realtime/protocol.schema.json)
  (JSON Schema 2020-12). Tests keep it identical to what the server enforces and validate every
  message of a full test match against it.
- Server source: `server/realtime/src/protocol.ts` (types), `server.ts` (connection),
  `hub.ts` (queue, matches, settlement), `match.ts` (timers), `rating.ts` (Elo, badges).

## 1. Transport

| | |
|---|---|
| URL | `wss://<cloud-run-host>/v2` (Terraform output `realtime_url`; the app reads it from its build config) |
| Frames | UTF-8 **text** frames, one JSON object per frame. Binary frames are rejected. |
| Size | First message (`hello`) ≤ 8 KB (it carries two tokens); every later message ≤ 512 bytes. |
| Rate | ≤ 5 messages/s sustained, bursts of 10. Above that the server answers `error RATE_LIMITED` and drops the message; persistent abuse closes the socket (4429). |
| Keep-alive | The server sends WebSocket pings every 15 s; a client that does not answer two in a row is dropped. Clients may also send `{"t":"ping"}` to measure RTT. |
| Lifetime | Cloud Run ends every request at 15 min. The server closes idle sockets (not queued, not in a match) after 10 min (`bye idle`) and sockets older than 14 min that are not in a match (`bye lifetime`, `reconnect:true`). A socket is never closed by the server during a match except on shutdown. |
| Health | `GET /healthz` → `{"ok":true,"draining":false,"engine":"v3","uptimeS":…}` |

**When to connect (cost).** Cloud Run bills while at least one socket is open. Open the socket
when the child taps 「たたかう」 (online), close it on the result screen or when leaving the online
menu. Do not keep it open in the background or on the home screen.

## 2. Session flow

```
app                                   server
 │ ── WebSocket upgrade /v2 ───────────► │
 │ ── hello {idToken, appCheckToken} ──► │ verify ID token + App Check, users/{uid}.consent.online
 │ ◄────────────── welcome {inMatch} ─── │ (or error + close)
 │ ── queue {snapshotId} ──────────────► │ snapshot must be yours, active, Lv ≥ 5 → Lv50 sync
 │ ◄──────────────────── queued ──────── │
 │        … matchmaking: PvP within the rating band, else a ghost after N s …
 │ ◄──── match {matchId, you, a, b} ──── │
 │ ◄──── snap (2 Hz) / ev (on events) ── │  10 Hz server-authoritative ATB
 │ ── select {seq, slot} ──────────────► │  (any time: while charging = さきどり)
 │ ◄──── sel {seq, accepted, queued} ─── │  private ack, the opponent never sees it
 │ ◄──── end {winner, reason, you} ───── │  rating/XP/badge already saved
 │ ── queue … (play again) or close ──► │
```

## 3. Client → server

All messages have a string `t`. Unknown fields are rejected (`BAD_MESSAGE`).

### `hello` (must be the first message, within 5 s)
```json
{ "t": "hello", "proto": 1, "idToken": "<Firebase ID token>", "appCheckToken": "<App Check token>", "lastSeq": 17 }
```
- `idToken`: from `FirebaseAuth.instance.currentUser.getIdToken()` (anonymous sign-in). Never cache
  across app restarts; refresh if older than ~55 min.
- `appCheckToken`: `FirebaseAppCheck.instance.getToken()`. Required in production
  (`REQUIRE_APP_CHECK=true`). Debug builds use App Check debug tokens.
- `lastSeq` (optional): the highest `ev.seq` the app has applied. Send it when reconnecting during a
  match; the server replays the events after it. Omit on a fresh session.

### `queue`
```json
{ "t": "queue", "snapshotId": "Abc123" }
```
`snapshotId` = the registered character (`Character.onlineId`, from `registerCharacter`). Idempotent:
re-sending while queued just returns `queued` again.

### `cancel`
```json
{ "t": "cancel" }
```
Leaves the queue (answered with `cancelled`). Has no effect on a running match.

### `select`
```json
{ "t": "select", "seq": 3, "slot": 1 }
```
- `slot` 0–3 = move slot as listed in `match.you.moves`.
- `seq`: per-match counter, strictly increasing (start at 1 after every `match`). Stale or duplicate
  `seq` values are answered with `sel {accepted:false, reason:"stale"}`.
- May be sent **at any time**: while the gauge is filling it is stored (さきどり) and used in the
  very tick the gauge becomes full; a later `select` replaces it. When the gauge is full it is used
  in the next tick (≤ 100 ms).

### `ping`
```json
{ "t": "ping" }
```

## 4. Server → client

| `t` | Fields | Meaning |
|---|---|---|
| `welcome` | `proto`, `serverTimeMs`, `inMatch` | Handshake accepted. `inMatch:true` means a `match` (+ missed events) follows: the child was reconnected to the running match. |
| `queued` | `snapshotId` | In the queue. Show 「あいてを さがしているよ」. |
| `cancelled` | – | Left the queue. |
| `match` | `matchId`, `you` (`"a"`/`"b"`), `tickHz` (10), `decisionTicks` (50), `a`, `b` (`FighterInfo`), `resumed` | Battle starts (or resumes). |
| `ev` | `seq`, `tick`, `events[]` | Things that happened in one tick, in order. `seq` increases by 1 per message. |
| `snap` | `tick`, `a`, `b` (`SideView`), `hash` | State every 5 ticks (2 Hz) and at the end. Interpolate gauges between snaps. |
| `sel` | `seq`, `slot`, `accepted`, `queued`, `reason?` | Private answer to `select`. `queued:true` = stored for さきどり. `accepted:false, reason:"unusable"` = the move cannot be used now (SP/cooldown): let the child pick again. |
| `end` | `matchId`, `winner`, `reason`, `you {outcome, xp, badge, badgeUp}` | Final result, already persisted. `reason`: `ko`, `timeout` (3 min, HP ratio), `forfeit` (a side was away 30 s), `aborted` (server restart: no rating/XP change). `xp` is added to the local character by the app. |
| `pong` | `serverTimeMs` | Answer to `ping`. |
| `error` | `code`, `message?` | See §6. `message` is for logs only; map `code` to a gentle kid message. |
| `bye` | `reason`, `reconnect` | The server is about to close the socket. If `reconnect:true`, reconnect silently (see §7). |

`FighterInfo`:
```json
{
  "displayName": "げんきな うさぎ",      // preset words (setDisplayName), "" or "かがみ" for a mirror ghost
  "characterName": "ねこまる",
  "imagePath": "snapshotImages/Abc123/image.png",
  "rig": { "...": "puppet rig as saved by the owner (opaque)" },
  "attr": "gu",                          // gu / choki / pa
  "moves": [{ "slot": 0, "name": "ぱんち", "templateId": "strike", "attr": "gu", "spCost": 0 }],
  "maxHp": 944,
  "level": 50,                           // rated play is always Lv50 (GAME_DESIGN_V2 §8)
  "badge": "rabbit",                     // best badge ever; never goes down
  "isGhost": false
}
```
`SideView`: `{ "hp", "maxHp", "sp" (1/100 SP, 0–10000), "gauge" (0–10000), "ready", "casting" }`.

Battle events (`ev.events[]`) always have `tick` and `type`, most have `side` (0 = a, 1 = b). Types
from the dev engine: `ready`, `act {slot}`, `cast {slot, ticks}`, `hit {dmg, hp, typePct}`,
`heal {amount, hp}`, `ko`, `end {winner, reason}`; added by the server: `autoPick {slot}` (5 s
timeout), `forfeit`. Engine v3 may add more types: **ignore unknown types**.

Badge ids → names: `egg` たまご, `chick` ひよこ, `rabbit` うさぎ, `fox` きつね, `bear` くま,
`lion` ライオン, `dragon` ドラゴン, `legend` でんせつ. The rating number is never sent.

## 5. Timing rules (server-owned)

| Rule | Value | Source |
|---|---|---|
| Tick | 100 ms (10 Hz), integer state | GAME_DESIGN_V2 §6.1 |
| Decision timeout | 50 ticks after the gauge filled **+ 3 ticks network grace** → おまかせ picks (`autoPick` event) | §6.3, §6.7 |
| さきどり | a queued `select` is used in the tick the gauge fills | §6.3 |
| Ghost / away AI | おまかせ "normal", thinks 10 ticks after ready | §6.6 |
| Disconnect | after 10 s away おまかせ plays for the child; back within 30 s = full control again; 30 s away = loss, XP 0 (rating counts as a loss) | §6.7 |
| Both away 30 s | match aborted, nothing saved | server |
| Hard cap | 1800 ticks (3 min), decided by HP ratio | §6.1 |

Clients render with a 150–250 ms delay and interpolate (GAME_DESIGN_V2 §6.7). Do not run the
battle engine for online matches; the server's `ev`/`snap` are the truth.

## 6. Errors and close codes

| `error.code` | When | Suggested kid message |
|---|---|---|
| `UNAUTHENTICATED` | bad/expired ID token, or no `hello` within 5 s (closes 4401 / 4408) | refresh the token and retry silently once |
| `APP_CHECK_FAILED` | App Check token missing/invalid (4401) | 「いまは つながらないよ」 |
| `CONSENT_REQUIRED` | `users/{uid}.consent.online` is not true (4403) | 「おうちのひとに オンラインを ゆるして もらってね」 |
| `PROTOCOL_VERSION` | `proto` ≠ 1 (4400) | ask to update the app |
| `BAD_MESSAGE` | invalid JSON/fields, binary, too large (too large: 4400) | – (bug) |
| `RATE_LIMITED` | > 5 msg/s | – |
| `NOT_FOUND` / `NOT_OWNER` | snapshot missing, not active, or someone else's | 「もういちど とうろく してね」 |
| `LEVEL_TOO_LOW` | character below Lv5 | 「レベル5に なったら オンラインで あそべるよ」 |
| `ALREADY_IN_MATCH` / `NOT_IN_MATCH` | queue during a match / select outside a match | – (client state bug) |
| `DRAINING` | server is restarting | reconnect after 1–2 s |
| `INTERNAL` | unexpected | 「うまく いかなかったよ」 |

Close codes: 1000 normal, 1012 server restart, 4400 bad message, 4401 unauthenticated,
4403 forbidden (consent), 4408 hello timeout, 4409 replaced by a newer connection of the same
uid, 4429 rate limited. HTTP 503 on the upgrade = too many connections or draining: retry with
backoff (1 s, 2 s, 4 s, max 3 tries) while still showing the searching screen.

## 7. Reconnecting (invisible to the child)

- One live connection per uid: a new `hello` for the same uid replaces the old socket (`bye
  replaced`, close 4409).
- During a match, on any drop (network change, iOS background), reconnect immediately with a
  fresh ID token and `lastSeq`. The server answers `welcome {inMatch:true}`, `match {resumed:true}`,
  the missed `ev`s and a `snap`. If the match ended while away, a `hello` with `lastSeq` gets the
  `end` again (kept 5 minutes).
- `bye {reconnect:true}` (`shutdown`, `lifetime`): reconnect and re-`queue` if the child was
  waiting. A running match is aborted on shutdown (`end reason:"aborted"`); show 「またあそぼう」
  and no result.
- Exponential backoff on repeated failures; after ~30 s give up and offer single-player.

## 8. Matchmaking, rating, cost mode (what the client may assume)

- Rating: Elo per user, start 1000, floor 600, K 48 for the first 20 rated games then 24, half
  against ghosts. Band ±100, +50 every 5 s, max ±400; both players' bands must accept. Same pair
  at most once per 60 min. XP for 20 rated matches per JST day.
- Ghost after `ghostAfterSec` from `config/costMode` (normal 20 s, saving 8 s, minimal 3 s; no PvP
  in minimal). The app shows the same searching animation regardless.
- If no other registered character exists yet, the opponent is a mirror of the child's own
  character (`displayName: "かがみ"`).
- Results are written by the server: `users/{uid}.rated`, `snapshots/{id}.ghostRating`,
  `rtMatches/{matchId}` (players may read; no rating numbers), `replays/{matchId}` (server-only,
  deleted after 30 days). `deleteMyData` removes `rtMatches`/`replays` of the child.

## 9. Engine swap (Engine team → GCP team)

The server is written against `server/realtime/src/engine.ts`, a narrow interface mirroring the
prototype (`app/lib/domain/battle_v2/atb_engine.dart`, `shared/battle_spec_v3/`). Until Engine v3
lands it runs `src/engines/devEngine.ts` (`BATTLE_ENGINE=dev`), a simplified stand-in that is
**not** the game rules. Production refuses to start with `BATTLE_ENGINE=v3` until the swap is done,
so the stand-in can never be used for rated play by accident (dev Terraform sets `dev`).

Swap steps:
1. `cd server/realtime && npm i ../../shared/battle_engine_v3_ts` (a `file:` dependency; the
   Dockerfile must then also `COPY shared/battle_engine_v3_ts/` before `npm ci`, and
   `Dockerfile.dockerignore` must allow it).
2. Add `src/engines/v3Engine.ts` implementing `BattleEngine`:
   - `ratedFighter(source, 50)` → v3 `ratedStats(actualLevel)` with the character's own growth and
     the moves actually unlocked (2 / 3 at Lv10 / 4 at Lv50); `source.data` is the snapshot
     document written by the v2 `registerCharacter`.
   - `createBattle(a, b, {seed})` → v3 battle with **`decisionTicks` disabled**
     (`Number.MAX_SAFE_INTEGER`): the server owns the 5 s timer and passes the おまかせ choice as
     an input.
   - `step([slotA, slotB])` → one tick; return the tick's events and which inputs were used.
   - `chooseMove(side, tier)` → v3 `chooseMove` with the side's AI stream.
   - `stateHash()` → FNV-1a of the canonical state (as in the golden vectors).
3. `loadEngine("v3")` in `src/engines/index.ts` returns it; add a test that replays the
   `battles` golden vectors of `shared/battle_spec_v3/golden_vectors.json` through the adapter
   (inputs at their ticks, timers disabled) and compares winner/tick/HP/event hash.
4. Set `realtime_battle_engine = "v3"` for dev in Terraform (prod already defaults to v3) and deploy.

## 10. Versioning

`proto` is bumped only for breaking changes. Additive changes (new optional fields, new event
types, new error codes) keep `proto: 1`; clients must ignore unknown fields and event types.
