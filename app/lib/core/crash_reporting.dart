/// Opt-in crash reports (SPEC §7: Crashlytics only, no Analytics).
///
/// Collection is OFF by default: the manifest sets
/// `firebase_crashlytics_collection_enabled=false`, and it is only switched
/// on while the parent's 「ふぐあいの じょうほうを おくる」 consent is on and
/// Firebase is configured. See docs/COMPLIANCE.md §4.
library;

import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

abstract interface class CrashReporter {
  /// False when Firebase is not configured (the consent switch is shown as
  /// 「準備中」).
  bool get isAvailable;

  /// Mirrors the parent's consent. Turning it off also deletes reports that
  /// were not sent yet.
  Future<void> setEnabled(bool enabled);
}

class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  bool get isAvailable => false;

  @override
  Future<void> setEnabled(bool enabled) async {}
}

/// Firebase Crashlytics. Only constructed after `Firebase.initializeApp`
/// succeeded.
class FirebaseCrashReporter implements CrashReporter {
  FirebaseCrashReporter({FirebaseCrashlytics? crashlytics})
    : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;
  bool _enabled = false;
  bool _hooked = false;

  @override
  bool get isAvailable => true;

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (enabled) _installHandlers();
    try {
      // Persisted by the native SDK; overrides the manifest default.
      await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
      if (!enabled) await _crashlytics.deleteUnsentReports();
    } on Object catch (e) {
      debugPrint('crashlytics: $e');
    }
  }

  /// Forwards Flutter/Dart errors, but only while enabled. Installed once,
  /// chaining the previous handlers.
  void _installHandlers() {
    if (_hooked) return;
    _hooked = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutter?.call(details);
      if (_enabled) unawaited(_crashlytics.recordFlutterFatalError(details));
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_enabled) {
        unawaited(_crashlytics.recordError(error, stack, fatal: true));
      }
      return previousPlatform?.call(error, stack) ?? _enabled;
    };
  }
}
