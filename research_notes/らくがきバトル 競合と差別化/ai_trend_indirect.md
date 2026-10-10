# 生成AI「らくがき→キャラ化」トレンド（2024–2026）と、日本の6–12歳のスクリーンタイムを奪い合う間接競合

調査日: 2026-10-10。各データの調査時期は本文に併記。数値は出典の記載どおりで、調査ごとに対象・設問が違うため単純比較はできない。

---

## Q1. 生成AIで「スケッチ／子どもの絵」をキャラ・3D・アニメ・物語に変えるアプリ・サービス（2024–2026）：人気、価格、批判、規制

### Takeaway
「子どもの絵を動かす／清書する」機能は、Meta Animated Drawings（無料・OSS）、Apple Image Wand（OS標準・無料）、小規模な子ども向けAIアプリ（無料〜月5ドル程度）、Sora 2系の動画化サービスまで広がり、すでにコモディティになりつつある。一方で、子ども向けAIアプリには児童データ保護の違反事例があり、Google Playは生成AIアプリにアプリ内通報機能を義務づけている。そのため「描いた絵をそのまま使い、AIは判定・補助にとどめる」設計と、データを最小限にすることが差別化と規約順守の両方につながる。

### Cited Findings
**主要なサービス・機能**
- Meta Animated Drawings：絵の人型を検出し、骨格を自動で付けて（リギング）、既存のモーションを当てて動かす。Web版は無料で、技術はGitHubでオープンソース化されている。人型の絵に最も向く — [mybesh.com](https://mybesh.com/tool/animated-drawings)
- Meta Animated Drawingsは2023年4月にオープンソース化され、約18万枚の絵のデータセットとアニメーション処理の一式（パイプライン）を公開した（Web版デモは2021年公開）— [Ben's Bites](https://news.bensbites.com/posts/562-meta-open-sources-ai-project-animated-drawings-which-turns-doodles-into-animations-with-a-dataset-of-nearly-180k-drawings-after-releasing-a-web-tool-in-2021); [Voicebot.ai](https://voicebot.ai/2023/04/19/meta-teaches-doodles-to-dance-with-open-source-generative-ai-project/)
- デモ公開から数か月で、ユーザーが学習利用を許可した画像は160万枚を超えた。デモのモーションは32種類（ダンス、ジャンプ、歩き、おもしろ系）— [Analytics Vidhya](https://analyticsvidhya.com/blog/2023/04/bring-doodles-to-life-meta-open-sources-ai-model)
- リポジトリはアーカイブ済みで保守終了との情報があるが、出典は信頼度の低いディレクトリサイトで、GitHubでの確認はできていない — [neura.market](https://neura.market/ai-tools-directory/animation/animated-drawings-by-meta)
- Apple Image Wand（iOS/iPadOS 18.2以降、Apple Intelligence）：メモアプリ内のスケッチを丸で囲み、説明文を足すと画像を生成する。スタイルはスケッチ、イラスト、アニメーションの3種。処理は端末内で完結する — [MacRumors](https://macrumors.com/guide/image-wand); [Create with Swift](https://createwithswift.com/exploring-apple-intelligence-image-generation)
- Image Wandの制約：メモ内で描いたスケッチしか入力にできず、写真やカメラ画像は使えない。人物は生成しない。開発者向けAPI（PencilKit）は未提供。レビューでは「スケッチより説明文のほうが重く反映される」との指摘がある — [Create with Swift](https://createwithswift.com/exploring-apple-intelligence-image-generation); [Counterpoint](https://www.counterpointresearch.com/insight/post-insight-reviews-apple-intelligence-part-2-ondevice-ai-creativity-image-playground-genmoji-photo-editing-tools)
- Higgsfield Sketch-to-Video（2025年10月、Sora 2ベース）：クレヨンやマーカーの絵を、音付きの1080pアニメに変換する。プロンプトは不要 — [Higgsfield](https://higgsfield.ai/blog/Sketch-to-Video-Cartoons)
- 子ども向けの小規模アプリが相次いで登場している。KidsAI（6〜13歳向け。手描きを着色し短い動画化）、Drawings Alive（スターター月額5ドル。6秒アニメ）、Drawing to Animation（iPad、無料）、Noodle: Animate your Doodles（iOS無料、2025年9月更新）、Draw to Life: AI Art for Kids（絵本・動画化、保護者ダッシュボード、広告なし）、Draw to Create AI（2025年9月公開、静止画）— [Educational App Store](https://www.educationalappstore.com/app/kidsai); [G2](https://ai.g2.com/marketplace/tools/drawings-alive); [App Store](https://apps.apple.com/us/app/id6745140927); [AppsHunter Noodle](https://appshunter.io/ios/app/noodle-animate-your-doodles/id6499508227); [AppsHunter Draw to Life](https://appshunter.io/ios/app/draw-to-life-ai-art-for-kids/id6752760587); [AppGoblin](https://appgoblin.info/apps/6752018138)
- 日本発の先行事例「らくがきAR」（2020年8月1日配信、Whatever）：ノートやホワイトボードに描いた絵をスキャンするとAR空間で歩き回り、餌やりやつつくこともできる。配信5日で46万ダウンロードを超え、8つの国・地域でiPhone有料アプリ総合1位。Android版は2020年11月24日に配信 — [Whatever](https://whatever.co/work/rakugakiar); [文化庁メディア芸術祭](https://www.bunka.go.jp/j-mediaarts-festival/award/single/rakugakiar/index.html); [マイナビニュース](https://news.mynavi.jp/article/20210708-1916126/)
- 文化庁メディア芸術祭のエンターテインメント部門で優秀賞を受賞 — [文化庁](https://www.bunka.go.jp/j-mediaarts-festival/award/single/rakugakiar/index.html)
- 日本語で探した範囲では「子どもの絵をAIでキャラ化して動かす」ことに特化した国内アプリは見つからなかった。見つかったのは、写真をアニメ風にする、またはプロンプトからイラストを作るアプリ（例：Nekomimi.AI、評価4.5・104件）が中心 — [App Store Nekomimi.AI](https://apps.apple.com/jp/app/id6480199306)

**AIキャラクターが日本の小学生文化にすでに入り込んでいる例**
- 「イタリアンブレインロット」（生成AIで作ったキャラにイタリア語風の名前を付けたモンスター群）は、小学館の2025年小学生年間トレンドで低学年女子の流行語1位 — [マイナビニュース](https://news.mynavi.jp/article/20251126-3720787/); [東洋経済オンライン](https://toyokeizai.net/articles/-/928326?display=b)
- キャラ数は2025年10月時点で100を超える。AIで誰でも新キャラを作れることが、拡散が速い理由と分析されている — [REAL SOUND](https://realsound.jp/tech/2025/10/post-2190787.html)
- KADOKAWAが図鑑を2026年4月1日に発売するなど、子ども向けの関連書籍が相次いでいる — [KADOKAWA](https://www.kadokawa.co.jp/product/322511000759/)
- 札幌市の小学校教諭は、ストーリー性が乏しいとして「本当に大流行？」と疑問を示している — [札幌市立小学校資料](https://www16.sapporo-c.ed.jp/wako-e/attach/get2/3241/0)

**批判・リスク**
- KidGeni（子ども向けAIアート）：2024年8月、米国の自主規制機関CARUが、保護者の同意なしに子どものデータを集めた、プライバシーポリシーなしで公開した、AI学習を行う第三者に子どものデータを共有したことを開示しなかった、としてCOPPA違反と判断した。KidGeniは是正に同意したが、判断そのものには異議を示した — [aitoolsforkids.com](https://aitoolsforkids.com/ai-tools/kidgeni)（二次情報。CARUの原文は未確認）
- AIモデルは大量のユーザーデータを処理し、子どもが理解しない形で使われうる。主要なチャットボットが13歳以上を利用条件にしている一因は児童オンラインプライバシー規制、との指摘がある。生成AIへの過度な依存が批判的思考や問題解決力を損なう懸念もある — [Qustodio](https://www.qustodio.com/en/blog/ai-for-kids/)
- 「AIが描いた絵はもう子どもの絵ではない」という懸念への対応として、テキストから画像を作るのではなく、子どもの絵を着色・動画化する方式で「本人の想像力の所有感」を残す、と打ち出すアプリがある（開発者側の主張）— [Educational App Store KidsAI](https://www.educationalappstore.com/app/kidsai)
- 「処理は全部端末内で、データを集めない」と打ち出す子ども向けAIお絵かきアプリもある（開発者の主張で、監査はされていない）— [App Store Kids Art Studio](https://apps.apple.com/us/app/-/id6756487842)

**プラットフォームと日本の規制**
- Google Play「AI生成コンテンツ」ポリシー：AIでコンテンツを生成するアプリは既存の開発者ポリシーに従い、児童搾取などの制限コンテンツの生成を防ぐ必要がある。アプリを離れずに不適切な出力を通報・フラグできる機能が必須で、その通報をフィルタリングやモデレーションの改善に使うことが求められる — [Play Console Help: AI-Generated Content](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en); [Android Developers Blog 2023/10](https://android-developers.googleblog.com/2023/10/announcing-policy-updates-to-support-app-quality-on-google-play.html)
- Familiesポリシー：13歳未満が主な対象、または子どもを含む混合対象のアプリは要件を守る必要がある。子どもがアクセスできるコンテンツは子どもにふさわしいものであること。子ども向けサービスでの利用を自己認証したSDKだけを使うこと。混合対象では、中立的な年齢確認の後ろに置く場合を除き、未承認SDKは使えない。対象年齢の申告を偽ると削除や停止の対象になる — [Play Console Help 9893335](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en); [Play Console Help 9867159](https://support.google.com/googleplay/android-developer/answer/9867159)
- 二次情報では、2025年にGoogle PlayがAI生成コンテンツを独立した規制領域に整理し、生成が中心機能なら全面適用、補助機能なら一般ポリシーで足りる、とされている。プロンプト操作への対策と、テスト内容の文書化（Googleが提出を求める場合がある）も挙げられている — [Revera Legal](https://revera.legal/en/info-centr/news-and-analytical-materials/2114-ii-v-mobilnyx-prilozheniyax-trebovaniya-google-play/amp/)（Googleの原文との突き合わせは未了）
- 文部科学省「初等中等教育段階における生成AIの利活用に関するガイドライン（Ver.2.0）」は2024年12月26日公表。学校の文書では「年齢によって保護者の同意が必要な生成AIもある。利用規約を確認し守ること」と運用されている — [文科省資料](https://www.mext.go.jp/zyoukatsu/ai/contents/2025/archive/20250729_01.pdf); [愛知県立高校 資料](https://toyohashihigashi-h.aichi-c.ed.jp/cms/wp-content/uploads/2025/04/e8f66f767c0e20cdaa808d9cedf616d8.pdf)

### Inferences
- 「絵が動く」「絵が清書される」だけでは、無料のOS標準機能（Image Wand）や無料・OSSのツール（Meta）と横並びになる。価値の中心を、描いた絵の特徴がそのまま強さや技になる「ゲーム性」と、バトルという遊びの循環に置く必要がある。
- イタリアンブレインロットの流行から、日本の小学生はAI由来のキャラに抵抗が小さく、「変なキャラを図鑑で集める」ことに強い需要があると推測できる。一方で教育現場には懐疑的な見方もある。保護者向けには「AIが作ったキャラ」ではなく「子どもが描いたキャラ」と打ち出すほうが受け入れられやすい可能性が高い。
- Image Wandが「スケッチより説明文が優先される」と評されていることは、「絵が上手くなくても描いた形が尊重される」設計（絵を描き替えない、描いた形を残すなど）の差別化ポイントの裏付けになる。
- Android優先で画像生成やAI判定を組み込む場合、AI生成コンテンツポリシー（アプリ内通報）とFamiliesポリシー（承認済みSDK、データの最小化）の両方に当たる可能性が高い。KidGeniのように、子どもの絵をAI学習に流用したと受け取られることが最大のリスクになる。

### Gaps
- ChatGPTの画像生成（2025年のジブリ風ブームなど）、Gemini / Pixel Studio、Canvaなど、大手の「スケッチ→画像」機能の詳細、利用者数、子どもの利用状況は、今回の検索範囲では一次情報を確認できなかった。
- 子ども向けAIお絵かきアプリ（KidsAI、Draw to Lifeなど）のダウンロード数や売上は見つからなかった。小規模なアプリが多いと思われる。
- らくがきARの現在の累計ダウンロード数と価格は未確認。
- Google PlayがFamilies対象アプリの生成AIについて特別な追加要件を定めているかは、公式ページで確認できなかった。
- こども家庭庁や個人情報保護委員会による、子ども向けアプリの生成AIに特化したガイドラインは見つからなかった。
- 「AIが描くと子どもの絵ではなくなる」という論点の、学術的な実証研究（2024–2026年）は見つからなかった。

---

## Q2. 日本の間接競合：6–12歳がよく遊ぶゲーム・アプリ（お絵かき、収集・バトル、創作系）

### Takeaway
日本の小学生が「いま一番遊んでいるゲーム」は、マインクラフトが圧倒的1位（2026年6月で31.8%）で、ロブロックスが前年比8倍強の12.7%で2位に急上昇した。「戦う」ゲームから「つくる・つながる」ゲームへの移行がはっきりしている。ポケモン系は複数タイトルに票が分かれ、それぞれ1〜4%台。男子の欲しいもの上位にはベイブレードX、ポケモンカード、デュエル・マスターズなどの実物の収集・対戦玩具が並ぶ。

### Cited Findings
- ゲムトレ「ゲームに関するアンケート調査2026」（2026年6月、全国の小学生367人、Web調査）の「いま一番遊んでいるゲーム」：1位マインクラフト31.8%、2位ロブロックス12.7%、3位マリオカート6.9%、4位スプラトゥーン6.1%、5位フォートナイト4.9%、6位スマブラ4.3%、7位ぽこ あ ポケモン3.8%、8位トモダチコレクション2.9%、9位あつまれ どうぶつの森2.9%、10位Pokémon LEGENDS Z-A 1.9%、11位マリオパーティ1.6%、12位桃太郎電鉄1.3%、13位にゃんこ大戦争0.8%、14位カービィのエアライダー0.8%、その他21タイトル16.9% — [PR TIMES（ゲムトレ）](https://prtimes.jp/main/html/rd/p/000000030.000056150.html)
- 同調査でロブロックスは前年の1.5%（8位）から12.7%（2位）に上がった。マインクラフトは2022年以降首位を維持。2021年に1位だったフォートナイト（22.3%）は2026年に5位（4.9%）まで下がった — [PR TIMES](https://prtimes.jp/main/html/rd/p/000000030.000056150.html); [Game*Spark「小学生のゲーム、“戦う”から“つくる・つながる”へ」](https://www.gamespark.jp/release/prtimes/20260629/296999.html)
- 2024年5月のゲムトレ調査でもマインクラフトが29.35%で最多 — [Web担当者Forum 2024/06](https://webtan.impress.co.jp/n/2024/06/11/47149)。2025年の同調査でもマインクラフトが1位、ゲーム実況はHikakinGamesが6年連続1位でシェア4割 — [GameBusiness.jp 2025/09](https://www.gamebusiness.jp/article/2025/09/19/25088.html)
- ゲーム実況YouTuber（2026年）：1位HikakinGames 29.6%（7年連続）、2位まいぜんシスターズ8.1%、3位ちろぴの7.1% — [さきがけ（共同配信）](https://www.sakigake.jp/news/article/20260702OR0139/)（記事は現在リンク切れ）; [PR TIMES](https://prtimes.jp/main/html/rd/p/000000030.000056150.html)
- 小学館「2025年小学生年間トレンド」（2025年4月15日〜11月13日、ちゃお・ぷっちぐみ・コロコロ読者とその家族。サンプル数の記載なし）
  - 女子の「一番遊んでいるゲーム」：1位あつまれ どうぶつの森、2位マインクラフト、5位ロブロックス
  - 男子の「ほしいゲーム」：1位ドンキーコング バナンザ、2位マリオカート ワールド、5位スーパー マリオパーティ ジャンボリー
  - マインクラフトは男女とも上位5位以内
  - 男子の欲しいもの：1位ベイブレードX、4位ポケモンカード、5位デュエル・マスターズ。女子の欲しいもの3位はひみつのアイプリのアイプリカード
  - 女子の趣味に「絵を描く」が入る
  — [マイナビニュース](https://news.mynavi.jp/article/20251126-3720787/)
- ポケモンフレンズ（2025年7月22日、iOS/Android/Switch）は「シンクシンク」の問題をもとにした知育パズルで、1日の遊びすぎを防ぐ回数制限を保護者が設定できる — [Game*Spark](https://www.gamespark.jp/article/2025/07/22/155275.html); [ポケモン社リリース](https://corporate.pokemon.co.jp/PostImages/pokemon_pressreleases_20250829.pdf)
- Pokémon TCG Pocket（2024年10月30日配信）は世界で累計1.5億ダウンロード超（2025年10月時点）。2025年2月に1億DLと累計売上5億ドル（AppMagic推計）を超えた — [PocketGamer.biz 150M](https://www.pocketgamer.biz/pokmon-tcg-pocket-surpasses-150m-downloads-in-under-a-year); [PocketGamer.biz 100M](https://www.pocketgamer.biz/pokmon-tcg-pocket-surpasses-100-million-downloads)
- バンダイこどもアンケート（2018年、Vol.243）：小学生の遊びの1位は遊具・鬼ごっこ・かくれんぼだが、小5〜6のころに人気の遊びが外遊びから「ゲーム」「スマートフォン」に移る — [バンダイ](https://www.bandai.co.jp/kodomo/pdf/question243.pdf)（古いデータ）

### Inferences
- 直接の時間の奪い合い相手は、マインクラフト、ロブロックス（ともに創作・共有・ユーザー生成コンテンツ）とSwitchのパーティー・対戦系（マリカ、スプラ、スマブラ）。「自分で作ったものが動く・戦う」という価値は、マイクラやロブロックスとかなり重なる。「描くだけで作れる」という手軽さと、「紙と鉛筆」という入口の低さで差別化するのが有効と考えられる。
- 「戦う」ゲームの人気は下がっているが、ベイブレードX、デュエマ、ポケカなどの実物の対戦・収集玩具は男子の欲しいもの上位にある。友達と見せ合う・対戦する遊びの需要は強い。自分の絵を見せ合い、学校で話題にできることが鍵になる。
- 女子はあつ森、トモコレ、アイプリ、絵を描く趣味など「作る・着せ替える・集める」志向が強い。バトルだけを打ち出すと、女子の取り込みを逃す可能性がある。
- ポケモンフレンズ型の「保護者が遊ぶ回数を制限できる」機能は、大手がすでに用意している安心の基準になりつつある。

### Gaps
- 日本の子ども向けお絵かき・ぬりえアプリ（例：「こどもお絵かき」系、ぬりえ系、Toca Boca、YouTube Kids）の利用率やランキングは、調査データを見つけられなかった。アプリストアのランキングも未取得。
- ポケモンGO、妖怪ウォッチ、たまごっち、デュエル・マスターズ プレイスなどの、6〜12歳の利用率は信頼できる調査が見つからなかった。
- Benesseの子どものゲーム・メディア利用調査（2024〜2026）は未取得。
- ゲムトレ調査は367人と小規模で、主催はカヤック（ゲームコーチング事業）のグループ会社。小学館調査は雑誌読者が対象で、偏りがありうる。
- ゲムトレ2026には、遊んでいる端末（Switch、スマホなど）の内訳は掲載されていなかった。

---

## Q3. 日本の6–12歳はスマホ・タブレットで何を、どれだけ、どの端末で使うか（Android/iOS比率を含む）

### Takeaway
こども家庭庁の令和6年度調査では、小学生（10歳以上）の97.2%がネットを使い、平日平均は約3時間44分。利用内容の上位は動画視聴（89.7%）とゲーム（86.6%）。6〜9歳でも91.4%が利用し、スマホは主に親と共用だが、10歳で「子ども専用」が65%を超える。スマホのOSは、日本全体では2025年にAndroidがiPhoneをわずかに上回った（51.4%対48.3%）。ただし子ども・若年層はiPhone比率が高く、子ども端末ではiPhone 40%、Android 34%という調査がある。Android優先は、最初は親のお下がり端末や格安SIM層に当たることになる。

### Cited Findings
**こども家庭庁「令和6年度 青少年のインターネット利用環境実態調査」（2025年3月公表）** — [調査結果（概要）PDF](https://www.cfa.go.jp/assets/contents/node/basic_page/field_ref_resources/9a55b57d-cd9d-4cf6-8ed4-3da8efa12d63/0a26134c/20250328_policies_youth-kankyou_internet_research_results-etc_16.pdf)
- 対象は10〜17歳の青少年5,000人とその保護者5,000人、0〜9歳の子どもの保護者3,000人。
- 小学生（10歳以上）の97.2%がネットを利用。青少年全体の利用機器は、スマホ75.4%、GIGA端末72.6%、ゲーム機66.5%、テレビ64.2%、自宅のPC・タブレット44.9%。
- 低年齢層（0〜9歳）の78.5%がネットを利用し、小学生（6〜9歳）では91.4%。利用機器の上位はテレビ57.1%、自宅のPC・タブレット40.7%、ゲーム機35.8%。
- 利用内容：小学生（10歳以上）は動画を見る89.7%、ゲームをする86.6%、勉強73.9%。低年齢層全体は動画93.9%、ゲーム63.2%、勉強42.7%。表から読み取ると、小学生（6〜9歳）は動画92.1%、ゲーム79.6%（PDF本文抽出の列対応による読み取り）。
- 専用か共用か：スマホを使う小学生（10歳以上）の72.0%が子ども専用。低年齢層のスマホは72.7%が親と共用。年齢別では10歳で専用と共用が逆転し、専用が65.7%（9歳は40.6%）。契約していないスマホ（お下がりなど）は12歳で専用が50%を超える。
- 平日1日の平均ネット利用時間（全機器の合計）：小学生（10歳以上）約3時間44分（R5は約3時間46分、R4は約3時間34分）、低年齢層約2時間9分。目的別では趣味・娯楽が最多。
- 令和7年度の速報（2026年2月公表）では、小学生（6〜9歳）の91.0%がネットを利用し、ゲーム機は32.5%と報じられている — [令和7年度 速報PDF](https://www.cfa.go.jp/assets/contents/node/basic_page/field_ref_resources/9a55b57d-cd9d-4cf6-8ed4-3da8efa12d63/23fcf9bc/20260226_policies_youth-kankyou_internet_research_results-etc_20.pdf)（検索結果の抜粋による。本文は未精読）

**スマホの所有（モバイル社会研究所 / NTTドコモ）**
- 2025年11月、全国の小中学生と親1,200組を調査（2026年1月発表）。スマホを持ち始める平均年齢は10.2歳（男子10.4歳、女子9.9歳）で、女子が10歳を下回ったのは2018年の調査開始以来初めて。小5で所有率が過半数、中1で8割超 — [GameBusiness.jp](https://www.gamebusiness.jp/article/2026/01/29/26094.html)
- 2024年11月調査では小学高学年の所有率が52%で初めて半数を超えた。2023年11月調査では高学年4割超、6年生は65% — [J-CAST 2025/02](https://www.j-cast.com/2025/02/05501308.html?p=all); [J-CAST 2024/02](https://www.j-cast.com/2024/02/02477457.html?p=all)

**OS比率**
- ALL CONNECT「子どものスマホ利用実態調査」（2025年12月3日〜17日、小中学生の保護者300人）：子どもの端末はiPhone 40.0%、Android 34.33%、キッズ携帯15.0%。回線は全学年で格安SIMが過半数（大手キャリアの約1.4倍）。スマホ所有率は低学年50.4%、高学年84.42%、中学生96.94%（サンプルが小さく、所有率はモバイル社会研究所より大幅に高い点に注意）。保護者の不安はSNS 40.0%、依存29.33%、ゲーム12.67%、課金10.67% — [Web担当者Forum](https://webtan.impress.co.jp/n/2026/01/09/51957)
- 東京都の調査（2023年3月公表、都内の小学生〜高校生）ではiOSが61.8%で、学年が上がるほどiPhone比率が高い。MMD研究所の2024年調査では10代男性の64.8%、10代女性の80.2%がiPhone — [Financial Field](https://financial-field.com/living/entry-500429)（二次引用）
- MMD研究所（2025年9月調査）：メイン端末のOSはAndroid 51.4%、iPhone 48.3%で、Androidが逆転した。iPhoneは10〜20代女性と20代男性で多く、Androidは60代で多い。Androidの機種ではAQUOSが25.7%で最多 — [Web担当者Forum 2025/10](https://webtan.impress.co.jp/n/2025/10/28/50297)
- 2026年8月の調査でAndroid 54.1%、iPhone 45.6%という報道もあるが、検索結果の要約のみで原典は未確認 — [Impress Watch](https://www.watch.impress.co.jp/docs/news/2141787.html)（要確認）
- 子どもがiPhoneを欲しがる理由（周りが持っている、など）を取材した記事 — [ITmedia 2025/05](https://www.itmedia.co.jp/news/article/2505/30/1250530102/)

### Inferences
- 6〜9歳は「親と共用のスマホ」「自宅のタブレット」「ゲーム機」でネットを使い、10歳を境に自分専用のスマホに移る。対象の5〜12歳のうち低学年は、保護者の端末やお下がり端末で遊ぶ前提で、保護者の同意と端末の共用を想定した設計が必要になる。
- 日本の子ども・若年層はiPhone寄り（子ども端末でiPhone 40%対Android 34%、10代は6〜8割がiPhone）。Android優先は、子ども専用スマホの主流層の半分以上を当初取りこぼす可能性がある。逆に、格安SIM、お下がり、Androidタブレット（Fireタブレット含む）の家庭には届きやすい。iOS版を早期に用意できるかは、市場拡大の重要な論点。
- 小学生の平日ネット利用は約3.7時間で、動画とゲームが中心。新しいアプリは、YouTube（ゲーム実況）、マイクラ、ロブロックスから時間を奪う必要がある。実況・動画映えする「変なキャラ同士のバトル」は、ゲーム実況文化（HikakinGamesなど）と相性が良い可能性がある。

### Gaps
- 6〜12歳に限ったスマホゲームの1日あたり利用時間（ゲームだけの時間）は、こども家庭庁の概要版に記載がなく、本編を見る必要がある。
- モバイル社会研究所の、子ども端末のiPhone/Android比率は確認できなかった（公式レポートの本文未確認）。
- 子どもが主に使うタブレット（iPad、Fire、Android）の比率、およびSwitchとスマホの利用時間比較について、信頼できる全国データは見つからなかった。
- 令和7年度調査（速報）の小学生の利用時間・利用内容の詳細は未精読。
