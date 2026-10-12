# おえかきファイターズ (doodle-battle)

> 旧仮称「らくがきバトル」から改名しました（docs/archive/SPEC_v1.md §11.4）。リポジトリ名・Dart パッケージ名 `doodle_battle`・applicationId などの内部の識別子は変えていません。

子どもが描いた絵をキャラクターにして、リアルタイムのゲージ制バトルで戦わせ、育てるゲーム。子どもらしく元気に描いた絵ほど強くなる（内部の補正は画面に出さない: docs/SPEC.md §3）。紙の絵をカメラで撮るか、アプリ内のお絵かきツールで描く。

- 仕様: [docs/SPEC.md](docs/SPEC.md)（v2.0 の現行仕様。v1 の仕様は [docs/archive/SPEC_v1.md](docs/archive/SPEC_v1.md)）
- チーム体制: [docs/TEAM.md](docs/TEAM.md)
- 広告・課金・プライバシー（ファミリーポリシー対応）: [docs/COMPLIANCE.md](docs/COMPLIANCE.md)、ポリシーのページ: [site/](site/)
- サーバー（GCP）: [docs/LEARN_GCP.md](docs/LEARN_GCP.md)（オーナー向けの学習ガイド）、対戦サーバー [server/realtime/](server/realtime/)、構成 [infra/terraform/](infra/terraform/)、通信の決まり [docs/REALTIME_PROTOCOL.md](docs/REALTIME_PROTOCOL.md)

## 開発
```sh
cd app && flutter pub get && flutter test
```
