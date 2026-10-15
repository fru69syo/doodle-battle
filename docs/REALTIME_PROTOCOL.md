# Realtime battle protocol v1, revision 3 (online rated play)

Revision 3 (2026-10-15) follows the owner's stackable-gauge decision (SPEC §15, 2026-10-14):
fighters stack 2–5 gauge bars, moves cost 1–5 bars, and **there is no decision timer** any more.

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
 │ ◄─────────── welcome {rev, inMatch} ─ │ (or error + close)
 │ ── queue {snapshotId} ──────────────► │ snapshot must be yours, active, Lv ≥ 5 → Lv50 sync
 │ ◄──────────────────── queued ──────── │
 │        … matchmaking: PvP within the rating band, else a ghost after N s …
 │ ◄──── match {matchId, you, a, b} ──── │
 │ ◄──── snap (2 Hz) / ev (on events) ── │  10 Hz server-authoritative, stackable bars
 │ ── select {seq, slot} ──────────────► │  (any time: kept until its bars are there = さきどり)
 │ ◄──── sel {seq, accepted, queued} ─── │  private ack, the opponent never sees it
 │ ── omakase {on} ────────────────────► │  (rev 2) おまかせ switch: the server plays for the child
 │ ◄──────────────────── omakase {on} ── │  private ack
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
- May be sent **at any time**. The server keeps it (さきどり) and uses it in the very tick the side
  has enough full bars for it and the move is off cooldown; a later `select` replaces it. If the
  bars are already there it is used in the next tick (≤ 100 ms).
- A move whose cost (`MovePublic.bars`) is above the side's `maxBars`, or a slot that does not
  exist, is refused at once (`sel {accepted:false, reason:"unusable"}`). Every move the server
  sends satisfies `bars ≤ maxBars`, so this only happens on a client bug.

