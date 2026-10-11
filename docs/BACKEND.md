# おえかきファイターズ Backend (Firebase)

Owner: Backend team (`feat/backend`). Source of truth for product rules is `docs/SPEC.md`; this
document describes how the backend implements SPEC §3.3, §5 and the server side of §7.

## 1. Principles

- **No free text between users.** Nothing a child types is ever shown to another child unless it
  passed the NG dictionary *and* an AI review (character names, move names). Display names are
  chosen from preset word ids. There is no chat.
- **Fail closed.** If moderation cannot run (AI down, bad output), nothing is published.
  `judgeDrawing` failures are harmless: the app continues with the on-device judgement.
- **Server authoritative.** Clients never write snapshots, queue entries, matches or results.
  Battles are resolved by Cloud Functions with the battle engine; clients only read match docs.
- **Minimal data.** `judgeDrawing` never stores the image. Logs never contain images or rejected
  text. Everything about a user can be deleted with `deleteMyData`.
- **Parent consent is enforced server-side** on every function that needs it.

## 2. Architecture

```
 Flutter app ──(callable + App Check / Play Integrity, Anonymous Auth)──► Cloud Functions v2 (asia-northeast1)
     │                                                                    │   judgeDrawing ───────► Claude (vision, structured JSON)
     │ reads own docs / match docs (rules)                                │   registerCharacter ──► Claude moderation → Storage + Firestore
     ▼                                                                    │   setDisplayName, joinQueue, leaveQueue
 Firestore ◄──────────────────────────────────────────────────────────────┤   submitAction, pollMatch ─► battle engine adapter
 Storage (snapshot images, read-only for clients)                         │   reportCharacter, deleteMyData
                                                                          │   sweepMatches (Cloud Scheduler, every minute)
                                                                          └── onUserConsentChanged (Firestore trigger)
```

**v2.0 additions (GCP team, `docs/LEARN_GCP.md`)**: online rated battles move to a Cloud Run
WebSocket server (`server/realtime/`, protocol in `docs/REALTIME_PROTOCOL.md`); the v1 callable
battle (`joinQueue`/`submitAction`/`pollMatch`) stays for v1.x clients. A budget → Pub/Sub →
`onBudgetAlert` kill switch maintains `config/costMode` (§16). All infrastructure except rules,
indexes and functions is Terraform (`infra/terraform/`).

```
 app ──wss /v2 (ID token + App Check in hello)──► Cloud Run "battle" (asia-northeast1, 0–1 instance)
                                                    └─ Admin SDK ─► users.rated, snapshots.ghostRating, rtMatches, replays
 Cloud Billing budget ─► Pub/Sub budget-alerts ─► onBudgetAlert ─► config/costMode ◄─ functions, battle server, app read
```

Code layout (`firebase/`):

| Path | What |
|---|---|
| `firebase.json`, `.firebaserc` | Emulator ports, rules/indexes, functions codebase. Default project id is the placeholder `doodle-battle-dev`. |
| `firestore.rules`, `storage.rules`, `firestore.indexes.json` | Security rules (deny by default) and composite indexes. |
| `functions/src/config.ts` | Region, `ANTHROPIC_API_KEY` secret, `CLAUDE_MODEL` param, all tunables (`LIMITS`, `RATE_LIMITS`). |
| `functions/src/callables/*` | One file per callable (handler is exported separately for tests). |
| `functions/src/ai/*` | Claude service (official `@anthropic-ai/sdk`), prompts, output schemas. |
| `functions/src/ngwords/*` | Normaliser + NG filter (data in `shared/ng_words/`). |
| `functions/src/battle/*` | Engine adapter + stub, ghost AI, match service, matchmaking, results. |
| `functions/src/cost/*` | Cost mode reader (`costMode.ts`), AI cost gate + usage meter (`aiUsage.ts`), kill switch `onBudgetAlert` (`budgetAlert.ts`). §16. |
| `functions/src/stats/statLimits.ts` | SPEC §3.2/§4.2 budget, growth and anti-tamper validation. |
| `functions/src/names/*` | Display names (words in `shared/names/`), preset character names, name validation. |
| `functions/scripts/sync-shared.mjs` | Copies `shared/ng_words`, `shared/battle_spec`, `shared/battle_engine_ts/src` into `functions/src/vendor/` (git-ignored) before build/lint/test, because Cloud Functions only uploads `functions/`. |

## 3. Consent model

The app writes consent behind the parent gate (SPEC §7) to its own profile doc. Firestore rules
only let the signed-in user write exactly these fields:

```jsonc
// users/{uid} (client-writable part)
{
  "consent": { "cloudJudge": false, "online": false, "policyVersion": 1 },
  "consentUpdatedAt": <request.time>,   // must equal request.time
  "createdAt": <request.time>          // create only
}
```

| Function | Requires |
|---|---|
| `judgeDrawing` | `consent.cloudJudge == true` |
| `registerCharacter`, `setDisplayName`, `joinQueue`, `submitAction`, `reportCharacter` | `consent.online == true` |
| `leaveQueue`, `pollMatch`, `deleteMyData` | sign-in only (must always work) |

When `consent.online` flips from true to false, `onUserConsentChanged` immediately marks the
child's snapshots `withdrawn` (unmatchable, images unreadable) and removes the queue entry.
`policyVersion` lets the app force re-consent when the privacy policy changes. The server cannot
verify that a parent (rather than the child) flipped the switch; that is what the parent gate is
for.

