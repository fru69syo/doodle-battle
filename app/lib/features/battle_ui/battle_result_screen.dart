import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../data/app_state.dart';
import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../monetization/rewarded_ad_button.dart';
import '../online/online_badges.dart';
import '../video_export/video_export_entry.dart';
import '../collection/xp_bar.dart';
import 'battle_outcome.dart';

/// Platform of this build for the rewarded-ad rule (Android only, SPEC
/// §10.2). Overridable in tests.
final appPlatformProvider = Provider<AppPlatform>((ref) {
  if (kIsWeb) return AppPlatform.other;
  if (Platform.isAndroid) return AppPlatform.android;
  if (Platform.isIOS) return AppPlatform.ios;
  return AppPlatform.other;
});

/// After a battle: win / lose, stars, XP, level up, new moves, しんか.
class BattleResultScreen extends ConsumerStatefulWidget {
  const BattleResultScreen({super.key, required this.outcome});
  final BattleOutcome outcome;

  @override
  ConsumerState<BattleResultScreen> createState() => _BattleResultScreenState();
}

class _BattleResultScreenState extends ConsumerState<BattleResultScreen> {
  late BattleOutcome _o = widget.outcome;

  Future<void> _onAdReward() async {
    final o = await ref.read(battleRewardsProvider).applyAdBonus(_o);
    if (mounted) setState(() => _o = o);
  }

  bool _adOffered() {
    if (_o.online || _o.stage == null || _o.adBonusXp <= 0) return false;
    if (!kAdsEnabledOnAndroid) return false;
    // The button itself checks the parent's consent and today's cap.
    return adBoostAvailable(
      platform: ref.watch(appPlatformProvider),
      parentAllowsAds: true,
      usedToday: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(characterByIdProvider(_o.characterId));
    final title = _o.aborted
        ? 'またあそぼう'
        : _o.won
        ? 'かった！'
        : 'まけちゃった…';
    return Scaffold(
      appBar: AppBar(
        title: const Text('けっか'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              _o.won ? Icons.emoji_events : Icons.sentiment_satisfied,
              size: 64,
              color: _o.won ? AppColors.gold : AppColors.secondary,
            ),
            Text(
              title,
              key: const Key('result-title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: _o.won ? AppColors.primary : AppColors.secondary,
              ),
            ),
            if (_o.won && _o.stage != null)
              Row(
                key: const Key('result-stars'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < 3; k++)
                    Icon(
                      k < _o.stars ? Icons.star : Icons.star_border,
                      size: 52,
                      color: k < _o.stars ? AppColors.gold : AppColors.disabled,
                    ),
                ],
              ),
            if (c != null)
              Center(child: CharacterPicture(character: c, size: 180)),
            const SizedBox(height: 12),
            if (!_o.aborted)
              Text(
                'けいけんち +${_o.xpGained}',
                key: const Key('result-xp'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (c != null && !_o.aborted) XpBar(character: c),
            if (_o.online && _o.badge != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: BadgeChip(
                    key: const Key('result-badge'),
                    badge: _o.badge!,
                    big: _o.badgeUp,
                  ),
                ),
              ),
            if (_o.badgeUp)
              const Celebrate(
                key: Key('result-badge-up'),
                icon: Icons.military_tech,
                text: 'あたらしい バッジ！',
              ),
            if (_o.leveledUp)
              Celebrate(
                key: const Key('result-levelup'),
                icon: Icons.arrow_upward,
                text: 'レベルアップ！ Lv${_o.levelAfter}',
              ),
            if (c != null)
              for (final slot in _o.newSlots) _NewMove(c: c, slot: slot),
            for (final e in _o.evolutions)
              Celebrate(
                key: Key('result-evo-$e'),
                icon: Icons.auto_awesome,
                text: e == 'densetsu'
                    ? 'しんか！ でんせつに なった！ わざが ぜんぶ パワーアップ！'
                    : 'しんか！ ${evolutionLabel(e)}に なった！',
                big: true,
              ),
            const SizedBox(height: 16),
            if (_adOffered()) RewardedAdButton(onRewarded: _onAdReward),
            const SizedBox(height: 16),
            if (c != null) ...[
              VideoExportButton(characterId: c.id),
              const SizedBox(height: 12),
            ],
            ..._buttons(context, c),
          ],
        ),
      ),
    );
  }

  List<Widget> _buttons(BuildContext context, CharacterV2? c) {
    final stage = _o.stage;
    return [
      if (stage != null && _o.won && stage < 100 && c != null)
        FilledButton.icon(
          key: const Key('result-next'),
          icon: const Icon(Icons.arrow_forward),
          onPressed: () =>
              context.pushReplacement(Routes.cpuBattle(c.id, stage + 1)),
          label: const Text('つぎの ステージへ'),
        ),
      if (stage != null && c != null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('result-retry'),
          icon: const Icon(Icons.replay),
          onPressed: () =>
              context.pushReplacement(Routes.cpuBattle(c.id, stage)),
          label: const Text('もういちど'),
        ),
      ],
      if (_o.online && c != null) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('result-online-again'),
          icon: const Icon(Icons.public),
          onPressed: () => context.pushReplacement(Routes.onlineQueue(c.id)),
          label: const Text('もういちど たたかう'),
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('result-home'),
        icon: const Icon(Icons.home),
        onPressed: () => context.go(Routes.home),
        label: const Text('ホームに もどる'),
      ),
    ];
  }
}

/// 「あたらしい わざ！」 with the move's name and colour.
class _NewMove extends StatelessWidget {
  const _NewMove({required this.c, required this.slot});
  final CharacterV2 c;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final m = c.allMoves()[slot];
    return Celebrate(
      key: Key('result-newmove-$slot'),
      icon: slot == 3 ? Icons.star : Icons.flash_on,
      text: 'あたらしい わざ！ 「${moveDisplayName(m)}」',
      big: true,
    );
  }
}

/// A yellow celebration card (pops in).
class Celebrate extends StatelessWidget {
  const Celebrate({
    super.key,
    required this.icon,
    required this.text,
    this.big = false,
  });
  final IconData icon;
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.6, end: 1),
    duration: const Duration(milliseconds: 500),
    curve: Curves.elasticOut,
    builder: (context, s, child) => Transform.scale(scale: s, child: child),
    child: Card(
      color: big ? const Color(0xFFFFE08A) : const Color(0xFFFFF0C2),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: big ? 48 : 36, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: big ? 22 : 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
