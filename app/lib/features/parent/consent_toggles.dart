import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../data/app_settings.dart';

/// The consent switches (SPEC §7 + opt-in crash reports). Parent-facing text (kanji is fine).
/// Server features are disabled while the backend is not configured.
class ConsentToggles extends StatelessWidget {
  const ConsentToggles({
    super.key,
    required this.value,
    required this.onChanged,
    required this.serverAvailable,
    this.crashReportsAvailable = false,
    this.noAdsPass = false,
    this.adsSupported = true,
    this.showPurchases = false,
  });

  /// In-app purchases are on in this build (off in v2.0, SPEC §10.2).
  final bool showPurchases;

  /// Rewarded ads exist in this build (Android only); otherwise the ads
  /// switch is not shown at all (the iPhone build is ad-free).
  final bool adsSupported;

  final ParentConsents value;
  final ValueChanged<ParentConsents> onChanged;
  final bool serverAvailable;

  /// Crashlytics needs Firebase; otherwise the switch shows 「準備中」.
  final bool crashReportsAvailable;

  /// こうこくなしパス is owned: no ads are shown, so the ads switch is
  /// replaced by an explanation (SPEC §11.4).
  final bool noAdsPass;

  static const _pending = '（現在準備中のため利用できません）\n';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _tile(
        key: 'cloudJudge',
        title: 'AI による絵の判定（クラウド判定）',
        body:
            '切り抜いた絵の画像をサーバーへ送り、AI（Anthropic 社の Claude）が'
            '名前の候補やわざの名前を考えます。画像は判定後すぐに破棄され、保存されません。'
            '絵が AI の学習に使われることはありません。',
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
      if (adsSupported)
        _tile(
          key: 'ads',
          title: '広告の視聴',
          body: noAdsPass
              ? 'こうこくなしパスを購入済みのため、広告は表示されません。'
                    'バトルのあとの経験値 2 倍は、広告なしで 1 日 $dailyAdBoostCap 回まで受け取れます。'
              : 'バトルのあとに「どうがを みて けいけんち 2ばい」が表示されます（1 日 $dailyAdBoostCap 回まで）。'
                    '子ども向けに設定したリワード広告のみで、見る前に必ず注意書きが出ます。',
          on: value.ads,
          enabled: !noAdsPass,
          set: (v) => onChanged(value.copyWith(ads: v)),
        ),
      // In-app purchases are switched off in v2.0 (SPEC §10.2).
      if (showPurchases)
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
      _tile(
        key: 'crashReports',
        title: 'ふぐあいの じょうほうを おくる',
        body:
            'アプリが異常終了したときなどに、原因を調べるための情報（端末の機種・'
            'OS のバージョン・エラーの内容・匿名のインストール ID）を Google の '
            'Firebase Crashlytics に送ります。絵や名前は送りません。'
            'オフにすると、まだ送っていない情報も削除します。',
        on: value.crashReports,
        enabled: crashReportsAvailable,
        set: (v) => onChanged(value.copyWith(crashReports: v)),
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
      enabled || key == 'ads' ? body : '$_pending$body',
      style: const TextStyle(fontSize: 14),
    ),
    value: on && enabled,
    onChanged: enabled ? set : null,
  );
}

/// 「えは AIの がくしゅうに つかいません」(SPEC §11.3) for the consent
/// screens: one hiragana line for the child, details for the parent.
class NoAiTrainingNotice extends StatelessWidget {
  const NoAiTrainingNotice({super.key});

  @override
  Widget build(BuildContext context) => const Card(
    key: Key('no-ai-training'),
    color: Color(0xFFE8F5E9),
    child: Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            'えは AIの がくしゅうに つかいません',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'お子さまの絵を AI の学習（トレーニング）に使うことはありません。'
            '当アプリも、クラウド判定を行う Anthropic 社も、送られた絵を学習に使いません。'
            '絵は AI の作品に作り替えず、お子さまが描いた線のままキャラクターになります。',
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    ),
  );
}