## 4. Data model

All timestamps are epoch milliseconds (`*Ms`) so that they are easy to compare on the client and
can be faked in tests.

| Collection | Written by | Client read | Notes |
|---|---|---|---|
| `users/{uid}` | client (consent only) + functions | own doc | `displayName {adjectiveId, nounId, text}`, `rating` (Elo, start 1000), `onlineStats {wins, losses, draws}`, `activeMatchId` |
| `snapshots/{id}` | functions | owner only | Immutable registered character: `ownerUid, localCharacterId, status, name, moveNames{element,special}, ownerDisplayName, element, baseStats, stats (effective at level), energy, skill, isShobo, level, xp, seedAllocations, evolution, subject, features, imagePath, imageSha256, moderation{aiSkillEstimate, suspectSkill, ngWordsVersion}, reportCount, reportReasons, randomKey, createdAtMs`. `status`: `active` / `hidden` (reports) / `removed` (ops) / `superseded` (re-registered) / `withdrawn` (consent revoked). Only moderation counters and `status` ever change. |
| `queue/{uid}` | functions | own doc | `{uid, snapshotId, level, status: waiting|matched, matchId, joinedAtMs, lastSeenMs}` |
| `matches/{id}` | functions | players (`playerUids`) | `mode: pvp|ghost, playerUids, snapshotIds, sides{a,b}: SideInfo, engineId, seed, turn, state, view{turn, finished, winner, a{hp,maxHp,gauge}, b{…}}, submitted{a,b}, turnDeadlineMs, timeouts{a,b}, status: active|finished|aborted, winner: a|b|draw|null, endReason: ko|turn_limit|forfeit_timeout|aborted, result{a,b}: {xp, ratingDelta, outcome}` |
| `matches/{id}/turns/{n}` | functions | players | `{turn, actions{a,b}, timedOut{a,b}, events[], view, resolvedAtMs}` (the battle log to animate) |
| `matches/{id}/private/actions` | functions | **nobody** | Pending actions of the current turn (kept hidden so the opponent cannot react to them). |
| `reports/{snapshotId}__{reporterUid}` | functions | – | One per reporter and snapshot. |
| `moderationQueue/{snapshotId}` | functions / ops | – | `{snapshotId, ownerUid, reportCount, reasons{}, hidden, state: pending, createdAtMs, updatedAtMs}` |
| `moderationLog/{auto}` | functions | – | `{uid, kind, reason, atMs}` for rejected registrations (no image, no text). |
| `aiSuggestionReports/{auto}` | functions | – | `{uid, kind, text, reasonCode, state, atMs}`: reports of AI-suggested names / move names (`reportAiSuggestion`). |
| `rateLimits/{uid}` | functions | – | Fixed-window counters. |
| `rtMatches/{matchId}` | battle server | players (`playerUids`) | v2 realtime match summary: `mode, playerUids, snapshotIds, sides{a,b}: {snapshotId, isGhost, outcome, xp}, winner, reason: ko|timeout|forfeit|aborted, ticks, engineId, startedAtMs, endedAtMs`. No rating numbers. |
| `replays/{matchId}` | battle server | – | `seed, engineId, sides, inputs[{tick, side, slot, src}], finalHash, winner, reason, ratingDeltas, expireAt` — deleted by a Firestore **TTL** policy 30 days after the match (`firestore.indexes.json`). |
| `config/costMode` | kill switch / owner | any signed-in user | `{mode: normal|saving|minimal, flags{cloudJudge, cloudMoveGen, pvp, ghostAfterSec}, updatedAtMs, source, pinned}` (§16). |
| `ops/costStatus`, `ops/aiUsage_YYYYMM` | functions | – | Last budget message and decision; monthly AI call counts and yen estimate (§16). |

