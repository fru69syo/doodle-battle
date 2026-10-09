# チーム体制

| チーム | 担当 | 主な担当ディレクトリ | ブランチ |
|---|---|---|---|
| PM / リード（統括） | 仕様、共通モデル、各ブランチのマージ、最終判断、ユーザーへの確認 | docs/, app/lib/domain/*.dart | main |
| Vision | 絵の切り抜き、特徴量、上手さ・のびのび度、ステータス生成 | app/lib/features/drawing_analysis/ | feat/vision |
| Battle | バトルエンジン、成長、CPU AI、共通バトル仕様とゴールデンテスト | app/lib/domain/battle/, shared/battle_spec/ | feat/battle |
| Backend | Firebase Functions（AI 判定・モデレーション・マッチング・サーバー側のバトル）、ルール | firebase/ | feat/backend |
| AR | ARCore での表示、glb の生成、フォールバック | app/lib/features/ar/, android/ のネイティブ部分 | feat/ar |
| App/UI | 画面、ナビゲーション、ローカル保存、保護者ゲート・設定、各機能の統合 | app/lib/core/, app/lib/features/* | feat/ui |
| Compliance | 広告・課金・ファミリーポリシー、プライバシーポリシー、データセーフティ | app/lib/features/monetization/, docs/ | feat/compliance |
| Release/QA | CI、署名、fastlane、ストア掲載情報、リリースチェックリスト | .github/, app/android/fastlane/, docs/RELEASE.md | feat/release |

## 進め方
1. 第1陣（並行）: Vision、Battle、Backend、AR。ロジックが中心で、お互いに依存しない
2. 第2陣: App/UI が第1陣の成果を統合する
3. 第3陣: Compliance と Release/QA。そのあと PM が全体を検証してリリース候補を作る

## ルール
- `docs/SPEC.md` を正とする。仕様を変えたいときは PM に報告して承認をもらう
- 自分の担当ディレクトリの外にあるファイルは原則として触らない。依存パッケージを足すときは報告する
- `flutter analyze` で警告ゼロ、`flutter test` がすべて通ることがマージの条件
