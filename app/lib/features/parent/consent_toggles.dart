import 'package:flutter/material.dart';

import '../../data/app_settings.dart';

/// The four consent switches (SPEC §7). Parent-facing text (kanji is fine).
/// Server features are disabled while the backend is not configured.
class ConsentToggles extends StatelessWidget {
  const ConsentToggles({
    super.key,
    required this.value,
    required this.onChanged,
    required this.serverAvailable,
  });

  final ParentConsents value;
  final ValueChanged<ParentConsents> onChanged;
  final bool serverAvailable;

  static const _pending = '（現在準備中のため利用できません）\n';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _tile(
        key: 'cloudJudge',
        title: 'AI による絵の判定（クラウド判定）',
        body:
            '切り抜いた絵の画像をサーバーへ送り、AI（Anthropic 社の Claude）が'
            '名前の候補やわざの名前を考えます。画像は判定後すぐに破棄され、保存されません。',
        on: value.cloudJudge,
        enabled: serverAvailable,
        set: (v) => onChanged(value.copyWith(cloudJudge: v)),
      ),
      _tile(
        key: 'online',
        title: 'オンライン対戦',
        body:
            'Lv5 以上のキャラで、ほかのプレイヤーのキャラと対戦できます。登録時に'
            '絵と名前をサーバーで審査します。チャットはなく、自由に入力した文字が'
            'ほかの人に表示されることはありません。',
        on: value.online,
        enabled: serverAvailable,
        set: (v) => onChanged(value.copyWith(online: v)),
      ),
      _tile(
        key: 'ads',
        title: '広告の視聴',
        body:
            'バトルのあとに「どうがを みて けいけんち 2ばい」が表示されます。'
            '子ども向けに設定したリワード広告のみで、見る前に必ず注意書きが出ます。',
        on: value.ads,
        enabled: true,
        set: (v) => onChanged(value.copyWith(ads: v)),
      ),
      _tile(
        key: 'purchases',
        title: 'アプリ内課金',
        body:
            '「おうちのひと」画面のショップで購入できるようになります。'
            '購入の前には毎回この確認（保護者ゲート）が出ます。',
        on: value.purchases,
        enabled: true,
        set: (v) => onChanged(value.copyWith(purchases: v)),
      ),
    ],
  );

  Widget _tile({
    required String key,
    required String title,
    required String body,
    required bool on,
    required bool enabled,
    required ValueChanged<bool> set,
  }) => SwitchListTile(
    key: Key('consent-$key'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      enabled ? body : '$_pending$body',
      style: const TextStyle(fontSize: 14),
    ),
    value: on && enabled,
    onChanged: enabled ? set : null,
  );
}
