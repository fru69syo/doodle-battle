import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'parental_gate_challenge.dart';

/// Holding time of the first step.
const parentalGateHold = Duration(seconds: 3);

/// The gate UI. Pops `true` when passed, `false` when cancelled or after 3
/// wrong answers. Parent-facing text uses normal Japanese (kanji).
class ParentalGateDialog extends StatefulWidget {
  const ParentalGateDialog({
    super.key,
    required this.random,
    this.maxAttempts = 3,
  });

  final Random random;
  final int maxAttempts;

  @override
  State<ParentalGateDialog> createState() => _ParentalGateDialogState();
}

class _ParentalGateDialogState extends State<ParentalGateDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: parentalGateHold,
  )..addStatusListener(_onHoldStatus);
  bool _held = false;
  late ParentalGateChallenge _challenge = ParentalGateChallenge.random(
    widget.random,
  );
  String _input = '';
  int _wrong = 0;
  String? _error;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _onHoldStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) setState(() => _held = true);
  }

  void _press(String key) {
    setState(() {
      _error = null;
      if (key == '←') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else if (_input.length < 4) {
        _input += key;
      }
    });
  }

  void _submit() {
    if (_challenge.check(_input)) {
      Navigator.of(context).pop(true);
      return;
    }
    _wrong++;
    if (_wrong >= widget.maxAttempts) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _error = '答えが違います。もう一度どうぞ。';
      _input = '';
      _challenge = ParentalGateChallenge.random(widget.random);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('保護者の方へ', textAlign: TextAlign.center),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: _held ? _question(context) : _holdStep(context),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('gate-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('やめる'),
        ),
      ],
    );
  }

  Widget _holdStep(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'ここから先は保護者の方向けです。\n下のボタンを3秒間長押ししてください。',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      const Text('（おうちのひとに わたしてね）', style: TextStyle(fontSize: 16)),
      const SizedBox(height: 20),
      Listener(
        key: const Key('gate-hold'),
        onPointerDown: (_) => _hold.forward(from: 0),
        onPointerUp: (_) => _held ? null : _hold.reset(),
        onPointerCancel: (_) => _held ? null : _hold.reset(),
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) => SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _hold.value,
                    strokeWidth: 10,
                    backgroundColor: AppColors.disabled,
                    color: AppColors.secondary,
                  ),
                ),
                const Text(
                  '長押し',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _question(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('次の計算の答えを入力してください。', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text(
        _challenge.digitsText,
        key: const Key('gate-question'),
        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
      ),
      Text(
        '（${_challenge.kanjiText}）',
        key: const Key('gate-question-kanji'),
        style: const TextStyle(fontSize: 18),
      ),
      const SizedBox(height: 12),
      Container(
        width: 160,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.ink, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _input.isEmpty ? ' ' : _input,
          key: const Key('gate-input'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ),
      const SizedBox(height: 12),
      _Keypad(onKey: _press, onOk: _input.isEmpty ? null : _submit),
    ],
  );
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.onOk});

  final ValueChanged<String> onKey;
  final VoidCallback? onOk;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['←', '0', 'OK'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final k in row)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    width: 72,
                    height: 56,
                    child: k == 'OK'
                        ? FilledButton(
                            key: const Key('gate-ok'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(56, 56),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: onOk,
                            child: const Text('OK'),
                          )
                        : OutlinedButton(
                            key: Key('gate-key-$k'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(56, 56),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => onKey(k),
                            child: Text(
                              k,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