### `omakase` (rev 2)
```json
{ "t": "omakase", "on": true }
```
- The child's おまかせ switch (SPEC §6.1). While `on`, the server plays this side with the
  **random-wait rule** (rev 3): it picks one move uniformly at random among the moves that are off
  cooldown and cost at most `maxBars` (the side's AI random stream), waits until enough bars are
  there, uses it, and picks again. Switching it on drops a pending さきどり; `select`s sent while it
  is on are stored and used only after it goes off.
- `on: false` gives the child full control again (さきどり) from the next tick. An idle child is
  never played for: the gauge just stops at `maxBars`.
- Only inside a match (`NOT_IN_MATCH` otherwise). The state lasts for the match, also across a
  reconnect; apps re-send their switch after every `match` anyway. Answered with a private
  `omakase {on}`; the opponent never learns about it (no `autoPick` event for these picks; the
  replay logs them as `src: "omakase"`).
- Send it only when `welcome.rev >= 2`; a rev 1 server answers `error BAD_MESSAGE` (harmless).
  A rev 2 server still runs the 5 s timer and picks with its ふつう AI; a rev 3 app should treat a
  rev < 3 server as outdated (it draws bars only from rev 3 snapshots).

### `ping`
```json
{ "t": "ping" }
```

## 4. Server → client

| `t` | Fields | Meaning |
|---|---|---|
| `welcome` | `proto`, `rev`, `serverTimeMs`, `inMatch` | Handshake accepted. `rev` = revision of v1 (2 = `omakase`, `deadline`, `FighterInfo.snapshotId`; 3 = stackable bars, no timer; absent = 1). `inMatch:true` means a `match` (+ missed events) follows: the child was reconnected to the running match. |
| `queued` | `snapshotId` | In the queue. Show 「あいてを さがしているよ」. |
| `cancelled` | – | Left the queue. |
| `match` | `matchId`, `you` (`"a"`/`"b"`), `tickHz` (10), `a`, `b` (`FighterInfo`), `resumed` | Battle starts (or resumes). (rev 3 removed `decisionTicks`.) |
| `ev` | `seq`, `tick`, `events[]` | Things that happened in one tick, in order. `seq` increases by 1 per message. |
| `snap` | `tick`, `a`, `b` (`SideView`), `hash` | State every 5 ticks (2 Hz) and at the end. Interpolate the gauge between snaps (≈ 280 per tick at equal AGI, up to `maxBars`·10000). |
| `sel` | `seq`, `slot`, `accepted`, `queued`, `reason?` | Private answer to `select`. `queued:true` = kept until its bars are there (さきどり). `accepted:false, reason:"unusable"` = the move can never be used (cost > `maxBars`, or no such slot). |
| `end` | `matchId`, `winner`, `reason`, `you {outcome, xp, badge, badgeUp}` | Final result, already persisted. `reason`: `ko`, `timeout` (3 min, HP ratio), `forfeit` (a side was away 30 s), `aborted` (server restart: no rating/XP change). `xp` is added to the local character by the app. |
| `omakase` | `on` | (rev 2) Private answer to `omakase`: the switch as the server now has it. |
| `pong` | `serverTimeMs` | Answer to `ping`. |
| `error` | `code`, `message?` | See §6. `message` is for logs only; map `code` to a gentle kid message. |
| `bye` | `reason`, `reconnect` | The server is about to close the socket. If `reconnect:true`, reconnect silently (see §7). |

`FighterInfo`:
```json
{
  "snapshotId": "Abc123",               // (rev 2) the registered character (snapshots/{id}): the id for reportCharacter
  "displayName": "げんきな うさぎ",      // preset words (setDisplayName), "" or "かがみ" for a mirror ghost
  "characterName": "ねこまる",
  "imagePath": "snapshotImages/Abc123/image.png",
  "rig": { "...": "puppet rig as saved by the owner (opaque)" },
  "attr": "gu",                          // gu / choki / pa
  "moves": [{ "slot": 0, "name": "ぱんち", "templateId": "strike", "attr": "gu", "bars": 1 }],  // (rev 3) bars = cost in gauge bars
  "maxHp": 944,
  "maxBars": 4,                          // (rev 3) gauge bars this fighter can stack, 2..5
  "level": 50,                           // rated play is always Lv50 (GAME_DESIGN_V2 §8)
  "badge": "rabbit",                     // best badge ever; never goes down
  "isGhost": false
}
```
`snapshotId` is the public Firestore document id of the character (both sides, ghosts too; a mirror
ghost carries the child's own id, which the app must not offer to report: `CANNOT_REPORT_SELF`).
It is random and says nothing about the character; the no-leak tests cover it.

`SideView` (rev 3): `{ "hp", "maxHp", "gauge" (0–maxBars·10000; one bar = 10000, partial fill
included), "bars" (full bars now), "maxBars", "casting" }`.

`maxBars` and the move costs come from the character's Lv1 SP and move strength; they are the
same for every viewer and say nothing hidden (a hidden late bloomer uses its rebuilt form's SP from
Lv1, so its bar count is distributed like a child drawing's and never changes).

Battle events (`ev.events[]`) always have `tick` and `type`, most have `side` (0 = a, 1 = b).
Engine v3 types (docs/BATTLE_V3.md §2, all fields integers unless noted): `bar {bars}` (rev 3: one
more bar became full), `inputIgnored {slot}`, `select {slot, cost, cast}` (`cost` = bars spent),
`moveStart {slot, template, attr}` (strings), `effective {target, pct}`,
`hit {target, n, amount, hp, crit, pct}`, `miss {target, n}`, `dot {target, amount, hp}`,
`heal {amount, hp, source}`, `stage {stat, stage, ticks}`, `status` / `statusFail {target,
status[, ticks]}`, `shield {pct, ticks}`, `expire {kind}`, `heatUp`, `faint`,
`end {winner, reason: ko|timeUp}`. Added by the server: `forfeit`. **Rev 3 removed** `ready`,
`autoPick` and `deadline` (there is no timer). **Ignore unknown types and fields.** (The local dev
stand-in engine sends `bar`, `act {slot, cost}`, `cast`, `hit {dmg, hp, typePct}`, `ko` instead; it
never runs on Cloud Run.)

Badge ids → names: `egg` たまご, `chick` ひよこ, `rabbit` うさぎ, `fox` きつね, `bear` くま,
`lion` ライオン, `dragon` ドラゴン, `legend` でんせつ. The rating number is never sent.

## 5. Timing rules (server-owned)

| Rule | Value | Source |
|---|---|---|
| Tick | 100 ms (10 Hz), integer state | GAME_DESIGN_V2 §6.1 |
| Gauge | 2–5 bars (`maxBars`), each fills by the AGI ratio (≈ 3.6 s at equal AGI); filling stops at `maxBars` and while casting; the opponent never pauses | §6.1–6.2 |
| Decision timeout | **none** (rev 3): an idle child just caps at `maxBars` | SPEC §6.1 |
| おまかせ switch | `omakase {on:true}`: random affordable move, used once its bars are there, then a new pick | SPEC §6.1 |
| さきどり | a queued `select` is used in the tick its bars are there (and it is off cooldown) | §6.3 |
| Ghost / away AI | tiered AI "normal" (`aiDecide`): thinks 10 ticks once it holds a bar, saves at most one bar ahead | §6.6 |
| Disconnect | after 10 s away the AI ("normal") plays for the child; back within 30 s = full control again; 30 s away = loss, XP 0 (rating counts as a loss) | §6.7 |
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
| `NOT_FOUND` / `NOT_OWNER` | snapshot missing, not active, someone else's, or a v1 snapshot (not `schema: 2`) | 「もういちど とうろく してね」 |
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

## 9. Engine swap (Engine team → GCP team) — **done** (Server team, v2.0)

The server is written against `server/realtime/src/engine.ts`, a narrow interface. It now runs
**Engine v3** (`shared/battle_engine_v3_ts`, bit-exact with the app's Dart engine and
`shared/battle_spec_v3/`) through `src/engines/v3Engine.ts`. The simplified stand-in
`src/engines/devEngine.ts` (`BATTLE_ENGINE=dev`, **not** the game rules) is only for local
development: the server refuses it with `NODE_ENV=production` (always set on Cloud Run) and
Terraform only accepts `v3`.

What was done (all four steps):
1. ✅ `server/realtime/package.json` depends on `"@doodle-battle/battle-engine-v3":
   "file:../../shared/battle_engine_v3_ts"`. Install / build it first
   (`cd shared/battle_engine_v3_ts && npm ci`, its `prepare` compiles `dist/`). The Dockerfile
   does the same, then replaces the npm link by a copy of the compiled engine so the runtime image
   is self-contained; `Dockerfile.dockerignore` allows the engine's package files and `src/`. CI
   (`realtime-ci.yml`, `realtime-deploy.yml`) builds the engine first and its path filters include
   `shared/battle_engine_v3_ts/**` and `shared/battle_spec_v3/**`.
2. ✅ `src/engines/v3Engine.ts` (`V3Engine`, engine id `v3.0`):
   - `ratedFighter(source, 50)` → `ratedFighterFromSnapshot(doc.engine, doc.level)`: v3
     `ratedSetup` at the real level (own growth, Lv50 stat sync, moves unlocked at the real level:
     2 / 3 at Lv10 / 4 at Lv50). Only `schema: 2` snapshots (written by the v2 `registerCharacter`)
     are accepted; anything else → `UnsupportedFighterError` → `NOT_FOUND`.
   - `createBattle(a, b, {seed})` → `RealtimeBattle` (engine id `v3.1` since rev 3; no timer).
   - `step`, `canUse`, `canQueue`, `aiInput(side, tier, think)` and `omakaseInput(side)` (side's AI
     stream only), `clearPlan`, `view`, `stateHash()` (FNV-1a of the canonical state, 8 hex digits)
     are pass-throughs.
   - **Hidden state**: `snapshot.engine.trust` and the late-bloomer form are engine input only.
     Clients get `attr`, the public move fields (`slot, name, templateId, attr, bars`), `maxHp`,
     `maxBars`,
     engine events and side views — none of them names the verdict or the form. Tested in
     `test/unit/v3Engine.test.ts` and over real WebSockets in `test/integration/v3.test.ts` (every
     message of PvP and ghost matches with hidden-form characters is checked for any trace of it).
3. ✅ `loadEngine("v3")` returns `V3Engine`. `test/unit/v3Engine.test.ts` replays all `battles` of
   `shared/battle_spec_v3/golden_vectors.json` through the adapter (`expected.inputLog` inputs at
   their ticks) and compares winner, end reason, tick, HP, max HP, event count, **event hash** (or
   the full event list, minus a さきどり the engine dropped as impossible, which the server refuses
   at `select`) and state hash; it also checks `ratedSetups` from v2 snapshot data. Replays of stored matches
   (`replays/{id}` = seed + inputs) reproduce `finalHash`.
4. ✅ Terraform: dev `realtime_battle_engine = "v3"` (prod already was). Deploy: see
   `docs/LEARN_GCP.md` §4.9.

## 10. Versioning

`proto` is bumped only for breaking changes. Additive changes (new optional fields, new event
types, new error codes, new client messages) keep `proto: 1` and raise `welcome.rev`; clients
must ignore unknown fields and event types, and only send new client messages when `rev` is
high enough.

| rev | Added |
|---|---|
| 1 | the original v1 (`welcome` has no `rev`) |
| 2 | `FighterInfo.snapshotId`, client `omakase {on}` + private ack, `deadline {side, at}` event, `welcome.rev` |
| 3 | Stackable gauge bars (2026-10-15): `FighterInfo.maxBars`, `MovePublic.bars` (replaces `spCost`), `SideView.bars` / `maxBars` (replace `sp` / `ready`; `gauge` now 0–maxBars·10000), `bar` event, `select.cost`. **No decision timer**: `deadline`, `autoPick`, `ready` and `match.decisionTicks` are gone; おまかせ uses the random-wait rule. Not purely additive (a rev 2 app would draw one gauge and wait for a timeout that never comes), so ship the app and the server together |
