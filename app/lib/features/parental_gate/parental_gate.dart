import 'dart:math';

import 'package:flutter/material.dart';

import 'parental_gate_dialog.dart';

export 'parental_gate_challenge.dart';
export 'parental_gate_dialog.dart';

/// Reusable parental gate (SPEC §7): 3-second hold, then a multiplication.
/// Use it before parent settings, purchases, external links and the ARCore
/// install prompt. Obtain it from `parentalGateProvider` so tests can
/// replace it.
abstract interface class ParentalGate {
  /// Shows the gate; true when an adult passed it.
  Future<bool> verify(BuildContext context);
}

class DialogParentalGate implements ParentalGate {
  DialogParentalGate({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  /// Wrong answers allowed before the gate closes.
  static const maxAttempts = 3;

  @override
  Future<bool> verify(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ParentalGateDialog(random: _random),
    );
    return ok ?? false;
  }
}