v2 fields added by the battle server: `users/{uid}.rated = {rating, games, best, dayKey, dayMatches}`
(Elo per GAME_DESIGN_V2 §8, separate from the v1 `rating`), `snapshots/{id}.ghostRating` (owner's
rating after their last rated match with it; used to pick ghosts near a child's rating). The v2
`registerCharacter` (Engine team) must keep `ownerUid, status, level, name, imagePath,
ownerDisplayName, randomKey` on snapshots; everything else is passed to the engine as-is.

`SideInfo` (what a player sees about the opponent): `uid (null for ghosts), isGhost, snapshotId,
displayName, characterName, element, level, isShobo, evolution, stats, imagePath, moveNames,
rating`. Ghost owners' uids are never exposed.

Storage: `snapshotImages/{snapshotId}/image.png` (written by `registerCharacter`). Readable by any
signed-in user while the snapshot is `active`, and always by its owner; never writable by clients.

## 5. Function contracts

All are **callable** functions (`firebase_functions` `httpsCallable`), region `asia-northeast1`,
**App Check enforced**. Errors are `HttpsError` with `details.code` from §6.

### `judgeDrawing` (SPEC §3.3)

```jsonc
// request
{ "imageBase64": "<PNG, cut-out, ≤512×512 px, ≤600 KB decoded, raw base64 without data: prefix>" }
// response
{
  "subject": "ねこ",
  "suggestedNames": ["にゃんた", "みけまる", "ねこりん"],    // always 3, kana only, 2–8 chars, NG-filtered
  "moveNames": { "element": "ほのおぱんち", "special": "にゃんにゃんびーむ" }, // kana, ≤10 chars
  "skillEstimate": 22,                                     // integer 0–100
  "appropriate": true,
  "reasons": [],   // when !appropriate: subset of violence|sexual|hate|copyright|real_person|personal_info|not_drawing|ai_generated|other
  "rejectCode": null // "IMAGE_AI_GENERATED" | "IMAGE_NOT_DRAWING" | null (SPEC §11.1, see below)
}
```
- **Origin check (SPEC §11.1, docs/TRUST.md §4).** The model also returns
  `origin: hand_drawn | unsure | ai_generated | photo_print_or_screen`. Only the two confident
  values reject: `ai_generated` → `rejectCode: "IMAGE_AI_GENERATED"` (+ reason `ai_generated`),
  `photo_print_or_screen` → `"IMAGE_NOT_DRAWING"` (+ `not_drawing`); both set `appropriate:
  false`. `unsure` never rejects. The prompt tells the model that the picture is a cut-out
  (background removed, colours normalised — not a sign of a digital image) and that wrongly
  refusing a real child's drawing is the worst mistake. The app shows 「かみに かいた えを とってね」
  and offers a retake; any other `appropriate: false` is still ignored silently.
- The image is only held in memory; nothing is written except the rate-limit counter.
- AI output is sanitised: anything that is not kana, too long, or hits the NG filter is replaced
  with presets/defaults; skill is clamped. If the model refuses, the response is
  `appropriate: false, reasons: ["other"], skillEstimate: 50, rejectCode: null` with preset names.
- Errors: `UNAUTHENTICATED, CONSENT_REQUIRED, INVALID_ARGUMENT, IMAGE_INVALID, IMAGE_TOO_LARGE,
  RATE_LIMITED (30/h, 100/day), AI_UNAVAILABLE` → app continues with device-only judging.

### `registerCharacter` (SPEC §5)

```jsonc
// request
{
  "localCharacterId": "c_123",                // [A-Za-z0-9_-]{1,64}; re-registering supersedes the old snapshot
  "imageBase64": "<PNG as above>",
  "name": "ねこまる",
  "element": "fire",                          // fire|water|leaf|thunder|shadow|rainbow
  "baseStats": { "hp": 90, "atk": 80, "def": 65, "spd": 65 },   // Lv1 stats (integers)
  "energy": 50, "skill": 20,                  // 0–100 (final skill incl. cloud blend)
  "level": 6, "xp": 10,
  "seedAllocations": { "atk": 3 },            // パワーのたね per stat
  "features": { "inkCoverage": 0.3 },         // optional, ≤40 numeric entries (stored for review)
  "subject": "ねこ",                          // optional
  "moveNames": { "element": "ほのおぱんち", "special": "にゃんびーむ" } // optional
}
// response (accepted)
{ "ok": true, "snapshotId": "Ab12…", "name": "ねこまる",
  "moveNames": { "element": "ほのおぱんち", "special": null },   // flagged move names are dropped (null)
  "displayName": "あおい ドラゴン" }
// response (rejected; nothing stored)
{ "ok": false, "reason": "NAME_NG", "presetNames": ["もこたん", "ぴかりん", "ぷにまる"] } // presetNames only for NAME_*
```
Pipeline (cheap checks first, AI last, fail-closed):
1. consent, input schema, PNG checks, rate limit (10/h, 30/day)
2. `level ≥ 5` → else `LEVEL_TOO_LOW`
3. stat plausibility → `STATS_INVALID` (see §8)
4. name: NFKC, 1–10 chars of hiragana/katakana/ー/・/latin/digits/kanji, ≤2 digits → `NAME_INVALID`;
   NG dictionary → `NAME_NG` / `NAME_PERSONAL_INFO`
5. ≤ 40 active snapshots per user (other local characters) → `TOO_MANY_CHARACTERS`
6. Claude moderation of image + names → `IMAGE_*` / `NAME_*`; a confident `origin` of
   `ai_generated` → `IMAGE_AI_GENERATED`, `photo_print_or_screen` → `IMAGE_NOT_DRAWING`
   (checked after `imageCategory`, before `isHandDrawn`)
7. Storage upload + Firestore transaction (supersede previous snapshot of the same `localCharacterId`).

The server recomputes `stats` (effective at level), `isShobo`, `evolution`; it never trusts client
values for those. The app should store `snapshotId` as `Character.onlineId`.

### `setDisplayName`

```jsonc
{ "adjectiveId": "a01", "nounId": "n02" }  // both or neither (neither = random)
→ { "displayName": { "adjectiveId": "a01", "nounId": "n02", "text": "あおい ネコ" } }
```
Ids come from `shared/names/display_name_words.json` (30 × 30 words), vendored into
`functions/src/vendor/names/` by `scripts/sync-shared.mjs`; the app bundles a byte-identical copy
for its picker (drift test in the app). Never reuse or renumber ids. A random name is assigned automatically at the first registration.

### `joinQueue` / `leaveQueue`

```jsonc
joinQueue  { "characterId": "<snapshotId>" }
leaveQueue {}
→ { "status": "waiting", "waitedMs": 12000 } | { "status": "matched", "matchId": "…" } | { "status": "left" }
```
- `joinQueue` is idempotent and doubles as the **heartbeat**: call it every ~10 s while waiting.
  Each call retries PvP pairing (oldest waiting player within level ±3 whose heartbeat is < 45 s
  old). Once the player has waited ≥ 60 s it starts a **ghost** match instead (random active
  snapshot of another player, preferring level ±3, driven by the server AI). If a match is already
  active it is returned.
- Errors: `CONSENT_REQUIRED, NOT_FOUND, NOT_OWNER, SNAPSHOT_NOT_ACTIVE, INVALID_ARGUMENT`.
- The app can also listen to `queue/{uid}` for `status: "matched"`.

### `submitAction` / `pollMatch`

```jsonc
submitAction { "matchId": "…", "turn": 3, "action": "tackle" }  // tackle|element|guard|special
→ { "resolved": true, "status": "active", "turn": 4 }

pollMatch { "matchId": "…" }
→ { "status": "active", "turn": 4, "turnDeadlineMs": 1800000020000 }
```
- One action per side per turn (retries are idempotent). The first action is stored in
  `matches/{id}/private/actions`, invisible to clients; the match doc only shows
  `submitted: {a: true, b: false}`. When both actions are in (immediately for ghost matches), the
  turn is resolved in the same transaction: new `state`/`view`, `turns/{n}` log, next deadline.
- Errors: `NOT_FOUND, NOT_IN_MATCH, MATCH_NOT_ACTIVE, WRONG_TURN, ILLEGAL_ACTION
  (e.g. special without a full gauge), INVALID_ARGUMENT`.
- End of match: `status: finished|aborted`, `winner`, `endReason`, `result[side] = {xp,
  ratingDelta, outcome}`. Rating and `onlineStats` are updated server-side; **the app applies
  `result[mySide].xp` to its local character** (dedupe by matchId), because levels live on device.

Client loop: listen `matches/{id}` → when `turn` increases read `turns/{turn-1}` and animate →
choose action → `submitAction`. Run a local 20 s timer; when it expires (and every ~5 s while
waiting for the opponent) call `pollMatch`.

### `reportCharacter`

```jsonc
{ "snapshotId": "…", "reasonCode": "bad_picture" }
// reasonCode: bad_picture | bad_name | real_person | personal_info | copied_character | other
→ { "ok": true, "alreadyReported": false }
```
Only characters met in the reporter's last 50 matches can be reported (`NOT_SEEN_IN_MATCH`), not
your own (`CANNOT_REPORT_SELF`), 20/day. One report per reporter and snapshot. After **3 distinct
reporters** the snapshot becomes `hidden` (unmatchable, image unreadable); every reported snapshot
gets a `moderationQueue` entry for a human.

### `reportAiSuggestion` (Google Play AI-generated content policy)

```jsonc
{ "kind": "name", "text": "にゃんた", "reasonCode": "mean" }
// kind: name | element_move | special_move | subject; text: kana (+ー/space), 1–12 chars
// reasonCode: mean | scary | strange | other   (preset, no free text)
→ { "ok": true }
```
A child flags a name / move name the AI suggested (naming screen 「いやな ことばを おしえる」).
Requires `consent.cloudJudge` (suggestions only exist with it), 20/day. Stored in
`aiSuggestionReports/{auto}` = `{uid, kind, text, reasonCode, state: "pending", atMs}` for human
review; never shown to anyone; deleted by `deleteMyData`. The app logs every report locally first
(`ai_reports.json`) and sends unsent ones when online and consented. Errors: `UNAUTHENTICATED,
CONSENT_REQUIRED, INVALID_ARGUMENT, RATE_LIMITED`.

### `deleteMyData`

```jsonc
{ "confirm": "DELETE" }  → { "ok": true, "deleted": { "snapshots": 1, "matches": 2, "reports": 2 } }
```
Deletes the profile, all snapshots + images, every match the user played or appeared in as a
ghost (with turn logs), v2 `rtMatches` + `replays` the user played or appeared in (`matches`
counts both), reports by and about the user, queue/rate-limit/moderation-log records, and
finally the Firebase Auth user. The app must call it behind the parent gate, then sign out and
wipe local data. Errors: `CONFIRMATION_REQUIRED, UNAUTHENTICATED, INTERNAL` (auth deletion failed
after data deletion; safe to retry).

### Background

- `sweepMatches` (Cloud Scheduler, every minute, Asia/Tokyo): removes queue entries whose
  heartbeat stopped (45 s), starts ghost matches for waits ≥ 60 s, resolves expired turns.
- `onUserConsentChanged` (Firestore `users/{uid}` update): consent withdrawal handling (§3).
- `onBudgetAlert` (Pub/Sub topic `budget-alerts`, runs as `cost-guard@`): the kill switch (§16).

## 6. Codes

**`HttpsError.details.code`**

| Code | HTTPS status | Meaning / app behaviour |
|---|---|---|
| `UNAUTHENTICATED` | unauthenticated | sign in anonymously first |
| `CONSENT_REQUIRED` | permission-denied | parent has not allowed this feature |
| `INVALID_ARGUMENT` | invalid-argument | malformed request (app bug) |
| `IMAGE_INVALID` | invalid-argument | not a PNG / too small |
| `IMAGE_TOO_LARGE` | invalid-argument | > 512 px or > 600 KB |
| `RATE_LIMITED` | resource-exhausted | try later |
| `AI_UNAVAILABLE` | unavailable | judge: continue on device; register: try later |
| `NOT_FOUND` | not-found | unknown character/match |
| `NOT_OWNER` | permission-denied | not your character |
| `SNAPSHOT_NOT_ACTIVE` | failed-precondition | character hidden/withdrawn/superseded → register again |
| `NOT_IN_MATCH` | permission-denied | |
| `MATCH_NOT_ACTIVE` | failed-precondition | match ended (or engine upgraded mid-match) |
| `WRONG_TURN` | failed-precondition | turn already resolved (e.g. timed out) → refresh |
| `ILLEGAL_ACTION` | invalid-argument | e.g. ひっさつ without full gauge |
| `CANNOT_REPORT_SELF` | invalid-argument | |
| `NOT_SEEN_IN_MATCH` | permission-denied | |
| `CONFIRMATION_REQUIRED` | invalid-argument | `deleteMyData` without `{confirm:"DELETE"}` |
| `NO_OPPONENT` | unavailable | reserved |
| `INTERNAL` | internal | |

**`registerCharacter` rejection reasons** (`{ok:false, reason}`; the app maps them to kind
messages, e.g. `IMAGE_REAL_PERSON` → 「ひとの しゃしんや かおは つかえないよ」):
`LEVEL_TOO_LOW, STATS_INVALID, NAME_INVALID, NAME_NG, NAME_PERSONAL_INFO, IMAGE_VIOLENCE,
IMAGE_SEXUAL, IMAGE_HATE, IMAGE_COPYRIGHT, IMAGE_REAL_PERSON, IMAGE_PERSONAL_INFO,
IMAGE_NOT_DRAWING, IMAGE_AI_GENERATED, IMAGE_OTHER, TOO_MANY_CHARACTERS` (`IMAGE_AI_GENERATED` and
`IMAGE_NOT_DRAWING` both map to 「かみに かいた えを とってね」).

## 7. Battles, ghosts and timeouts

- **Engine adapter** (`functions/src/battle/engine.ts`): `BattleEngine { id, init(a, b, seed),
  legalActions(state, side), resolveTurn(state, actionA, actionB, timedOut?) → {state, events},
  view(state) }`, implemented by `SharedEngine`, which delegates to the shared TypeScript engine
  (`shared/battle_engine_ts`, the same rules as the app; see docs/BATTLE.md). Id
  `shared-<specVersion>`. States/events are plain JSON stored in Firestore:
  `{engine, seed, turn, rngState, inner}` where `inner` is the shared `BattleState`.
  **Randomness**: the shared mulberry32 state lives *in* the engine state (`rngState`, initialised
  to `deriveSeed(seed, 0)`) and is advanced by each resolved turn inside the same transaction, so a
  turn needs only the stored state and a whole match replays from its seed + action log. (This
  replaces the earlier per-turn `turnSeed` design so that the shared golden vectors replay through
  the adapter unchanged — `test/unit/engine.test.ts`.) Timed-out players are passed to the engine
  as `timeout` (it plays たいあたり and logs a `timeout` event).
  Every match records `engineId`; if a deploy changes the engine (spec version), running matches
  are aborted rather than resolved with different rules.
- **Turn limit / end**: 20 s per turn (+3 s server grace). Missing actions become たいあたり.
  3 consecutive timeouts by a human → forfeit (`forfeit_timeout`); both players gone → `aborted`
  (no XP/rating). Turn 30 without KO → the shared engine picks the winner by remaining HP ratio
  (`turn_limit`); an exact tie is broken by its rng, so there are no draws.
- **Results**: XP from the shared `xpForBattle` (win 100 / lose 40, しょぼキャラ ×1.5, SPEC §4.2),
  identical to the app. A legacy `draw` outcome earns the losing XP. Elo per user,
  K = 32 (PvP), 16 (ghost; the ghost's rating mirrors the player's). Ghost owners are unaffected.
- **Ghost AI** ("ふつう"): the shared `chooseCpuAction(…, "normal")` — special when ready, element
  move unless type-disadvantaged, occasional guard; its own rng from `turnSeed(seed, turn,
  "ghost-<side>")`, so it is deterministic and never shifts battle rolls.

**Timeout design choice — lazy enforcement + 1-minute sweep (no Cloud Tasks).** Every
`submitAction` and `pollMatch` first checks the current deadline and, if it has passed, resolves
the turn in a transaction. The app calls `pollMatch` when its 20 s timer expires, so the absent
player's turn resolves ~20–23 s after it started — the precision SPEC asks for — with no extra
infrastructure. `sweepMatches` (Cloud Scheduler, 1/min) is the backstop when *both* clients are
gone. Cloud Tasks would give exact per-turn timers even with no client online, but needs a queue,
IAM for the task invoker, an enqueue (and usually a cancel) per turn, and adds latency/cost on the
hot path; since a turn only matters while at least one player is watching, client-driven
enforcement is simpler and cheaper. Switching later only requires calling `enforceDeadline` from a
task handler.

### Shared battle engine wiring (done, Battle team round 2)

`npm run build` / `lint` / `test` first run `scripts/sync-shared.mjs`, which copies
`shared/battle_engine_ts/src/` → `src/vendor/battle_engine/` and `shared/battle_spec/*.json` →
`src/vendor/battle_spec/` (git-ignored). `getEngine()` returns `SharedEngine`; the stub engine was
removed. A unit test replays every battle vector of `shared/battle_spec/golden_vectors.json`
through the adapter and checks that the vendored JSON equals the spec embedded in the engine.

## 8. Stat validation (anti-tamper)

`validateStatClaim` (pure, unit-tested) checks: energy/skill in 0–100; level 1–30; `0 ≤ xp <
50 + 25·L` (any xp at Lv30); base stats are non-negative integers; `Σ base ≤ ceil(budget) + 4` with
`budget = (200 + 2·energy) · skillMultiplier(skill)` (SPEC §3.2, so しょぼキャラ get 0.35×); each
stat ≤ `ceil(0.7 · budget) + 1`; `Σ seeds ≤ L − 1`. The server then computes effective stats with the shared
`statsAtLevel` (`floor(base · (100 + g·(L−1) + 3·seeds) / 100)`, g = 4, or 12 for しょぼキャラ) and
checks them against the shared `maxStatsAtLevel` caps (`statCapsAtLevel`). If the AI's `skillEstimate` exceeds the claimed
skill by ≥ 50, the snapshot is accepted but flagged `moderation.suspectSkill` for review (likely an
adult/traced drawing claiming a child's "のびのび" budget).

## 9. AI (Claude)

- Official SDK `@anthropic-ai/sdk`, `messages.parse` with **structured outputs**
  (`output_config.format` from zod schemas) so the response is always the expected JSON shape.
  Effort `low` for judging, `medium` for moderation; no sampling parameters; adaptive thinking is
  left at the model default. `max_tokens` 4096, client timeout 25 s, 1 retry.
- **Model**: read from the Firebase param `CLAUDE_MODEL`; set it to the **latest low-cost
  Haiku-class model** (it must support vision, structured outputs and `effort`). No model id is
  hard-coded anywhere in the repo. The API key is the Secret Manager secret `ANTHROPIC_API_KEY`,
  only mounted into `judgeDrawing` and `registerCharacter`.
- **Prompt-injection hardening**: the system prompt states that the drawing and any writing in it,
  and the candidate names, are untrusted data that must never be followed or copied; names are
  sent as an escaped JSON array inside `<candidate_names>` tags; the output is schema-constrained
  (enums for categories); and every field is re-validated server-side (kana-only, length, NG
  filter, clamping). Writing in the picture that tries to manipulate the reviewer is itself a
  rejection reason (`IMAGE_OTHER`).
- Refusals (`stop_reason: "refusal"`) are treated as "inappropriate" (judge) / `IMAGE_OTHER`
  (register). API errors, truncation and unparsable output → `AI_UNAVAILABLE`.
- Images are sent base64 in the request and never persisted by `judgeDrawing`. Note for the
  privacy policy: drawings are processed by Anthropic as a sub-processor when the parent enables
  cloud judging / online play.

## 10. NG words and the shared normaliser

- `shared/ng_words/ng_words.json`: categories `slur, sexual, violence, insult, personal_info`,
  each with `ja`/`en` lists of `substring` and `exact` entries (exact for short words that would
  cause false positives, e.g. `kill` vs `skill`), regex `patterns` for personal info (6+ digit
  runs incl. kanji numerals and full-width digits, URLs, domains, e-mail, @handles, 〒) and an
  `allowExact` override list.
- `shared/ng_words/normalize_vectors.json`: the normaliser **specification** (`algorithm`) and
  golden vectors. `normalizeForMatch`: NFKC → lower-case → katakana→hiragana → small kana → leet
  (only inside ASCII runs that contain a letter) → strip everything but a-z/0-9/hiragana/kanji →
  collapse repeats. `normalizeForPatterns`: NFKC → lower-case → kanji numerals → strip separators.
- `shared/ng_words/ng_check_vectors.json`: expected blocked/clean results for the whole filter.
- The Flutter offline filter must pass both vector files (Dart has no built-in NFKC; use a
  normalisation package such as `unorm_dart`). The dictionary is only the cheap first layer; the
  server always adds the AI review before anything is shown online.

## 11. Security rules

Deny by default. Clients can create/update only their own `users/{uid}` consent fields
(validated types, `request.time` timestamps), read their own profile/queue/snapshots, and read
matches + turn logs they play in, v2 `rtMatches` they play in, and `config/costMode` (any
signed-in user). Pending actions, reports, moderation data, rate limits, `replays` and `ops` are
unreadable. Storage: no client writes; snapshot images readable only while the snapshot is
`active` (cross-service `firestore.get`) or by the owner. Tested with
`@firebase/rules-unit-testing` (`test/emulator/rules.*.test.ts`).

## 12. Development and tests

```bash
cd firebase/functions
npm ci
npm run lint        # tsc --noEmit (src + tests) + eslint (strict type-checked)
npm run build       # syncs shared/ assets, compiles to lib/
npm test            # unit tests, then emulator tests (Auth/Firestore/Storage emulators, Java 21)
npm run test:unit   # pure tests only (no Java needed)
```

- Unit (`test/unit`, 209 tests): normaliser + NG vectors, names, stat limits, PNG checks, shared engine adapter + golden vectors,
  ghost AI, results, Claude service request shape / error mapping with a mocked SDK client.
- Emulator (`test/emulator`, 69 tests): every callable handler against real emulators with a
  mocked AI service (`setAiServiceForTesting`) and an injectable clock (ghost wait, turn
  timeouts), the sweep, consent trigger, deletion, and Firestore/Storage rules. Tests use the
  `demo-doodle-battle` project id, so they can never touch a real project.
- Cost mode (§16): unit tests for the kill-switch decision and flags; emulator tests for
  `onBudgetAlert` (mode changes, AI estimate, owner pin), the judge gate + usage meter, moderation
  staying on, v1 matchmaking per mode, rules for `config/costMode` and `rtMatches`.
- No test calls the Claude API.
- Realtime server: `cd server/realtime && npm test` (unit + two WebSocket clients playing full
  matches, offline) and `npm run test:firestore` (Firestore emulator). See its README.
- Note: if your shell sets `HTTPS_PROXY`, unset it for `npm test` (the Storage emulator's
  cross-service rule lookups to the Firestore emulator are otherwise sent to the proxy and the
  storage-rules tests fail): `env -u HTTPS_PROXY -u https_proxy npm test`.
- Local app development: `npm run emulators` (runs functions too). Put `CLAUDE_MODEL=…` in
  `functions/.env.local` and `ANTHROPIC_API_KEY=…` in `functions/.secret.local` (both
  git-ignored), and use the App Check debug provider in the app.

## 13. Cost estimate (per 1,000 DAU)

> v2.0: the full monthly estimate including the Cloud Run battle server and the ¥5,000 budget is
> in `docs/LEARN_GCP.md` §12 (≈ ¥1,600–3,200 GCP + ≈ ¥1,500 AI at 1k DAU). The v1 table below
> is kept for the callable battle.

Assumptions per daily user: 2 `judgeDrawing`, 0.2 registrations, 3 online matches (≈12 turns,
half PvP), ~30 s average queue wait. Prices are list prices at the time of writing and must be
re-checked; Firestore numbers use ≈ $0.06/100k reads and $0.18/100k writes.

| Item | Volume / day | ≈ $/day |
|---|---|---|
| Claude judge (~1.3k input incl. image ≈ 350 tokens, ~0.45k output) | 2,000 calls | 0.72 at $0.10/$0.50 per MTok · 7.2 at $1/$5 |
| Claude moderation (~1.5k in, ~0.8k out) | 200 calls | 0.11 · 1.1 |
| Firestore (≈ 70 reads + 35 writes per match per player incl. listeners, heartbeats, rate limits) | ~420k reads, ~210k writes | ≈ 0.65 |
| Cloud Functions (~55 invocations/user, 256 MiB, ~0.2 s) | ~55k | ≈ 0 (free tier) |
| Storage + egress (≈100 KB image per registration; ~3 opponent images per user) | 20 MB stored, ~0.3 GB egress | ≈ 0.05 |
| Cloud Scheduler | 1 job | ≈ 0 |
| **Total** | | **≈ $1.5/day ≈ $45/month** (Haiku-class at $0.10/$0.50) · **≈ $9/day ≈ $270/month** at $1/$5 |

Main levers: cache judge results by image hash on device, fewer heartbeats (listen to `queue/{uid}`
instead), `minInstances` only if cold starts hurt (costs money).

## 14. Deploy (what a human must do)

> **v2.0: steps 1–5 are now Terraform** (`infra/terraform`, `docs/LEARN_GCP.md` §4): project
> APIs, Firebase link, Firestore (asia-northeast1), anonymous Auth, the default Storage bucket,
> Android/iOS apps + App Check, the `ANTHROPIC_API_KEY` secret container, the budget and the
> kill-switch topic. Humans still: create the project and link billing, run `bootstrap/` once, set
> the secret value, set `CLAUDE_MODEL`, and deploy functions/rules with the Firebase CLI —
> `functions-deploy.yml` authenticates with **Workload Identity Federation** (no JSON key). The
> manual steps below remain valid for a project managed without Terraform.

1. **Create the Firebase project** (replace `doodle-battle-dev` in `firebase/.firebaserc`) and
   switch to the **Blaze plan** (required for Cloud Functions v2, Secret Manager, Scheduler).
   Set a GCP budget alert.
2. **Firestore** in Native mode, location **asia-northeast1** (the Firestore trigger must be in the
   same region). **Storage** default bucket in asia-northeast1.
3. **Authentication**: enable *Anonymous*.
4. **App Check**: register the Android app with the **Play Integrity** provider (add the Play app
   signing SHA-256 certificate), enable enforcement for Cloud Functions (functions already set
   `enforceAppCheck: true`), and preferably for Firestore and Storage. Debug tokens for dev
   builds.
5. **Anthropic API key**: `npx firebase functions:secrets:set ANTHROPIC_API_KEY` (from
   `firebase/functions`, with `--config ../firebase.json`). Configure spend limits in the
   Anthropic console and check the organisation's data-retention settings for the privacy policy.
6. **Model param**: create `firebase/functions/.env.<projectId>` with `CLAUDE_MODEL=<id of the
   latest Haiku-class model>` (or answer the prompt during deploy).
7. Deploy: `cd firebase/functions && npm ci && npx firebase deploy --config ../firebase.json
   --project <id> --only functions,firestore,storage`. Accept the prompt that grants Storage rules
   access to Firestore (cross-service rules). Indexes are in `firestore.indexes.json`.
8. **Operations**: someone must review `moderationQueue` (Firebase console) and set the snapshot
   `status` to `active` (false report) or `removed`, then mark the entry resolved; also review
   snapshots with `moderation.suspectSkill`.
9. **Play Console / Data safety**: declare drawings (optional, parent-enabled, processed by
   Anthropic), anonymous ID, crash logs; provide the account-deletion web resource required by
   Play (explain the in-app deletion; a support channel can call `deleteMyData` on the user's
   behalf given the support ID = uid shown in the parent settings).

## 15. Assumptions and open decisions (for the PM)

- Each stat ≤ 70% of the budget (SPEC "weights ≥ 0.15" is ambiguous about normalisation) — confirm
  with Vision. Growth: +4%/level and +3%/seed of the Lv1 value, rounded once — confirm with Battle.
- Draw XP 70, full XP for ghost matches, Elo per **user** (not per character), K 32/16, matching by
  level only (not rating).
- Forfeit after 3 consecutive missed turns; turn cap 30 decided by HP ratio.
- Report hide threshold 3; only opponents of the last 50 matches can be reported.
- Character names: 1–10 chars, kana/latin/kanji, ≤ 2 digits; move names must be kana ≤ 10.
- SPEC §5 says players "write actions to `matches/{id}` and a `resolveTurn` function resolves
  them"; implemented as the `submitAction` callable that resolves in the same transaction
  (clients never write to Firestore), per the backend brief.
- `judgeDrawing` refusal → `appropriate: false` with neutral skill 50.
- The NG dictionary is a starting point; it needs review by a native speaker / trust-and-safety and
  regular updates (bump `version`, keep both vector files green).

## 16. Cost mode (v2.0, SPEC §12.6–12.7)

`config/costMode` tells every part of the system how much paid cloud work to do this month. It
is written only by `onBudgetAlert` (or by the owner in the console with `pinned: true`). Values
and thresholds live in `shared/cost_mode/cost_mode.json` (copied into functions and the battle
server by `sync-shared`). Full explanation for the owner: `docs/LEARN_GCP.md` §6.

| mode | when (GCP spend + AI estimate vs. budget) | `cloudJudge` | `cloudMoveGen` | `pvp` | `ghostAfterSec` |
|---|---|---|---|---|---|
| `normal` | < 80 % | true | true | true | 20 |
| `saving` | ≥ 80 % (or forecast ≥ 120 %) | false | false | true | 8 |
| `minimal` | ≥ 100 % | false | false | false | 3 |

Server-side enforcement (done):
- `getAiService()` wraps the AI service (`src/cost/aiUsage.ts`): `judgeDrawing` (and future
  `generateMove(s)`) throw `AiUnavailableError` when the flag is off, so `judgeDrawing` returns
  `AI_UNAVAILABLE` and the app silently keeps its on-device result (it already does this for any
  failure). Every AI call adds an estimate to `ops/aiUsage_YYYYMM` because the AI provider is
  billed outside GCP. **Moderation (`moderateCharacter`) is never gated.**
- v1 `joinQueue` / `sweepMatches`: ghost after `min(60 s, ghostAfterSec)` outside normal mode; no
  PvP pairing when `pvp` is false. The realtime server does the same with the v2 timings.
- Readers cache the document for 60 s and fall back to `normal` if it cannot be read.

**For the client team** (no UI change, ever — the child must not notice):
- Read `config/costMode` once per app start and at most every 10 minutes (one Firestore `get`;
  rules allow any signed-in user). Use `flags`, ignore `mode` for logic.
- `flags.cloudJudge == false` → skip the `judgeDrawing` call and use the on-device judgement
  directly (saves latency; the server would refuse anyway). Same for move generation with
  `cloudMoveGen`.
- `flags.pvp` / `ghostAfterSec` → nothing to do: the server decides. Keep showing
  「あいてを さがしているよ」 until `match` arrives.
- If the document is missing or unreadable, behave as `normal`.
- Never show the mode, a "saving" message or a budget to children or parents in the app.

## 17. Realtime battle server (v2.0)

`server/realtime/` (TypeScript, Node 22, `ws`) on Cloud Run, asia-northeast1, min 0 / max 1
instance (in-memory matchmaking), session affinity, request-based billing, 15 min request timeout.
Protocol and client rules: `docs/REALTIME_PROTOCOL.md`. Summary:
- Auth: Firebase ID token + App Check token in the first message (`hello`), then
  `users/{uid}.consent.online`; one live connection per uid.
- Matchmaking: Elo band ±100 (+50 / 5 s, max ±400), same pair once per 60 min, ghost after
  `ghostAfterSec` (ghost = active snapshot near the rating, not own, not one of the last 10;
  mirror of the own character if none exists). Rated play at Lv50 (`ratedFighter(source, 50)`).
- Battle: server-authoritative 10 Hz ATB through `src/engine.ts` (Engine v3 adapter; dev stand-in
  until it lands), server-owned さきどり, 50+3-tick おまかせ timeout, ghost AI, 10 s / 30 s
  disconnect rules.
- Results in one Firestore transaction: `users/{uid}.rated` (Elo K 48→24, ghosts half, floor 600,
  XP for 20 matches/JST day), `snapshots/{id}.ghostRating`, `rtMatches/{id}`, `replays/{id}`
  (seed + input log, TTL 30 days). Badges come from the best rating and never go down.
- Operations: `/healthz`, structured JSON logs (`event` = `match_start`, `match_end`, `stats`,
  `auth_rejected`), SIGTERM drain (running matches end as `aborted` without rating changes).

