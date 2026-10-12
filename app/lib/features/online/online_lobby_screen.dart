import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/coming_soon.dart';
import '../../data/app_state.dart';
import '../battle_ui/battle_select_screen.dart';
import 'display_name_picker.dart';
import 'online_badges.dart';
import 'realtime/realtime_client.dart';

/// Online lobby (SPEC §12.5): only when the parent allowed online play and
/// the server is configured; characters from Lv5. Shows the online name
/// (preset words only) and the best badge. No chat.
class OnlineLobbyScreen extends ConsumerWidget {
  const OnlineLobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(settingsProvider).value?.consents.online ?? false;
    final ready =
        ref.watch(backendApiProvider).isAvailable &&
        ref.watch(realtimeUrlProvider).isNotEmpty;
    if (!allowed || !ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('オンライン')),
        body: Center(
          child: allowed
              ? const ComingSoonNote(key: Key('online-coming-soon'))
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'オンラインで あそぶには おうちのひとに きいてね',
                    key: Key('online-not-allowed'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
        ),
      );
    }
    final badge = ref.watch(progressProvider).value?.onlineBadge ?? 'egg';
    return BattleSelectScreen(
      title: 'オンライン たいせん',
      filter: (c) => c.onlineUnlocked ? null : 'Lv5 に なったら あそべるよ',
      header: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BadgeChip(key: const Key('lobby-badge'), badge: badge),
          ),
          const DisplayNameCard(),
        ],
      ),
      onSelect: (context, c) => context.push(Routes.onlineQueue(c.id)),
    );
  }
}
