import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_settings.dart';
import '../../data/app_state.dart';
import '../../core/config/app_config.dart';
import '../parent/consent_toggles.dart';
import '../parent/policy_links.dart';

/// First-run parent setup (SPEC §2-1): parental gate → explanation and
/// consents → done. Also shown again when the privacy policy version grows.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _unlocked = false;
  ParentConsents? _consents;
  bool _saving = false;

  Future<void> _openGate() async {
    final ok = await ref.read(parentalGateProvider).verify(context);
    if (ok && mounted) setState(() => _unlocked = true);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final consents =
        _consents ??
        ref.read(settingsProvider).value?.consents ??
        const ParentConsents();
    await ref.read(settingsProvider.notifier).completeSetup(consents);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: _unlocked ? _consentStep() : _welcomeStep()),
  );

  Widget _welcomeStep() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.brush, size: 96, color: AppColors.primary),
        const SizedBox(height: 12),
        const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            appDisplayName,
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'はじめに おうちのひとと いっしょに じゅんびしよう！',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          key: const Key('setup-start'),
          onPressed: _openGate,
          icon: const Icon(Icons.family_restroom),
          label: const Text('おうちのひとに わたす'),
        ),
      ],
    ),
  );

  Widget _consentStep() {
    final serverAvailable = ref.watch(backendApiProvider).isAvailable;
    final consents =
        _consents ??
        ref.watch(settingsProvider).value?.consents ??
        const ParentConsents();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '保護者の方へ',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          '「$appDisplayName」は、お子さまが紙にかいた絵を撮影してキャラクターにし、'
          'バトルで育てるゲームです。絵の解析は端末の中で行われます。\n'
          '以下の機能は、許可した場合だけ使われます（あとから「おうちのひと」'
          '画面でいつでも変更できます）。',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 12),
        const NoAiTrainingNotice(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ConsentToggles(
              value: consents,
              serverAvailable: serverAvailable,
              crashReportsAvailable: ref
                  .watch(crashReporterProvider)
                  .isAvailable,
              onChanged: (c) => setState(() => _consents = c),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'サーバーを使う機能では、匿名の ID が作成されます。氏名・住所・メール'
          'アドレスなどは集めません。データは「おうちのひと」画面からいつでも'
          'すべて削除できます。',
          style: TextStyle(fontSize: 14),
        ),
        const PolicyLinks(pages: [PolicyPage.privacy, PolicyPage.terms]),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('setup-finish'),
          onPressed: _saving ? null : _finish,
          child: const Text('この設定ではじめる'),
        ),
      ],
    );
  }
}
