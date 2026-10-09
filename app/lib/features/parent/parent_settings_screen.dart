import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../monetization/shop_section.dart';
import 'ar_install_tile.dart';
import 'consent_toggles.dart';
import 'delete_all_data.dart';
import 'parent_session.dart';
import 'policy_links.dart';

/// 「おうちのひと」 (behind the parental gate; SPEC §7). Parent-facing text.
class ParentSettingsScreen extends ConsumerStatefulWidget {
  const ParentSettingsScreen({super.key});

  @override
  ConsumerState<ParentSettingsScreen> createState() =>
      _ParentSettingsScreenState();
}

class _ParentSettingsScreenState extends ConsumerState<ParentSettingsScreen> {
  late final ParentSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(parentSessionProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the area locks it again (next visit needs the gate).
    final session = _session;
    Future.microtask(() {
      try {
        session.lock();
      } on Object {
        // container already disposed (app shutting down)
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final backend = ref.watch(backendApiProvider);
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('おうちのひと')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const _Section('許可の設定'),
            ConsentToggles(
              value: settings.consents,
              serverAvailable: backend.isAvailable,
              crashReportsAvailable: ref
                  .watch(crashReporterProvider)
                  .isAvailable,
              onChanged: (c) =>
                  ref.read(settingsProvider.notifier).updateConsents(c),
            ),
            const _Section('プレイ時間の目安（1日）'),
            _PlayTimePicker(minutes: settings.playTimeMinutes),
            const _Section('AR'),
            const ArInstallTile(),
            const _Section('ショップ'),
            const ShopSection(),
            const _Section('データ'),
            if (backend.supportId != null)
              ListTile(
                leading: const Icon(Icons.badge),
                title: const Text('サポート ID'),
                subtitle: SelectableText(backend.supportId!),
              ),
            ListTile(
              key: const Key('delete-all'),
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                'すべてのデータを削除',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const Text('端末とサーバーのデータをすべて削除します'),
              onTap: () => deleteAllData(context, ref),
            ),
            const _Section('ポリシーとサポート'),
            const PolicyLinks(),
            const _Section('その他'),
            ListTile(
              key: const Key('licenses'),
              leading: const Icon(Icons.description),
              title: const Text('ライセンス'),
              onTap: () =>
                  showLicensePage(context: context, applicationName: 'らくがきバトル'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 20, 8, 4),
    child: Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
  );
}

class _PlayTimePicker extends ConsumerWidget {
  const _PlayTimePicker({required this.minutes});
  final int? minutes;

  static const options = <int?>[null, 30, 60, 90, 120];

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final m in options)
        ChoiceChip(
          key: Key('playtime-${m ?? 'none'}'),
          label: Text(m == null ? 'なし' : '$m分'),
          selected: minutes == m,
          onSelected: (_) => ref.read(settingsProvider.notifier).setPlayTime(m),
        ),
    ],
  );
}
