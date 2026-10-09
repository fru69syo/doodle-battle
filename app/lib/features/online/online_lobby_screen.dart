import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/coming_soon.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../domain/character.dart';
import '../battle_ui/battle_select_screen.dart';
import 'online_messages.dart';
import 'online_registration.dart';

/// Heartbeat interval while waiting in the queue (docs/BACKEND.md §5).
final queueHeartbeatProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// Online lobby (SPEC §2-7): only when the parent allowed online play and
/// the server is configured; only characters Lv5+.
class OnlineLobbyScreen extends ConsumerWidget {
  const OnlineLobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(settingsProvider).value?.consents.online ?? false;
    final ready = ref.watch(backendApiProvider).isAvailable;
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
    return BattleSelectScreen(
      title: 'オンライン たいせん',
      filter: (c) => c.onlineUnlocked ? null : 'Lv5 に なったら あそべるよ',
      onSelect: (context, c) => context.push(Routes.onlineQueue(c.id)),
    );
  }
}

enum _Phase { registering, rejected, waiting, error }

/// Registration (moderation) → matchmaking queue with heartbeat.
class OnlineQueueScreen extends ConsumerStatefulWidget {
  const OnlineQueueScreen({super.key, required this.character});
  final Character character;

  @override
  ConsumerState<OnlineQueueScreen> createState() => _OnlineQueueScreenState();
}

class _OnlineQueueScreenState extends ConsumerState<OnlineQueueScreen> {
  late Character _c = widget.character;
  _Phase _phase = _Phase.registering;
  String _message = '';
  List<String> _presets = const [];
  Timer? _heartbeat;
  bool _inQueue = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    if (_inQueue && !_navigated) {
      unawaited(ref.read(backendApiProvider).leaveQueue().catchError((_) {}));
    }
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _phase = _Phase.registering);
    final r = await ref.read(onlineRegistrationProvider).ensureRegistered(_c);
    if (!mounted) return;
    switch (r) {
      case RegistrationOk(:final character):
        _c = character;
        await _join();
      case RegistrationRejected(:final message, :final presetNames):
        setState(() {
          _phase = _Phase.rejected;
          _message = message;
          _presets = presetNames;
        });
    }
  }

  Future<void> _usePreset(String name) async {
    _c = await ref.read(onlineRegistrationProvider).rename(_c, name);
    await _register();
  }

  Future<void> _join() async {
    setState(() => _phase = _Phase.waiting);
    _inQueue = true;
    await _beat();
    _heartbeat ??= Timer.periodic(
      ref.read(queueHeartbeatProvider),
      (_) => _beat(),
    );
  }

  Future<void> _beat() async {
    try {
      final s = await ref.read(backendApiProvider).joinQueue(_c.onlineId!);
      if (!mounted || _navigated) return;
      if (s.state == QueueState.matched && s.matchId != null) {
        _navigated = true;
        _heartbeat?.cancel();
        context.pushReplacement(Routes.onlineMatch(s.matchId!, _c.id));
        _inQueue = false;
      }
    } on BackendException catch (e) {
      if (!mounted) return;
      if (e.code == BackendCodes.snapshotNotActive) {
        _heartbeat?.cancel();
        _heartbeat = null;
        await ref.read(progressProvider.notifier).setOnlineLevel(_c.id, -1);
        await _register();
        return;
      }
      _heartbeat?.cancel();
      setState(() {
        _phase = _Phase.error;
        _message = backendErrorMessage(e.code);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('オンライン たいせん')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _body()),
      ),
    ),
  );

  Widget _body() => switch (_phase) {
    _Phase.registering => const _Waiting(
      key: Key('online-registering'),
      text: 'キャラを しんさ しているよ…',
    ),
    _Phase.waiting => const _Waiting(
      key: Key('online-waiting'),
      text: 'あいてを さがしているよ…',
    ),
    _Phase.rejected || _Phase.error => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.sentiment_neutral,
          size: 72,
          color: AppColors.secondary,
        ),
        const SizedBox(height: 12),
        Text(
          _message,
          key: const Key('online-message'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in _presets)
              ActionChip(
                key: Key('online-preset-$n'),
                label: Text(n, style: const TextStyle(fontSize: 20)),
                onPressed: () => _usePreset(n),
              ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('もどる'),
        ),
      ],
    ),
  };
}

class _Waiting extends StatelessWidget {
  const _Waiting({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(
        width: 96,
        height: 96,
        child: CircularProgressIndicator(strokeWidth: 10),
      ),
      const SizedBox(height: 24),
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('やめる'),
      ),
    ],
  );
}
