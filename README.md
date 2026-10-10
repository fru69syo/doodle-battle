# おえかきファイターズ (doodle-battle)

> 旧仮称「らくがきバトル」から改名しました（docs/SPEC.md §11.4）。リポジトリ名・Dart パッケージ名 `doodle_battle`・applicationId などの内部の識別子は変えていません。

子どもの描いた絵を読み込んでキャラクターにして戦うゲーム。上手さではなく、子どもらしい線や色がそのままキャラの個性になる（内部の補正は見せない: docs/SPEC.md §11.1）。紙に手で描いた絵だけを受け付ける（docs/TRUST.md）。

- 仕様: [docs/SPEC.md](docs/SPEC.md)
- チーム体制: [docs/TEAM.md](docs/TEAM.md)
- 広告・課金・プライバシー（ファミリーポリシー対応）: [docs/COMPLIANCE.md](docs/COMPLIANCE.md)、ポリシーのページ: [site/](site/)

## 開発
```sh
cd app && flutter pub get && flutter test
```
