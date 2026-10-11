# おえかきファイターズ v2.0: infrastructure research (Infra Research team)

Branch `spike/infra`, 2026-10-10. Scope: SPEC §12 (v2.0) server-side questions. These are
research decisions with sources, not implemented code. Prices were checked on 2026-10-10 and
must be re-checked before launch. **Unverified** marks a value that comes from third parties
or that we could not confirm.

## 0. 要約（オーナー向け）

| 項目 | 推奨 | 予備案 |
|---|---|---|
| クラウドの画像→3D | **自社の GCP で TRELLIS.2（MIT ライセンス）を動かす**（Cloud Run GPU、シンガポール）。子どもの絵を外部の AI 事業者に渡さない。保存せず、学習にも使わない | **Tripo API**（有料プランは「学習に使わない」と規約にある。書面で確認し、DPA を結んでから使う）。どちらにするかは、子どもらしい絵 40 枚の比較テスト（§1.6）で決める |
| 技の生成 AI | 既存の Claude（Haiku 系、`CLAUDE_MODEL`）。AI が選べるのは名前・説明・テンプレートと演出の ID だけ。数値はサーバーのコードが予算から計算する | AI が失敗・拒否したら、端末と同じテンプレート生成器で作る |
| オンラインのリアルタイム対戦 | **Cloud Run（東京）の WebSocket サーバー 1 台**で共有の TS エンジンを 10 Hz で動かす。マッチングはこのサーバーのメモリ内で行い（Glicko-2、15 秒待ったらゴースト）、結果だけ Firestore に書く | 規模が大きくなったら、マッチ ID でシャーディングした複数のサービスに分けるか、GKE/Agones に移る |
| 月額コスト（目安） | 1k DAU で **約 $150〜170**、10k DAU で **約 $600** | 広告収入の見込み: 1k DAU で **約 $30**（幅 $4〜170）、10k DAU で **約 $300**（幅 $40〜1,700） |

プラン別（§4.5）: 梅 は 1k DAU で約 $40〜85、10k DAU で約 $175〜225／竹 は約 $140〜170、約 $550〜600／松 は自社で動かして約 $530、約 $3,850（Tripo の自動リグを使うと約 $5,150、約 $51,000）。iOS の注意点は §3.7 にある。キッズカテゴリでは AdMob が審査で却下されるおそれがあるので、iOS では広告なしのビルドを用意しておく。

**結論: 子ども向け（パーソナライズなし）のリワード広告だけでは、クラウドの 3D 生成の費用はまかなえない。** 3D 生成は「Lv10 になったキャラへのごほうび」とし、1 人あたり 1 日 1 回・1 週間 3 回まで、さらに全体の月の予算で上限をかける（§4.4）。オーナーには月の予算、DPA の締結、比較テストの実施を決めてもらう必要がある（§6）。

---

## 1. Cloud image→3D for children's drawings

