# らくがき→バトルキャラ化ゲーム（「上手いほどしょぼキャラ」補正）に関するゲームデザイン上のエビデンス

調査日: 2026-10-10。対象: 5〜12歳向け。注: 検索ツールの要約経由で得た情報が多く、一次文献（論文本文）を直接確認できていないものは本文中でその旨を記した。

## Q1. お絵かき駆動ゲーム（Drawn to Life / Scribblenauts / らくがきAR / Animated Drawings 等）の「子どもが好きな点」と「離脱要因」

### Takeaway
「自分の絵がゲーム内で動く」こと自体は強い初期フックとして一貫して高評価だが、その後に続くゲーム部分（プラットフォーム、ミニゲーム）が単調だと「描く部分は良いがゲームは凡庸」という評価に落ち着き、継続動機が弱くなる。認識精度・写真条件に関する定量的な離脱データは見つからなかった。

### Cited Findings
- Drawn to Life（DS, 2007）: Common Sense Media は7歳以上を推奨。テンプレート内にスタイラスで描いて色を塗ったものがゲームに組み込まれアニメーションする点を中心的フックとして紹介。雲の色を暗くすれば不穏に、明るい青にすれば楽しい雰囲気になるなど「子どもが世界の見た目と雰囲気を形作れる」ことを評価。子どもレビューは8歳以上 — [Common Sense Media: Drawn to Life](https://www.commonsensemedia.org/game-reviews/drawn-to-life)
- Drawn to Life: SpongeBob Edition について Common Sense Media は「ゲームプレイはせいぜい基本的だが、お絵かき機能が際立つ」と評価（子どもレビューは6歳以上） — [Common Sense Media: Drawn to Life SpongeBob](https://www.commonsensemedia.org/game-reviews/drawn-to-life-spongebob-squarepants-edition)
- Pocket Gamer（Kath Brice, 3/5）: 自分の絵が足場・武器・乗り物になるアイデアは「incredibly well」機能し、「自分の個性の刻印」が全体に残る満足感があると評価。一方「ゲームは常に次のプラットフォームステージに戻り、この要素が飽きを生む」、プラットフォーム部分は「基本的」で「ネットのフラッシュゲームのよう」、敵がすぐ復活するので無視しがち、「本当は低年齢層向けのゲーム」で経験あるゲーマーには物足りない、と批判 — [Pocket Gamer: Drawn to Life](https://www.pocketgamer.com/articles/004242/drawn-to-life/)
- Scribblenauts Showdown（対戦パーティ版）: 「ミニゲームの種類が限られパーティ形式がすぐ反復的になる」「数時間後にはやることがあまりない」、GameCentral は 3/10 で「ミニゲームが退屈で反復的、またはイライラする」と評価 — [OpenCritic: Scribblenauts Showdown Reviews](https://opencritic.com/game/5541/-/reviews)
- Scribblenauts Unlimited の Common Sense 子どもレビューは創造性・教育的価値に概ね肯定的だが、操作が時々扱いにくい点、不適切な単語入力に注意が必要な点が挙がる（Common Sense の AI 要約・少数レビューに基づく） — [Common Sense Media Kid Reviews: Scribblenauts Unlimited](https://www.commonsensemedia.org/game-reviews/scribblenauts-unlimited/user-reviews/child)
- らくがきAR（Whatever Inc.）: 2020年8月1日 iOS 配信、配信5日で46万DL、iPhone 有料総合で日本・中国・韓国など8か国・地域で1位。ノートやホワイトボードの絵をスキャンすると画面内で動き回り、タップでご飯をあげる・突っつくと弾き飛ばされる等のインタラクションがある — [マイナビニュース](https://news.mynavi.jp/article/20210708-1916126/); [Whatever: RakugakiAR](https://whatever.co/work/rakugakiar)
- らくがきAR は第24回文化庁メディア芸術祭エンターテインメント部門優秀賞。審査員が自分の子どもたちと片っ端から落書きをスキャンして遊んだ体験を記述 — [文化庁メディア芸術祭: らくがきAR](https://www.bunka.go.jp/j-mediaarts-festival/award/single/rakugakiar/index.html); [j-mediaarts.jp (英)](https://j-mediaarts.jp/en/award/single/rakugakiar/)
- らくがきAR は独自エンジン「HoneBorn」でスキャンした絵に自動で「骨」を付けて動かす。App Store レビューには美術教師の「必須アプリ」評価がある一方「スキャン中にクラッシュすることがある」という不具合報告もある — [AMT Lab review](https://amt-lab.org/reviews/2021/9/rakugakiar-bring-your-doodles-to-life); [App Store: RakugakiAR](https://apple.co/3FJHDIs)
- Meta Animated Drawings: 子どもの人物画のばらつきに頑健な自動アニメーション化システム。公開デモには約670万枚の画像がアップロードされ、約320万人が利用。当初1万枚収集目標に対し300万枚超が寄せられ、許諾付きで178,166枚の「Amateur Drawings Dataset」を公開（2023年4月にコードとともにオープンソース化） — [arXiv 2303.12741](https://arxiv.org/pdf/2303.12741v1); [Meta Newsroom 2021](https://about.fb.com/news/2021/12/using-ai-to-animate-childrens-drawings/); [InfoQ](https://www.infoq.com/news/2023/04/meta-animated-drawings/)

### Inferences
- 「自分の絵が動く」驚きは市場で実証済み（らくがきAR 46万DL/5日、Animated Drawings 320万人）であり、差別化要素としては弱い。差別化は「描いた後に何をするか（バトル・成長・収集）」の厚みで決まる可能性が高い。
- Drawn to Life / Scribblenauts Showdown の批判パターンから、バトル部分が単調（同じ操作の繰り返し）だと「描くのは楽しいがすぐ飽きる」評価になるリスクが高い。描き直し・追加パーツ描画などで「描く」行為をゲームループ中に繰り返し呼び戻す設計が望ましい。
- Drawn to Life は「テンプレート内に描く」方式で認識失敗を回避している。自由描画＋写真取り込み方式では認識失敗が体験を壊すリスクがあり、失敗時でも何らかのキャラが必ず生成されるフォールバックが重要と推測される。

### Gaps
- Draw a Stickman: EPIC、Crayon Physics Deluxe、Doodle God のレビュー・ポストモーテムは今回の調査範囲（ツール呼び出し上限）で確認できなかった。
- 写真撮影時の照明・影・紙の歪みによる認識失敗が離脱にどの程度効くかの定量データ、「絵が自分のものに見えない」ことへの不満を扱った一次資料は見つからなかった。Animated Drawings 論文本文は取得失敗（PDFサイズ超過）のため失敗モードの記述を確認できていない。
- GDC / Game Developer のお絵かきゲームのポストモーテムは未確認。

## Q2. 子どもの描画発達段階（Lowenfeld/Kellogg）、年齢差の公平性、絵を「評価」されることへの子どもの反応

### Takeaway
描画能力は年齢で系統的に変化し（なぐりがき期→前図式期→図式期→写実の芽生え）、8〜10歳頃には「写実的に上手く描く」ことへのこだわりが強まる。一方で、事前に評価されると知らされた状態では創造性が下がり、期待された報酬は絵を描く内発的動機を下げるという古典的研究があり、「上手さスコア」を子どもに可視化する設計には明確なリスクがある。

### Cited Findings
- Lowenfeld の段階: なぐりがき期（約2〜4歳、無秩序・縦線・円・命名の下位段階。命名期では子どもがなぐりがきに物語をつける）、前図式期（約3.5/4〜6/7歳、人や動物を示唆する円と線が現れ、図式が形成される）、図式期（約5/6〜9歳、一貫した記号と基底線、空と地面の分離）、写実の芽生え（約7〜9歳）、疑似写実期（約10〜13歳）。年齢幅は資料によって異なる — [UMN Duluth: Lowenfeld stages](https://www.d.umn.edu/artedu/lowenf.html); [The Art of Education: Stages of Drawing Reference Guide](https://uploads.theartofeducation.edu/2015/07/The-Stages-of-Drawing-Reference-Guide.pdf); [LibreTexts: Artistic Development](https://socialsci.libretexts.org/Courses/Irvine_Valley_College/Creative_Development_in_Young_Child_(HD131)/03%3A_Artistic_Development)
- Gardner/Winner（Harvard Project Zero）の「U字曲線」: 小学校期（8〜10歳頃）は描画のルール習得に没頭する「literal stage（字義的段階）」で、写実を目指し絵が慣習的になり大人から見て面白みが減る。美的魅力は児童期中期に落ち込み、思春期に（特に芸術家になる人で）再び上昇する — [Harvard Project Zero: Valuing Thinking in the Arts](https://pz.harvard.edu/sites/default/files/Valuing%20Thinking%20in%20the%20Arts.pdf)
- ただし Rotenberg, Jolley ら（2016）は、表現性スコアの素点は前思春期まで線形に上昇し、U字は写実描画能力で統計的に調整した場合にのみ現れると報告。U字モデルは西洋モダニズム様式への選好を反映しているとの批判もある — [Keele repository (Jolley et al.)](https://eprints.keele.ac.uk/1836/); [Staffordshire repository](https://eprints.staffs.ac.uk/2309)
- Amabile の実験（主にブランダイス大学、参加者は子どもまたは大人、コラージュ・俳句・短編等）: 「専門家が評価する」と事前に伝えられなかった参加者が最も創造的な作品を作った。評価は努力を促すが創造性には不十分（P. Gray による二次解説） — [Psychology Today (Peter Gray): Unsolicited Evaluation Is the Enemy of Creativity](https://www.psychologytoday.com/us/blog/freedom-learn/201210/unsolicited-evaluation-is-the-enemy-creativity?eml)
- 原典: Amabile, T. (1979) "Effects of external evaluation on artistic creativity", JPSP 37, 221–233（本文は未確認） — [Rider University PDF（参考文献として引用）](https://www.rider.edu/sites/default/files/2024-05/Gender%26Evaluation.pdf)
- Baer（1997）の8年生研究では、外発的制約下で女子の創造性は大きく低下したが男子は低下しなかった。Hennessey & Zbikowski（1993）は報酬の負の効果に対し子どもを「免疫化」できる場合があると示した — [Rider University PDF](https://www.rider.edu/sites/default/files/2024-05/Gender%26Motivation.pdf)
- Lepper, Greene & Nisbett（1973）: もともとマーカーで絵を描くのが好きな未就学児を対象に、「Good Player 賞状」を期待して描いた群は、2週間後の自由時間に描く時間が、予期せず賞状をもらった群・報酬なし群より有意に少なかった（アンダーマイニング／過正当化効果）。報酬は金銭ではなく象徴的な賞状。サンプル数は資料により51名等の記載差あり — [Greene et al. 1976 PDF (uowm.gr)](https://eclass.uowm.gr/modules/document/file.php/NURED262/%CE%A0%CE%A1%CE%A9%CE%A4%CE%9F%CE%A4%CE%A5%CE%A0%CE%91%20%CE%91%CE%A1%CE%98%CE%A1%CE%91/Greene%20et%20al%20overjustification%201976.pdf); [Psychology Notes HQ](https://www.psychologynoteshq.com/overjustification-effect/)
- 日本の実践知: 小学校低学年頃から「自分は絵が下手」と思い込む子が出てくるが、原因は「思い通りに描けないこと」。周囲から上手と褒められる子はますます描くのが好きになりやすい — [るるぶKids](https://kids.rurubu.jp/article/92022/)
- 「上手い絵を描かせなければ」という認識が描く楽しさを奪うとの問題提起、出来栄えより子ども自身に目を向ける姿勢が必要との指摘 — [山梨大学 資料](https://www.edu.yamanashi.ac.jp/wp-content/uploads/2022/05/cfdc1e632f3a511404a69161b0f0e36c.pdf)
- 表現を否定されることは人格全体を否定されるほどの衝撃になりうる、表現を認めることが自己肯定感を高めるうえで重要（保育園資料） — [くじら廿日市保育園 資料](https://kujira-hatsukaichi-hoikuen-hirsm.edumap.jp/wysiwyg/file/download/1/830)
- 図画工作科の第一の目的は上手に描く指導ではなく、楽しい・面白いと感じられる体験 — [テレメール 講義No.06765](https://telemail.jp/shingaku/academics-research/lecture/g006765)

### Inferences
- 「上手いほど弱い」補正は、実質的に年齢補正として働く（年長児ほど写実的に描けるため弱くなる）。兄弟間の公平性には寄与するが、逆に8〜12歳（literal stage、写実志向が強い時期）の子が「上手く描こうと頑張るほど損をする」と感じ、離脱または反発するリスクがある。
- Amabile／Lepper の知見からは、絵の「上手さ点数」を数値で子どもに見せること自体が創造性・内発的動機を下げうる。スコアは内部パラメータに留め、子どもには「元気さ」「勢い」「個性」などポジティブな属性名で返すのが安全と推測される。
- 「上手い＝弱い」を子どもに明示すると、「上手」という評価を負の結果と結びつけ、図工での褒め言葉と矛盾するメッセージになりうる。保護者・教育者から反発を受ける可能性がある（推測）。
- 年長児向けには、写実的な絵でも強くなれる別ルート（例: 細部の描き込み→特殊技、色数→属性など）を用意し、「上手さ」の方向性ごとに異なる強みを与える設計が公平性と動機の両面で有利と推測。

### Gaps
- Kellogg の基本形態（20種のなぐりがき等）の一次資料は確認できなかった。
- 「ゲーム内で絵を自動採点されること」に対する子どもの反応を直接扱った研究は見つからなかった。
- J-STAGE 上の日本の描画発達研究（年齢別の描画特徴の定量データ）は今回未取得。

## Q3. 子ども向けクリーチャーゲームの継続要因（図鑑・進化・共有・物理連動・ローカル対戦・デイリー報酬）とローカル vs オンライン対戦

### Takeaway
保護者はオンラインでの見知らぬ人との交流を強く懸念しており、親子・兄弟で一緒に遊ぶ（co-play）ことには家族コミュニケーション上の利点と子ども側の需要がある。継続要因としては、新コンテンツの定期投入が AR 系でも継続率を支えている事例がある。図鑑・進化・デイリー報酬の子ども向け効果を示す信頼できる定量データは今回見つからなかった。

### Cited Findings
- 米国のゲーマー保護者1,000人超の調査（WebPurify）で、最大の懸念はマルチプレイでの不適切なやり取り（41%）と見知らぬ人との交流（40%） — [WebPurify Multiplayer Family Report](https://www.webpurify.com/collateral/WebPurify_Multiplayer_Family_Report.pdf)
- 保護者1,000人調査で81%がオンラインゲームの安全性に何らかの懸念 — [Destructoid](https://www.destructoid.com/study-81-percent-parents-concerned-kids-safety-online-games/)
- 豪 eSafety Commissioner 報告（8〜17歳と保護者2,000人超）: 若者の94%がゲームに肯定的だが、子への利点を認める保護者は15%のみ。子ども（8〜12歳相当）の52%、ティーンの27%が保護者に一緒に遊んでほしいと回答（二次報道経由） — [The Echo / Cosmos](https://www.echo.net.au/2024/02/what-parents-just-dont-get-about-video-games/)
- CHI 2024 ワークショップ論文: 親が子と一緒に遊ぶと課金などの問題を話し合い境界を設定できるが、フィルタされないチャット等の害は親でも防ぎにくい — [arXiv 2602.23596](https://arxiv.org/pdf/2602.23596)
- 韓国の家族研究（質問紙76名、インタビュー14家族）: 家族の co-play は他の家族余暇よりインタラクティブなコミュニケーションを可能にする — [hrcak.srce.hr](https://hrcak.srce.hr/en/334800)
- Internet Matters（英）インフォグラフィック: 同じ部屋で一緒に遊ぶのを好む子23%、一人で遊ぶ37%、オンラインで他者と22%（サンプル・年次は未確認） — [Internet Matters Gaming Stats](https://www.internetmatters.org/wp-content/uploads/2019/07/Internet_Matters_GamingStatsInfographic.pdf)
- AR キッズコンテンツ Milo（Blippar）: 2週間ごとの新エピソードで、エピソード間継続率66%（ベンダー発表、非査読） — [Blippar: Milo](https://www.blippar.com/work/milo)
- Quiver（AR塗り絵）: 塗った紙をスキャンすると3Dで動く。作品を写真・動画でカメラロールに保存・共有可能。教師レビューで子どもが「魔法のページ」と呼ぶ。スキャン時に約3ドルのパック課金がある — [Common Sense Education: Quiver](https://www.commonsense.org/education/reviews/quiver-3d-coloring-app); [Gearbrain](https://www.gearbrain.com/-2514323764.html)
- Pokémon GO 初期の衰退要因として、事前に発表されていた交換機能等の未実装と、近隣プレイヤーへの依存が挙げられた — [Consumerist](https://consumerist.com/2016/08/23/has-pokemon-go-run-its-course); [Pocket Gamer.biz](https://www.pocketgamer.biz/pokemon-go-users-are-declining/)

### Inferences
- 5〜12歳・日本の家庭向けでは、「同じ部屋で兄弟・親子対戦」が保護者の安心感と子どもの需要の両方を満たす主軸となり得る。オンライン対戦は、チャットなし・フレンドコード限定などに制限しないと保護者の懸念（見知らぬ人41%/40%）に直撃する。
- Pokémon GO の交換機能未実装が衰退要因として挙がったことから、キャラ交換・見せ合い（共有）はクリーチャー系の継続に効く可能性がある（推測、直接データなし）。
- 自作キャラは「紙の原画」が物理的に存在するため、原画とキャラカードを並べて印刷・保存する等の物理連動は他社にない自然な強みになり得る（推測）。

### Gaps
- 図鑑・進化・デイリーログインボーナスが5〜12歳の継続率に与える効果の公開データ（ポケモン、妖怪ウォッチ等）は見つからなかった。
- 日本の保護者のオンライン対戦への意識調査（例: こども家庭庁・内閣府の青少年ネット利用調査）の該当数値は今回未取得。

## Q4. 「スキルペナルティ」的メカニクスの先例（ハンデ、ラバーバンド、ヘタウマ文化）と受け止められ方・ポジティブなフレーミング

### Takeaway
上位者を不利にする仕組み（マリオカートの青甲羅・ラバーバンド）は「ドラマと緊張を生む」と開発側が擁護する一方、「勝者への見える罰」「良い判断を阻害」と批判もある。日本には「一見下手だが味がある」ことを価値とするヘタウマの文化的土壌があり、ポジティブなフレーミングに使える。

### Cited Findings
- 青甲羅批判: ラバーバンドとして機能するが「良い判断を阻害し退屈なプレイスタイルを促す」、回避がほぼ不可能で先頭の努力を帳消しにする — [Law of Game Design: Theory: Rubber Bands](https://lawofgamedesign.com/2014/08/25/theory-rubber-bands/)
- 任天堂・矢吹氏: 青甲羅なしで試すと「何かが足りない」感じがした（公平性よりドラマ・緊張の価値） — [Business Insider](https://www.businessinsider.nl/mario-kart-blue-shell-2017-7)
- マリオカートのラバーバンドは個々の人間プレイヤーが近くのカートとの差を詰めるためのもので、全体を均す意図ではないとの分析。青甲羅は勝者への目に見える罰と感じられうる — [Vice/Broadly: The Blue Shell and Its Discontents](https://broadly.vice.com/en/article/epngxp/the-blue-shell-and-its-discontents-2)
- ラバーバンドはカジュアル層を含む幅広い層を遊ばせるための設計要件になりうる — [Game Developer: Rubber Banding as a Design Requirement](https://www.gamedeveloper.com/design/rubber-banding-as-a-design-requirement)
- ヘタウマ: 一見下手そうだが下手さが計算されていて真似できない、下手さが個性や味になっている表現。明確な定義はなく受け手の感性による。湯村輝彦（テリー・ジョンスン）の『ガロ』表紙、1980年の『情熱のペンギンごはん』（糸井重里原作）がブームの先駆け。渡辺和博、蛭子能収、根本敬、みうらじゅん、しりあがり寿らが系譜 — [artscape: ヘタうま](https://artscape.jp/artword/6733/)
- 英語版 Wikipedia は1970年代の『ガロ』を起点とするアンダーグラウンド漫画の潮流と位置づけ（起源時期の記述に差） — [Wikipedia: Heta-uma](https://en.wikipedia.org/wiki/Heta-uma)

### Inferences
- 「上手い→弱い」を罰として見せると青甲羅と同じ「勝者への見える罰」の不満を招く。逆に「ヘタウマ＝味がある＝強い」「勢いのある線にはパワーが宿る」など、子どもらしい特徴に"ボーナス"を与える形で提示すれば、同じ数値効果でも受け止めは大きく変わると推測（プロスペクト理論的なフレーミング効果、直接の子ども向け実証は未確認）。
- 「上手い絵」には弱体化ではなく別の価値（レア見た目、図鑑の特別枠、防御寄り特性、"職人"称号など）を与える非対称設計にすれば、年長児・保護者の「不公平」感を緩和できる。
- 公平性への配慮として、ローカル対戦時にハンデを明示的に選べる（親が自分にハンデをかける）方式は、隠れた補正よりも透明で親子対戦の文脈に合う（推測）。
- 「クソゲー」的ユーモア・"しょぼキャラ"の笑いは日本の大人には通じるが、5〜7歳児が自作キャラを「しょぼい」と言われて笑えるかは未検証。Q2の自己肯定感の観点から、子ども自身の絵に「しょぼ」というラベルを付けるのは避けるべきと推測。

### Gaps
- お絵かき上手さにペナルティを与える既存ゲームの具体例と、その子ども・保護者の反応データは見つからなかった。
- 子ども（5〜12歳）がハンデ・キャッチアップ機構をどう知覚するかの実証研究は見つからなかった。

## Q5. 子ども向けアプリにおける AR: 継続要因か一過性の「わぁ」か

### Takeaway
AR は初期の注目と拡散（らくがきAR 5日46万DL）を生む力は確認できるが、継続を示す独立したデータは乏しい。Pokémon GO も初期の急減が報告されており、継続は AR 自体よりも定期的な新コンテンツやソーシャル機能に依存していると見られる。

### Cited Findings
- らくがきAR は配信5日で46万DL、有料総合8か国・地域で1位 — [マイナビニュース](https://news.mynavi.jp/article/20210708-1916126/)
- Pokémon GO の DAU はピーク約4,500万（2016年7月）から8月中旬に約3,000万へ減少（Axiom/Apptopia 推計、Bloomberg 報道経由） — [Big Think](https://bigthink.com/the-future/why-the-pokemon-go-mania-may-be-settling-game-losses-10-million-daily-active-users/); [MCV UK](https://mcvuk.com/pokemon-go-has-lost-around-15m-daily-users/0171558)
- comScore 由来として、ピーク2,850万から2016年末に500万へ減少との報道もあるが二次報道のみで信頼度は低い — [Christian Post](https://christianpost.com/news/pokemon-go-latest-news-daily-users-drop-by-80-percent.html)
- 同時期の評論は、減少は大型ローンチ後の通常パターンであり衰退ではない、ローンチ以来約3.5億ドルの収益（App Annie）と指摘 — [Consumerist](https://consumerist.com/2016/08/23/has-pokemon-go-run-its-course)
- AR 学習ゲームの体系的レビュー: 67% の研究が使用直後にのみ成果を測定しており、長期効果を見た研究は約3分の1 — [arXiv 2111.08214](https://arxiv.org/pdf/2111.08214)
- 未就学児の AR 語彙学習研究: 4週間で大きな向上の後、2週間の休止で保持テストが17ポイント低下（単一群デザイン） — [Atatürk Univ. AVESIS](https://avesis.atauni.edu.tr/yayin/2e7bbe91-3ccd-45cb-941b-41fd4a2c2486/an-examination-of-vocabulary-learning-and-retention-levels-of-pre-school-children-using-augmented-reality-technology-in-english-language-learning)
- AR キッズ番組 Milo は2週間ごとの新エピソードでエピソード間継続率66%（ベンダー発表） — [Blippar: Milo](https://www.blippar.com/work/milo)
- Quiver は保存・共有（写真/動画）機能を備え、教育現場で好評 — [Common Sense Education: Quiver](https://www.commonsense.org/education/reviews/quiver-3d-coloring-app)

### Inferences
- AR は「初回の魔法体験」と「SNS 拡散・保護者の撮影動機」には有効だが、それ単体で継続を支える根拠は見つからない。AR は「自作キャラを現実の机の上で見せる/写真・動画を撮る」共有機能として位置づけ、継続はバトル・収集・定期コンテンツで担う方が妥当と推測。
- 子どもの AR 利用は端末を持ち続ける身体的負荷・保護者の見守りが必要（ARCore対応端末制限も含む）であり、コア体験を AR 必須にしない方が離脱リスクは低いと推測。

### Gaps
- らくがきAR の長期継続率（D7/D30）や子ども利用比率のデータは公開されていなかった。
- 子ども向けエンタメ AR アプリの「ノベルティ効果の減衰」を直接測った研究は見つからなかった（教育用途の短期学習効果研究が中心）。