### 1.1 Requirements (from SPEC §12.2 and COMPLIANCE)
- Input: one cut-out PNG (≤512 px today; up to 1024 px is fine) of a **flat 2D drawing** —
  crayon lines, uneven fills, no shading, often non-humanoid (blobs, stars, cars, "a cat with
  six legs").
- Output: GLB with baked textures, mobile-friendly (≤20k triangles, ≤1K textures, ≤1 MB after
  meshopt/Draco + KTX2), and an animation solution (idle/attack/hit/faint).
- Runs only with **parental consent** (new consent flag `cloud3d`, or reuse `cloudJudge`, see §6).
  Also used for the hidden Lv50 re-generation of "simplified" characters.
- **The provider must not train on the images. Retention must be short, a DPA must be
  available, and the provider's terms must allow use in a children's app.** Japan only; APPI
  requires us to disclose any foreign recipient and the country it is in (privacy policy).

### 1.2 Comparison

| Option | Single image → GLB | Rigging / animation | Price per textured model | Rate limits / latency | Training on our inputs? | Retention / DPA / region | Kids-app fit |
|---|---|---|---|---|---|---|---|
| **Meshy** API (Meshy 7.1 / 6) | Yes. Accepts a data URI; `pose_mode`, `moderation` flag; GLB, FBX, USDZ, … [M2] | Auto-rig 5 credits, animation 3 credits per action [M1]. Humanoid-oriented | 30 credits (2K textures). At the Pro plan's 1,000 credits for $20 that is about **$0.60**; with a rig and 3 animations about **$0.80** [M1][M6]. Enterprise pricing is by quote | Pro: 20 req/s, 10 tasks in the queue. Enterprise: 100 [M3]. About 1–3 min | **Yes for non-Enterprise**: ToS §2.9 lets Meshy "use Customer Inputs and Customer Outputs" to train. §2.9 does not apply to Enterprise [M5] | API outputs are deleted after 3 days [M4]. Input retention is not stated; data "may be stored anywhere in the world". No public DPA; contact sales [M7] | Users must be 14+ or the local age with parental permission [M5]. A B2B API use behind our consent should be fine, but this must be confirmed with Meshy. **Only acceptable with an Enterprise contract** |
| **Tripo** API (VAST; H3 / P1 models) | Yes. `image_to_model`, async task polling [T2] | `rig_check` free, auto-rig $0.25, retarget $0.10 per animation [T1]. Biped, quadruped and more | 30 credits = **$0.30** ($0.01 per credit). HD texture +$0.10 [T1] | Not published. About 1 min | According to Tripo's help centre, **paid users' inputs and outputs are excluded from training (ToS §5.2.2)**. Free users' content is not excluded [T3] (*unverified: we could not fetch the page directly, 403*) | Retention is not stated publicly. The operator (Holymolly Ltd / VAST) is China-linked, so the jurisdiction must be confirmed for the APPI disclosure. DPA: ask business@tripo3d.ai | ToS: 13+ or with parental permission [T3]. **Acceptable with a paid plan and written confirmation of no training, retention and a DPA** |
| **Hunyuan3D** via Tencent Cloud International | Yes (Pro/Express; there is also a "Sketch" mode) | Not in the API price list | Pro 25 credits at $0.015–0.02 = **$0.38–0.50** [H2] | 3 concurrent tasks by default; more cost $5,000 per month per slot [H2] | Service terms: Tencent "retains the **perpetual right to use the Content to … develop, and improve the Services**" [H3] | Singapore endpoint. Retention not stated | **Rejected** (perpetual right to improve the service) |
| **Hunyuan3D-2.1** open weights, self-hosted | Yes (shape + PBR texture) | No | GPU time only (≈ TRELLIS.2, below) | Our own | No (our infrastructure) | Our GCP project | Licence: territory excludes the EU, UK and South Korea (**Japan is OK**). Needs a separate licence above 1M MAU. Outputs may not be used to improve other models [H4]. **Possible alternative model** |
| **Rodin / Hyper3D** Gen-2 (Deemos) | Yes | Not in the API | About $0.5–1.5 (third-party estimates; API access needs the $120/month Business plan) [R1] | Unknown | Not stated publicly [R2] | Unknown | Too expensive, and the terms are unclear. **Not chosen** |
| **Stability** SF3D / SPAR3D | Yes. Fast (a few seconds) | No | SF3D 10 credits = **$0.10** [S1] | – | A third-party summary says API inputs are not used for training by default (*unverified*) [S2] | Hosted on AWS in the US (*unverified*) | Object-quality meshes and weaker results on characters. **Low-quality fallback only** |
| **TRELLIS.2-4B** (Microsoft, **MIT**), self-hosted on Cloud Run GPU | Yes. Mesh + PBR, exports GLB with 4K textures (we downscale) [TR1] | No (we animate procedurally, §1.4) | GPU time: **about $0.05 per model at 10k DAU and $0.10–0.15 at 1k DAU** (batched, including cold starts, §1.5) | Our quota (3 GPUs by default). H100: 3 s at 512³, 17 s at 1024³; an L4 is several times slower [TR1] | **No.** The image never leaves our GCP project | Same Google Cloud DPA as Firebase. GPU regions: **Singapore** (no Tokyo GPU on Cloud Run) [G2] | Needs at least 24 GB of GPU memory, Linux, CUDA 12.4. Raw meshes can have small holes [TR1]. **Recommended primary** |
| TRELLIS.2 hosted (fal, Replicate) | Yes | No | fal about $0.25–0.35, Replicate about $0.82 (*third-party*) [TR2] | – | Not stated | DPA unknown | No advantage over self-hosting for privacy. Not chosen |
| CSM, Luma Genie | Still listed in 2026, but little API documentation [C1] | – | – | – | – | – | Not evaluated further |

**Quality on flat children's drawings: no public evidence.** We found no independent
benchmark of image→3D models on children's drawings. Vendors only show tutorials such as Meshy's
"turn any drawing into 3D" [M8], and Tripo and Hunyuan advertise sketch input. Known failure modes
of image→3D on flat line art: the model produces a thin "card" or relief instead of a volume; it
treats black outlines as geometry; and it invents a back side that does not match. Hence the
mandatory bake-off in §1.6 before we commit. If TRELLIS.2 gives flat reliefs on drawings, try
Hunyuan3D-2.1's shape stage in the same container, then Tripo.

### 1.3 Decision
1. **Primary: a self-hosted TRELLIS.2 worker in our own GCP project** (Cloud Run service with
   1 GPU, `asia-southeast1`, instance-based billing, `min-instances=0`, `concurrency=1`,
   `max-instances` = GPU quota). Reasons: (a) a child's drawing is never sent to an extra AI
   vendor, so there is no training risk and no new sub-processor or country to disclose beyond
   Google; (b) it costs 3–6× less than Tripo and 6–12× less than Meshy at our volumes; (c) the
   MIT licence has no territory or MAU limits. Before deploying, check the licences of
   everything the pipeline loads (feature extractor, any background-removal model). We skip
   background removal because our input is already cut out.
2. **Fallback: the Tripo API (paid plan)**, behind the same job interface. Turn it on only
   after: written confirmation that inputs and outputs are not used for training, a stated
   retention period (≤30 days) or a deletion API, a signed DPA, the operator's country added to
   the privacy policy, and a passing bake-off. Use it when self-hosted quality fails the
   bake-off or GPU capacity is exhausted.
3. Meshy only with an **Enterprise** contract (the only way to stop training under its ToS).
   Hunyuan via Tencent Cloud: no. Rodin: no (cost and unclear terms).

### 1.4 Animation without provider rigging
Children's characters are often not humanoid, so humanoid auto-rigs (Meshy, Tripo) will fail on
many of them. **Animate every model with the same procedural system as the on-device "inflated"
model**: squash-and-stretch, hop, lean and spin through a lattice or vertex-shader deformer on the
model's bounding box, and a "wobble" along the vertical axis. This is engine-independent and
needs no rig. Optionally, when Tripo's free `rig_check` reports a biped or quadruped, buy the
rig ($0.25) and play retargeted clips (10 credits each). That is a later enhancement, not needed
for v2.0.

### 1.5 Server flow (Cloud Functions + Cloud Tasks + Cloud Run GPU)

```
App ──callable requestModel3D({characterId, imageSha256, reason: "lv10_reward"|"lv50_regen"})──► Functions (asia-northeast1)
   1. App Check + auth + consent.cloud3d + per-child caps (§4.4) + global budget counter
   2. Image: the app uploads the cut-out PNG to Storage `gen3dInput/{uid}/{jobId}.png` (rules: owner write-once, ≤1 MB, image/png)
   3. Moderation: reuse the Claude moderation result stored for this imageSha256 (registerCharacter/judge),
      or run it now. Reject: real person, sexual, violence, personal info. AI-generated or pro images are allowed (SPEC §12.2)
   4. Firestore `gen3dJobs/{jobId}` {uid, characterId, status: queued, provider, imageSha256, createdAt}
   5. Cloud Tasks queue `gen3d` (rate limit = GPU count, max attempts 2, dispatch deadline 30 min) ──► worker URL (OIDC)
Worker (Cloud Run GPU, asia-southeast1)  ── or the Tripo adapter (Function, polls the task every 10 s up to 10 min)
   6. Read the PNG → generate (TRELLIS.2 at 1024³) → decimate to ≤20k triangles, 1K textures, meshopt → GLB
   7. Render a 256 px thumbnail; Claude vision check of the thumbnail (cheap, fail-closed only for online use)
   8. Write `models3d/{characterId}/{jobId}.glb` + thumbnail to Storage (asia-northeast1); update the job doc to `done`
   9. **Delete** the input PNG immediately (Storage lifecycle rule: delete `gen3dInput/` objects after 1 day as a backstop)
App listens to its own job doc (or polls a callable) → downloads the GLB → caches it on the device
```
- **Batching for cost**: the queue drains in bursts. Cloud Tasks holds jobs until a scheduler
  "pump" (every 30 min, 07–21 JST; every 10 min above 3k DAU) resumes the queue, so one cold
  start (pull the image, load about 16 GB of weights; budget 2–4 min) serves many jobs. The child
  sees 「たまごを あたためているよ（すこし じかんが かかるよ）」 and keeps playing with the
  on-device model. Turn batching off when volume keeps the instance warm.
- **GPU sizing**: an L4 (24 GB; minimum 4 vCPU/16 GiB, recommended 8/32) costs about
  $1.42/h [G1]. It is borderline for TRELLIS.2 memory; test 1024³ with fp16 and low-VRAM
  options. An RTX PRO 6000 (96 GB; minimum 20 vCPU/80 GiB) costs about $3.19/h [G1][G2] and is
  about 3× faster. Cost per model: 1–2 min of L4 time ≈ $0.03–0.05 when warm; at 1k DAU,
  cold starts bring it to about $0.10–0.15.
- **Commercial adapter (Tripo)**: `POST /v3/files` (upload), then `POST image_to_model`, then
  poll `GET /v3/tasks/{id}` [T2] from the Function. Download the GLB at once, because providers
  delete outputs (Meshy after 3 days [M4]). Never store provider URLs.
- **Idempotency**: job key = `sha256(uid, characterId, imageSha256, reason, pipelineVersion)`.
  A retried request returns the existing job. `deleteMyData` must also delete `gen3dJobs`,
  `models3d/` and any input left behind.
- Lv50 regeneration: the server decides eligibility (the snapshot is flagged `simplified`, the
  level is 50 or more, and the level was server-verified when the character was registered).
  The app shows the result as a normal evolution. Nothing in the UI or the API names says
  "hidden".

### 1.6 Bake-off (do this before choosing)
- Inputs: the 13 bundled synthetic CPU drawings (`app/assets/cpu/*.png`), plus about 30 more
  drawings made by adults in a child-like style (crayon on paper, phone photos, with our
  cut-out pipeline). **Do not use real children's drawings** until consent and a DPA are in place.
- Candidates: self-hosted TRELLIS.2 (512³ and 1024³), Hunyuan3D-2.1 (self-hosted), Tripo
  (paid trial), Meshy (trial, no children's data), and our on-device inflation as the baseline.
- Score each drawing 1–5 on: recognisable from the front, plausible volume (not a card), colour
  fidelity to the crayon, no scary artefacts, file size after decimation. Count failures. Gate:
  a mean of 3.5 or more and fewer than 10% "scary or broken".

## 2. AI move generation (Claude)

### 2.1 Principle
**The AI chooses words and IDs. The game computes numbers.** The game-design team owns
`shared/move_templates/` (template catalogue + budget schema). The AI picks from enumerations
and writes kana text, and deterministic shared code turns template + budget + choices into
power, SP cost and effect amounts. So no prompt injection or hallucination can change balance.

### 2.2 Data contract (server side; the schema details are owned by game design)
```jsonc
// request to the model (built by the server, never by the client)
{ "slot": "birth" | "lv10" | "lv50",
  "element": "a" | "b" | "c",                  // 3-way elements (SPEC §12.3)
  "traits": ["かたい", "とがってる", "まるい"], // server-derived adjectives from features (enum list)
  "subject": "ねこ",                           // from judgeDrawing (already NG-filtered), optional
  "allowedTemplates": ["strike_heavy", "beam", "guard_up", …],  // filtered by slot/element/simplified flag
  "allowedVfx": ["sparkle", "flame_burst", …], "allowedSfx": [...],
  "existingMoves": [{"templateId": "...", "name": "..."}] }
// structured output (output_config.format, zod; enums are the allowed lists)
{ "moves": [ { "templateId": "<enum>", "bias": "power" | "balanced" | "efficient",
               "name": "<kana 2–10>", "flavour": "<kana ≤ 40>", "vfxId": "<enum>",
               "sfxId": "<enum>", "colorId": "<enum>" } ] }
```
The server computes numbers with `computeMove(template, budget(levelSlot, characterPower,
isSimplified), bias)` in shared TypeScript (golden vectors, ported to the client like the
battle engine).

### 2.3 Flow
1. **Birth moves are generated in the same Claude call as `judgeDrawing`** (the image is already
   in that request). This saves one call and the image tokens. The Lv10 and Lv50 moves are
   text-only calls (`generateMove` callable) from the stored `subject` and `traits`. No image is
   needed, so we keep no image.
2. Callable checks: App Check, auth, `consent.cloudJudge`, rate limit (5 per day per child), and
   level eligibility (server-verified when online; otherwise trust the device, which is harmless
   because numbers do not come from the AI).
3. **Cache** in `moveGen/{key}` with `key = sha256(imageSha256 | slot | templatesVersion |
   promptVersion)`. The same drawing gives the same moves (SPEC determinism), and retries and
   reinstalls cost nothing.
4. **Validate** every field: schema parse; kana regex and length; shared NG normaliser and
   filter; no duplicate names; `templateId ∈ allowedTemplates`; vfx compatible with the
   template. **Replace any invalid field** with the deterministic on-device template generator
   (seeded by the image hash), so a bad field never blocks the child.
5. Refusal (`stop_reason: "refusal"`), API error or timeout (10 s): use the full on-device
   template result, with `source: "template"`.
6. Online: move names go through the existing `registerCharacter` moderation, and the AI
   suggestion report button gets new kinds `move_name` and `move_flavour`.
7. Optional cost trick: pre-generate the Lv10 move at Lv8 and the Lv50 move at Lv45 through the
   Message Batches API (50% cheaper, not latency-critical).

### 2.4 Prompt-injection safety
- Untrusted inputs are only the drawing image (writing inside it) and `subject` (AI output,
  already filtered). **The child-typed character name is never sent.**
- The system prompt says that text in the picture is data, never instructions, and that names
  written in the picture (possible real names) must never be used.
- The model has no tools, so injection can at worst produce odd kana text, which the NG filter,
  the report button and online moderation catch. It cannot change numbers, IDs outside the enums
  or other users' data.
- Log only the validation outcome codes, not the generated text of rejected outputs (same rule
  as BACKEND §1).

### 2.5 Tokens and cost per character
Pricing from the claude-api skill (cached 2026-10-06): the current Haiku-class model costs
**$0.10 input / $0.50 output per MTok**; cache reads cost 0.1×; the minimum cacheable prefix is
512 tokens; the Batch API is 50% off. A 512×512 image is about 340 tokens (≈ one token per 28×28
patch). The model id stays in the `CLAUDE_MODEL` param.

| Call | Input | Output (incl. low-effort thinking) | Cost |
|---|---|---|---|
| Birth: judge + 2 moves (image) | ≈2,200 system + 340 image + 250 JSON | ≈650 | ≈ **$0.0006** uncached / $0.0004 with a cache hit |
| Lv10 or Lv50 move (text) | ≈2,000 + 300 | ≈500 | ≈ $0.0005 (half that through the Batch API) |
| **Per character, lifetime** | | | ≈ **$0.0016 (≈ ¥0.25)**. At Haiku 4.5 list prices ($1/$5) it would be ≈ $0.016 |

Prompt caching pays off only when the same prefix is used again within 5 minutes. At 1k DAU
(about 15 calls per hour) most calls miss, so enable `cache_control` only when traffic is above
about one call per 5 minutes (≥3k DAU), or use the 1-hour TTL.

## 3. Real-time online ATB battles (rated)

### 3.1 Load (the brief's assumptions)
20% of DAU play online, 3 matches each per day, 3 minutes per match. That is 1,800
player-minutes per day per 1k DAU. If 20% of play happens in the evening peak hour: **about 6
concurrent players at 1k DAU and about 60 (peaks of 120) at 10k DAU.** One small Node process
can simulate thousands of 10 Hz ATB matches, so capacity is not the problem. **Matching is**: at
1k DAU there are rarely two children with a close rating queuing at the same time, so most
matches will be ghost matches. The ghost fallback is essential (§3.4).

### 3.2 Comparison

| Option | Latency from Japan | Server authority / TS engine reuse | Cost at 1k / 10k DAU | Ops | Client SDK (Flutter / Unity / Godot) | Families / data |
|---|---|---|---|---|---|---|
| **Cloud Run (Tokyo) WebSocket service** | One region hop, about 10–40 ms of network RTT | Node 22 runs the shared TS engine directly | ≈ $25–45 / $45–95 (1 vCPU always on ≈ $44; 2 vCPU ≈ $93; scale to zero during the day at 1k) [G1] | Low. Caveats: session affinity is best-effort and connections end at the request timeout (≤60 min) [G3]. Hence a single instance and in-process matchmaking | WebSocket only: `web_socket_channel` / NativeWebSocket or `System.Net.WebSockets` / Godot's built-in `WebSocketPeer` | No new SDK or processor (Google, already disclosed) |
| Firebase RTDB relay + server ticker | RTDB is only in us-central1, europe-west1 or **Singapore** [F2]. Each step is client → RTDB → ticker → RTDB → client, about 150–250 ms | Yes (the ticker runs the TS engine) | Downloads $1/GB, 200k connections [F1]. ≈ $5–30 + ticker ≈ $45 | Medium (ticker leases, sharding) | Official Firebase SDK in Flutter and Unity. Godot: REST-only community plugins [E3] | Fine |
| Firestore listeners | 100s of ms to about 1 s per update | Yes (Functions) | 10 Hz writes: ≈ 1,800 writes per match → ≈ $20/day at 10k DAU | Low | Flutter and Unity official. Godot: community | Fine, but **too slow and expensive for ATB**. Keep only for turn-based or async |
| GKE Autopilot + Agones | Tokyo | Yes | Cluster fee ≈ $73/month + pods; > $150/month | **High** for a small team | WebSocket/UDP | Fine |
| Unity Multiplay | – | – | – | Unity ended direct support on 2026-03-31; the hosting moved to Rocket Science [E4] | – | **Avoid** |
| Colyseus Cloud | Region list unverified (older docs list Seoul, not Tokyo) | **Node/TS, so the engine is reusable** | From $15/month, no CCU limits [E1] | Low | Official Unity SDK. Dart and Godot: community or none | New processor (IP, anonymous IDs): needs a DPA and a privacy-policy entry |
| Nakama / Heroic Cloud | Region by request | TS runtime is **ES5 only** (goja; no async, limited ES6), so the engine needs transpiling and testing [E2] | Heroic Cloud price on request; third parties say from about $600/month [E2] | Low (managed) or high (self-host with Postgres) | **Official SDKs for Dart/Flutter, Unity and Godot** [E2] | New processor |
| Photon (Realtime / Fusion / Quantum) | Has a Japan region | Server logic in C# (Quantum is deterministic C#), so **the TS engine cannot be reused** | 500 CCU $95/month; free tiers only for Fusion/Quantum [E5] | Low | Unity first-class; no official Dart; Godot via .NET only | New processor |

### 3.3 Decision: one Cloud Run "battle-server" in asia-northeast1
```
                   (HTTPS callables, unchanged)                         (Admin SDK)
 Client ──► Cloud Functions: registerCharacter, judge, gen3d, deleteMyData ──► Firestore / Storage
   │
   └─ wss://battle-<hash>-an.a.run.app/v2  (Cloud Run, asia-northeast1, min 0–1, max 1, concurrency 1000,
        │                                     timeout 15 min, session affinity on, 1 vCPU / 512 MiB)
        │  hello{idToken, appCheckToken, proto, resume?} ─► verifyIdToken + appCheck.verifyToken + consent.online
        │  queue{snapshotId}  ─► in-memory matchmaker (Glicko-2 window + power band, 15 s → ghost)
        │  match{matchId, sides, myMoves, tickHz:10}   ◄─ snapshot stats loaded from Firestore (never from the client)
        │  select{matchId, seq, slot}  ─► validated (gauge full, SP, slot owned, ≤5 msgs/s)
        │  ev{tick, events[]} (immediately) + snap{tick, hp, sp, gauge} at 2 Hz  ◄─ engine.step() every 100 ms
        │  end{winner, ratingDelta, xp}  ◄─ Firestore transaction: users/{uid}.rating, matches/{id} summary,
        │                                    replays/{id} {seed, engineVersion, inputs[]} (TTL 30 days)
        └─ checkpoint: every select is also written to matches/{id}.inputs (enough to replay after a restart)
```
- **Why a single instance**: the two players of a match must reach the same process, and Cloud
  Run cannot route by match. With `max-instances=1`, the matchmaker and every match are in one
  process, and any reconnect lands there. Capacity is far above our load (§3.1).
- **Instance restarts and deploys**: matches are short (3 min) and deterministic. On restart, the
  new instance rebuilds active matches from `matches/{id}` (seed + timestamped inputs) when the
  clients reconnect (resume token). Deploy with a new revision that only accepts *new* queue
  entries while the old one drains (or deploy in a quiet hour). Cloud Run may briefly run more
  than `max-instances` during surges, so a match is owned through a Firestore lease
  (`ownerInstance`, 10 s heartbeat). A non-owner tells the client to reconnect. If ownership
  cannot be settled, the match is aborted with no rating change.
- **Scale-out path** (well above 10k DAU or more than about 2,000 concurrent players): run K
  identical services `battle-0..K-1`. `joinQueue` (a callable) picks the shard by rating bucket
  and returns its URL. If routing beyond that is needed, move to GKE/Agones. The protocol stays
  the same.
- **min-instances**: 0 below about 3k DAU (cold start 1–3 s on the first connection, hidden by
  the 「あいてを さがしているよ」 screen), 1 above that.
- **Battle engine reuse**: add the ATB engine v3 to `shared/battle_engine_ts` as a pure
  fixed-tick function `step(state, inputsAtTick) → {state, events}` with integer gauges
  (e.g. 0–10,000; `gain = AGI × k` per tick), the RNG state inside `state`, golden vectors as
  tick logs, and "おまかせ" AI as a pure function of state + its own seed. The server imports it
  through `sync-shared` as today. The client needs the engine only for offline single-player
  (port it with the golden vectors, as Dart does today). For online play the client just renders
  `ev` and `snap`, interpolating gauges between snapshots at 60 fps.

### 3.4 Matchmaking by rating, with ghosts
- **Glicko-2 per user** (rating 1500, RD 350, volatility 0.06). Children play irregularly, and RD
  models uncertainty better than a fixed Elo K. The badge is shown from a conservative rating
  (`r − 2·RD`) with a **floor**: a child never drops below a badge once earned (game design
  decides the tiers).
- Window: `|Δr| ≤ 100 + 25·wait_s`, capped at 400, **and** character power within ±25% (stats
  and level differ a lot; the rating alone is not enough).
- **Ghost after 15 s** (v1 used 60 s; children will not wait). Pick an active snapshot with the
  closest rating and power, not the child's own, and not one played in the last 10 matches. The
  server's "おまかせ" AI drives the ghost. The ghost's owner is unaffected. The player's rating
  update uses the ghost with a raised RD (≥150), so ghost results move ratings about half as much.
- PvP is preferred while a queued partner exists. Expect mostly ghosts at 1k DAU.

### 3.5 Reconnects, timeouts, anti-cheat
- **Reconnect**: a resume token per match. Within 30 s, the server resends `match` + the latest
  `snap` + events after the client's last acknowledged seq. While a player is disconnected,
  "おまかせ" plays for them (SPEC §12.4's 5 s timeout rule), so the match always finishes and
  disconnecting does not help. A result is final even if the player never returns.
- **Anti-cheat basics**: server authority and server RNG; stats only from the server snapshot;
  the client sends only `{slot, seq}`, and the server validates gauge, SP and ownership; the
  opponent's selection stays hidden until it executes; ID token + App Check token on connect;
  one live connection per uid; message size ≤1 KB and ≤5 messages per second; every match is
  replayable from the seed + inputs (audits); limit rating gain from the same opponent pair per
  day (win-trading); `registerCharacter` stat validation as today (adapted to the 10 stats).
- Optional cost cut, not recommended for v2.0: verify ghost matches by replaying a client-run
  match. This is cheaper but lets modified clients search for optimal timings.

### 3.6 Client-engine implications (PM update: Flutter, Unity or Godot)
Keep the server protocol engine-independent: **HTTPS callables** (a documented JSON-over-HTTPS
protocol: POST `{data}` with `Authorization: Bearer <ID token>` and the `X-Firebase-AppCheck`
header) plus **WebSocket JSON** for battles. Do not rely on client-side Firestore listeners for
anything essential (the gen3d job status should also be pollable by a callable).

| Need | Flutter | Unity | Godot 4 |
|---|---|---|---|
| Firebase Auth (anonymous), Functions, Storage, Crashlytics | Official FlutterFire | **Official Firebase Unity SDK** | No official SDK. Community REST plugins (GodotFirebase: Auth incl. anonymous, Firestore) [E3]. Callables over plain HTTP |
| App Check / Play Integrity | Official | Official (`PlayIntegrityProviderFactory`) [E6] | **Gap**: write an Android plugin that gets a Play Integrity token and exchanges it through the App Check REST API (custom work, a risk) |
| WebSocket battle client | `web_socket_channel` | `System.Net.WebSockets.ClientWebSocket` (Android/iOS) or NativeWebSocket | Built-in `WebSocketPeer` |
| Runtime GLB loading | Owned by the 3D-rendering spike | glTFast (Unity package) | Built-in `GLTFDocument` |
| AdMob, child-directed (Families-certified `play-services-ads`) | `google_mobile_ads` (current) | Official Google Mobile Ads Unity plugin | Community plugin (Poing Studios, MIT) wrapping the official Android SDK [E7]. Check that it exposes `tagForChildDirectedTreatment` / `maxAdContentRating` |
| Things to watch | – | Turn off Unity Analytics / Cloud Diagnostics; check the merged manifest for `AD_ID` (keep `check_release.sh`) | Check every plugin for Families compliance (Families policy covers all SDKs, not only ad SDKs) |

Third-party realtime services (Photon, Colyseus, Nakama) look attractive mainly with Unity. They
add a processor and do not remove the need for Firebase (moderation, Claude, storage), so the
recommendation does not change with the client engine.

### 3.7 iOS-specific constraints (PM update: Android + iOS)
- **Kids Category (Guideline 1.3)**: no links out of the app, no purchasing opportunities and no
  other distractions to kids except behind a parental gate. **No personal or device information
  may be sent to third parties.** Third-party analytics or advertising is allowed only "in
  limited cases": analytics that collect no IDFA or identifying or device information, and
  *contextual* ads only from services with "publicly documented practices … that include human
  review of ad creatives" [IOS1].
- **5.1.4**: apps that collect or share children's **drawings** (named explicitly) need a privacy
  policy and must follow children's privacy laws. The parental gate is not the same as parental
  consent. Apps outside the Kids Category may not say "for kids" in their metadata [IOS1].
  **2.5.18**: no targeted or behavioural ads based on data from kids [IOS1].
- **Ads on iOS are a real review risk.** Developer-forum reports show Kids-category apps rejected
  under 1.3 for AdMob or Unity Ads: reviewers asked for documented human review of ad creatives,
  then told developers to remove the ads, and flagged IDFA/ATT API references in the Google
  Mobile Ads SDK [IOS2] (anecdotal). Plan for an **ad-free iOS build (feature flag)** if review
  fails. Revenue in §4.3 should then count Android only. Never show the ATT prompt and never read
  the IDFA. Choosing the Kids Category is the owner's decision (§6).
- **Crashlytics** sends device data to Google. In the Kids Category, treat it as third-party
  analytics: keep it opt-in (as on Android), or leave it out of the iOS build if review objects.
  Firebase Auth, Functions, Storage and the battle server are our own backend (service providers),
  not third-party analytics.
- **App Check on iOS**: App Attest (iOS 14+) with DeviceCheck as fallback. Supported by
  FlutterFire and the Firebase Unity SDK [E6]. Godot has the same gap as on Android.
- **WebSocket and background**: iOS suspends the app seconds after it goes to the background, so
  the socket drops. This is expected: the resume token (§3.5) covers it, and "おまかせ" plays
  meanwhile. Do not request background modes (VoIP or audio tricks are rejected). Use native
  WebSockets (`URLSessionWebSocketTask` under Flutter, Unity or Godot). TLS only (ATS), which
  Cloud Run provides.
- **3D / AR**: GLB loads in all three engines. If the AR feature uses ARKit QuickLook, convert to
  USDZ (Meshy and Tripo can export it [M2]; self-hosted conversion with `usd-core` /
  Blender-free tools). No server change.
- Apple's privacy "nutrition label" must list drawings (optional, parent-enabled), the anonymous
  ID and crash data (optional), and must match the Play data safety form.

## 4. Total monthly cost model

### 4.1 Assumptions (central case; change them in the table)
- New saved characters: 0.5 per DAU per day. Parents who enable cloud features: 40%.
- Claude: 2 judge+moves calls per consented new character (retakes), Lv10/Lv50 moves, and
  0.05 registrations per DAU per day.
- **Cloud 3D: X = 5% of new characters** (with the caps in §4.4 this is about 1 generation per
  consented, engaged child per week). Sensitivity: 10% and 30%.
- Cost per 3D model: self-hosted $0.13 at 1k DAU (cold starts) and $0.05 at 10k DAU; Tripo
  $0.30; Meshy about $0.65.
- Online: 20% of DAU × 3 matches. WebSocket traffic about 90 KB per player per match.
- GLB about 0.8 MB after compression. Opponents' models are downloaded once and cached.
- Firestore in Tokyo at about $0.04 reads / $0.12 writes per 100k (us-central1 is $0.03 /
  $0.09 [F3]; Tokyo is slightly higher, so these are estimates). Egress from Tokyo is $0.14/GB
  after 10 GB [F3].

### 4.2 Costs (USD per month)

| Item | 1k DAU | 10k DAU | Notes |
|---|---|---|---|
| Cloud 3D, self-hosted (X = 5%: 750 / 7,500 models) | ≈ $100 | ≈ $375 | X = 10%: ≈ $195 / $750. X = 30%: ≈ $585 / $2,250 |
| ↳ same volume with Tripo instead | ≈ $225 | ≈ $2,250 | Meshy: ≈ $490 / $4,900 |
| Claude (judge + moves + moderation) | ≈ $10 | ≈ $105 | ×10 at Haiku 4.5 prices |
| Realtime (Cloud Run battle-server) | ≈ $25 (scale to zero) | ≈ $45–95 | Egress < $1 |
| Firebase (Firestore, Functions, Storage, egress, Tasks, Scheduler, Secret Manager, logs) | ≈ $5 | ≈ $25 | Firestore stays mostly inside the free tier at 1k |
| **Total (self-hosted 3D)** | **≈ $140–170** | **≈ $550–600** | Fixed part ≈ $40 |
| **Total (Tripo 3D)** | ≈ $265 | ≈ $2,400 | |

### 4.3 Expected rewarded-ad revenue (child-directed, non-personalised, Japan)
Public benchmarks (none are specific to Japan + Android + child-directed):
- Rewarded eCPM in Japan (blended OS): **$10.80** [AD1] or **$6.50** [AD2]. Tier-1 markets
  $15–40 (AppLovin, via [AD3]). Japan rewarded eCPMs rose 17% in Q2 2026 [AD4].
- Child-directed (COPPA-style) traffic: eCPMs **2.5–5× lower** than general traffic, according
  to one industry newsletter (directional) [AD5]. Google disables interest-based ads and
  remarketing for such requests [AD6].
- So for this app: **$1.3–4.3 eCPM, central $2.5.** Impressions per DAU per day = share with
  ads allowed (20/40/60%) × views (1/1.5/2.5, capped at 3) × fill (50/70/90%).

| | Low | Central | High |
|---|---|---|---|
| 1k DAU | $4 | **$32** | $174 |
| 10k DAU | $39 | **$315** | $1,740 |

**Uncertainty is large (more than 10× between low and high).** Measure in AdMob within the first
2 weeks and re-plan. Even in the central case the app loses money (about −$120/month at 1k DAU
and −$250/month at 10k DAU with self-hosted 3D). Without cloud 3D it roughly breaks even at
10k DAU.

### 4.4 Caps that keep cost bounded (recommendation)
| Cap | Value | Enforced by |
|---|---|---|
| Cloud 3D eligibility | Character is **Lv10 or higher** (the 「かがやき」 reward), plus the hidden Lv50 regeneration. Never on every new drawing | `requestModel3D` |
| Cloud 3D per child | **1 per day, 3 per 7 days**. Lv50 regeneration: once per character, outside the weekly cap | `rateLimits/{uid}` |
| Global 3D budget | `monthlyBudgetUsd / costPerModel` per month, released evenly per day. When it is used up, new requests are queued 「あしたに なるよ」 and the on-device model is kept | `ops/limits` doc + counter; Cloud Billing budget alert at 50/90/100%, and a Pub/Sub kill switch that sets `gen3dEnabled=false` |
| Claude judge | 10 per hour, 30 per day per child (down from 30/100) | existing `RATE_LIMITS` |
| Move generation | 5 per day per child. Cache by image hash | `generateMove` |
| Online matches | 1 live connection per uid; 20 rated matches per day (the parent's play-time settings still apply) | battle-server |
| Anthropic | Monthly spend limit in the Console = 2× the forecast | Anthropic Console |
| GPU | `max-instances` = 2 (the quota is 3) | Cloud Run |

### 4.5 Cost and infrastructure by plan tier (松 / 竹 / 梅)
The server side is the same for all three tiers (Firebase + Claude + Cloud Run battle-server +
the gen3d job pipeline). Only the 3D generation volume and the asset size change. Assumptions
are as in §4.1. "Consented" means 40% of children.

| | 梅 (Flutter 2.5D, on-device 3D; cloud 3D optional) | 竹 (Flutter shell + real 3D battle; on-device + cloud 3D with consent) | 松 (full game engine; cloud 3D with auto-rig for most characters) |
|---|---|---|---|
| Cloud 3D volume | Off at launch, or only the hidden Lv50 regeneration (≈ 0–1% of characters; ≤ 150 / 1.5k models per month) | Lv10 reward, capped (X ≈ 5%: 750 / 7,500 models per month) | Every consented new character, cap 2 per day (X ≈ 40%: 6,000 / 60,000 models per month) |
| 3D pipeline | TRELLIS.2 self-hosted (scale to zero) or Tripo pay-per-use (no fixed cost; simplest when volume is tiny) | Self-hosted TRELLIS.2 (Tripo as fallback) + procedural animation | Self-hosted TRELLIS.2 + **auto-rig** (UniRig, SIGGRAPH 2025, MIT per a third party, *licence of checkpoints to verify* [UR1]), or Tripo rig + retarget ($0.25 + $0.10 per clip [T1]) |
| Cost per model | Tripo $0.30 (low volume) | $0.13 (1k) / $0.05 (10k), self-hosted | Self-hosted with rig ≈ $0.08 / $0.06. Tripo with rig and 3 clips ≈ $0.85 |
| Realtime stack | Cloud Run WebSocket battle-server (§3.3). Same protocol for every client | Same | Same. The server stays ATB-event based; 3D movement is client-side choreography |
| GLB / egress | Small (few cloud models) | ≈ 0.8 MB per model | ≈ 1.5–2 MB (skin + clips): egress ≈ $5 / $40 |
| **Monthly cost, 1k DAU** | **≈ $40–85** (Claude $10, realtime $25, Firebase $5, 3D $0–45) | **≈ $140–170** | **≈ $530** self-hosted · ≈ $5,150 with Tripo rigging |
| **Monthly cost, 10k DAU** | **≈ $175–225** (+ 3D $0–75) | **≈ $550–600** | **≈ $3,850** self-hosted · ≈ $51,000 with Tripo rigging |
| Fits kids-mode ad revenue (§4.3 central: $32 / $315)? | Close at 10k DAU | No, needs a budget (≈ −$120 / −$250 per month) | No. Only viable with self-hosting **and** a much higher revenue source (e.g. the IAP restored later) |

Notes: 松 depends on self-hosting. Commercial rigging at 松 volumes costs 10× more. Auto-rigging
quality on blob-like children's characters is unproven, so keep the procedural animation as the
fallback in every tier. All tiers keep the §4.4 caps and the global budget kill switch.

## 5. Risks
1. **3D quality on flat drawings is unproven** for every option (no public evidence). Mitigation: the bake-off (§1.6); the on-device model is always the default.
2. **Cost against revenue**: kids-mode eCPM is low and uncertain. Cloud 3D must stay a capped reward, with a hard budget and a kill switch.
3. Provider terms change (Meshy and Tripo changed pricing and models during 2026). Self-hosting removes this; for the Tripo fallback, sign a DPA and re-check terms every quarter.
4. Cloud Run GPU is not in Tokyo (Singapore only), quota is 3 GPUs by default, and RTX PRO 6000 is a Preview [G2]. The data leaves Japan but stays with Google; update the privacy policy.
5. A single battle-server instance is a single point of failure. Mitigation: deterministic replay, resume tokens, abort without rating change, and the shard path.
6. Low concurrency at 1k DAU means PvP will be rare. Ghosts must feel good (AI quality, rating weight).
7. A Godot client would lack official Firebase and App Check support (§3.6).

## 6. Decisions needed from the owner
1. **Monthly server budget** (e.g. ¥20,000 at launch). This sets the global 3D quota (§4.4).
2. **Bake-off approval**: GPU quota in asia-southeast1 and about $50 of test spend; a Tripo paid trial (no children's data).
3. **Primary 3D path**: self-hosted (recommended; engineering time for the GPU container) or Tripo first (faster to ship; needs a DPA and its country in the privacy policy).
4. **Sign a DPA / written no-training confirmation** with any external 3D vendor (Tripo, or a Meshy Enterprise contract) before use. Confirm Anthropic's retention (COMPLIANCE §8-5) for move generation.
5. **Consent model**: a separate parent switch 「クラウドで 3D に する」 (recommended; it names the processing region, Singapore) or reuse 「クラウド判定」.
6. Accept **ghost-heavy matchmaking** at small scale and the 15 s ghost timeout.
7. Client engine choice (Flutter / Unity / Godot). Godot adds App Check and Firebase work (§3.6).
8. **iOS**: whether to list in the Kids Category (strict 1.3 rules), and whether to accept an **ad-free iOS build** if AdMob is rejected (§3.7).
9. Plan tier (松 / 竹 / 梅). The cost difference is driven almost entirely by cloud 3D volume (§4.5).

## 7. Sources (checked 2026-10-10)
- [M1] Meshy API pricing: https://docs.meshy.ai/api/pricing
- [M2] Meshy Image to 3D API: https://docs.meshy.ai/en/api/image-to-3d
- [M3] Meshy rate limits: https://docs.meshy.ai/en/api/rate-limits
- [M4] Meshy asset retention (API outputs kept for at most 3 days): https://docs.meshy.ai/api/asset-retention
- [M5] Meshy Terms of Use (§1.1 age, §2.5, §2.9 training, Enterprise exception): https://www.meshy.ai/terms-of-use
- [M6] Meshy pricing (Pro $20 per month, 1,000 credits): https://meshy.ai/pricing
- [M7] Meshy privacy policy: https://www.meshy.ai/privacy-policy
- [M8] Meshy drawing tutorials: https://www.meshy.ai/tutorials/turn-any-drawing-into-3d-art-with-meshy-just-upload-generate, https://www.meshy.ai/blog/sketch-to-3d
- [T1] Tripo developer pricing: https://developers.tripo3d.ai/en/pricing
- [T2] Tripo API introduction (v3 endpoints, rig, retarget, task polling): https://developers.tripo3d.com/en/docs/introduction
- [T3] Tripo privacy, training help article and terms (seen through search snippets; direct fetch returned 403): https://www.tripo3d.ai/privacy, https://www.tripo3d.ai/help/privacy-policy/how-to-understand-data-privacy-and-ai-training-at-tripo, https://www.tripo3d.ai/terms
- [H1] Tencent Hunyuan 3D global launch: https://www.tencent.com/en-us/articles/2202235.html
- [H2] Tencent HY 3D Global billing: https://www.tencentcloud.com/document/product/1281/74121
- [H3] Tencent Cloud service terms (§6.3(c)): https://intl.cloud.tencent.com/document/product/301/78149
- [H4] Hunyuan3D-2.1 licence: https://huggingface.co/tencent/Hunyuan3D-2.1/blob/main/LICENSE
- [R1] Rodin pricing: https://hyper3d.ai/pricing, https://www.costbench.com/software/ai-3d-generation/rodin-hyper3d/
- [R2] Hyper3D legal: https://hyper3d.ai/legal/privacy
- [S1] Stability API pricing update: https://stability.ai/api-pricing-update-25
- [S2] Third-party summary of Stability's data policy: https://conductatlas.com/platform/stability-ai/stability-ai-privacy-policy/
- [TR1] TRELLIS.2-4B model card (MIT, ≥24 GB GPU, timings): https://huggingface.co/microsoft/TRELLIS.2-4B
- [TR2] Hosted TRELLIS.2 prices (third-party): https://trellis2.app/blog/how-to-use-trellis-2-online-free
- [C1] CSM: https://csm.ai. Luma Genie listing: https://www.llmreference.com/provider/luma-api/genie-3d
- [G1] Cloud Run pricing (CPU, memory, L4 and RTX PRO 6000 per second): https://cloud.google.com/run/pricing
- [G2] Cloud Run GPU regions, minimums and quota: https://docs.cloud.google.com/run/docs/configuring/services/gpu
- [G3] Cloud Run WebSockets (timeout, best-effort affinity): https://docs.cloud.google.com/run/docs/triggering/websockets
- [F1] Firebase pricing: https://firebase.google.com/pricing
- [F2] Realtime Database locations: https://firebase.google.com/docs/database/locations
- [F3] Firestore pricing and network egress: https://cloud.google.com/firestore/pricing
- [E1] Colyseus pricing: https://www.colyseus.io/pricing, https://docs.colyseus.io/cloud/pricing-billing
- [E2] Heroic Cloud pricing: https://heroiclabs.com/pricing. Nakama TS runtime (ES5/goja): https://heroiclabs.com/docs/nakama/server-framework/typescript-runtime/. Dart client: https://pub.dev/packages/nakama
- [E3] GodotFirebase (REST): https://store.godotengine.org/asset/godotnuts/godotfirebase/
- [E4] Unity Multiplay Hosting status: https://docs.unity.com/en-us/multiplay-hosting
- [E5] Photon pricing: https://www.photonengine.com/pricing, https://doc.photonengine.com/photon/v1/pricing
- [E6] Firebase App Check for Unity: https://firebase.google.com/docs/app-check/unity/default-providers
- [E7] Godot AdMob plugin: https://github.com/poingstudios/godot-admob-plugin
- [AD1] Mistplay eCPM data: https://business.mistplay.com/resources/mobile-ads-ecpm
- [AD2] Undrads: https://www.undrads.com/blogs/how-much-do-mobile-games-make-per-ad
- [AD3] Coinis, rewarded video: https://coinis.com/glossary/rewarded-video
- [AD4] Bidlogic Q2 2026 eCPM trends: https://bidlogic.io/2026/07/31/q2-2026-ecpm-growth-interstitial-rewarded-video-and-banner-trends/
- [AD5] Game Biz Consulting, COPPA ad monetisation 2026: https://www.gamebizconsulting.com/newsletter/admon-newsletter-11-the-shrinking-island-ad-monetization-underage-users
- [AD6] AdMob targeting (child-directed treatment): https://developers.google.com/admob/android/targeting
- [IOS1] App Store Review Guidelines (1.3 Kids Category, 2.5.18, 5.1.4): https://developer.apple.com/app-store/review/guidelines/
- [IOS2] Kids-category rejections involving ad SDKs (anecdotal): https://developer.apple.com/forums/thread/133834, https://developer.apple.com/forums/thread/678312, https://discussions.unity.com/t/help-needed-app-rejection-due-to-guideline-1-3-safety-kids-category/949422
- [UR1] UniRig (SIGGRAPH 2025): https://arxiv.org/pdf/2504.12451 (licence seen only through a third party: https://www.skills.sh/akillness/jeo-skills/unirig)
- Claude pricing and features: the claude-api skill reference (cached 2026-10-06); Anthropic data retention: https://privacy.claude.com/en/articles/7996866
