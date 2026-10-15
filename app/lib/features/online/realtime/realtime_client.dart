/// WebSocket client of the realtime battle server (docs/REALTIME_PROTOCOL.md):
/// hello → queue → match → select … → end, with silent reconnects. The
/// socket is open only while the child is searching or battling (§1: the
/// server bills while a socket is open).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../data/backend/backend_api.dart';
import 'realtime_messages.dart';

/// One WebSocket connection (text frames).
abstract interface class RealtimeSocket {
  Stream<String> get frames;
  void send(String frame);
  Future<void> close([int code = 1000]);
}

/// Opens a socket to [url]; throws when the upgrade fails (e.g. HTTP 503).
typedef RealtimeConnector = Future<RealtimeSocket> Function(Uri url);

class _IoSocket implements RealtimeSocket {
  _IoSocket(this._ws);
  final WebSocket _ws;

  @override
  Stream<String> get frames => _ws.where((f) => f is String).cast<String>();

  @override
  void send(String frame) => _ws.add(frame);

  @override
  Future<void> close([int code = 1000]) => _ws.close(code);
}

Future<RealtimeSocket> ioRealtimeConnector(Uri url) async =>
    _IoSocket(await WebSocket.connect(url.toString()));

final realtimeConnectorProvider = Provider<RealtimeConnector>(
  (ref) => ioRealtimeConnector,
);

/// The server URL (`--dart-define=REALTIME_URL=…`); empty = not set up.
final realtimeUrlProvider = Provider<String>((ref) => realtimeUrl);

/// Delays between reconnect attempts (§6–7): 1, 2, 4 … then give up
/// (about 30 s in total) and offer single-player.
final realtimeBackoffProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ],
);

enum RealtimePhase {
  /// Connecting / saying hello.
  connecting,

  /// In the matchmaking queue (「あいてを さがしているよ」).
  searching,

  /// A match is running.
  battle,

  /// The result arrived (or the match was aborted).
  ended,

  /// Gave up; [RealtimeSession.error] says why (kid message).
  failed,
}

/// Session state machine. Listeners are notified on phase changes; battle
/// traffic goes to [onMatch] / [onEvents] / [onSnap] / [onSel] / [onEnd].
class RealtimeSession extends ChangeNotifier {
  RealtimeSession({
    required this.url,
    required this.connect,
    required this.auth,
    required this.snapshotId,
    this.backoff = const [Duration(seconds: 1)],
  });

  final Uri url;
  final RealtimeConnector connect;
  final Future<RealtimeAuth> Function() auth;
  final String snapshotId;
  final List<Duration> backoff;

  void Function(MatchMsg m)? onMatch;
  void Function(EvMsg m)? onEvents;
  void Function(SnapMsg m)? onSnap;
  void Function(SelMsg m)? onSel;
  void Function(EndMsg m)? onEnd;

  RealtimePhase phase = RealtimePhase.connecting;
  String? error;

  /// The server's protocol revision (`welcome.rev`; 1 = no `omakase`).
  int serverRev = 1;

  /// The child's おまかせ switch as last set with [setOmakase]. Re-sent
  /// after every `match` (also when resuming after a reconnect).
  bool omakase = false;

  /// Protocol error code that ended the session, if any.
  String? errorCode;
  MatchMsg? match;
  EndMsg? end;

  RealtimeSocket? _socket;
  StreamSubscription<String>? _sub;
  int _lastSeq = 0;
  int _selectSeq = 0;
  int _failures = 0;
  bool _closed = false;
  bool _unauthRetried = false;
  Timer? _retry;

  void _set(RealtimePhase p) {
    if (phase == p) return;
    phase = p;
    if (!_closed) notifyListeners();
  }

  /// Connects and joins the queue (or resumes a running match).
  Future<void> start() => _open();

  Future<void> _open() async {
    if (_closed) return;
    try {
      final a = await auth();
      final s = await connect(url);
      if (_closed) {
        await s.close();
        return;
      }
      _socket = s;
      _sub = s.frames.listen(
        _onFrame,
        onDone: _onDrop,
        onError: (Object _) => _onDrop(),
        cancelOnError: true,
      );
      s.send(
        helloMsg(
          idToken: a.idToken,
          appCheckToken: a.appCheckToken,
          lastSeq: phase == RealtimePhase.battle ? _lastSeq : null,
        ),
      );
    } on Object {
      _scheduleReconnect();
    }
  }

  void _onFrame(String frame) {
    final m = ServerMsg.parse(frame);
    switch (m) {
      case WelcomeMsg(:final inMatch, :final rev):
        _failures = 0;
        serverRev = rev;
        if (!inMatch && phase != RealtimePhase.ended) {
          if (phase == RealtimePhase.battle) {
            // The match ended while away and its `end` is gone: nothing to
            // show (the server already saved the result).
            _finishSilently();
          } else {
            _socket?.send(queueMsg(snapshotId));
          }
        }
      case QueuedMsg():
        _set(RealtimePhase.searching);
      case MatchMsg():
        if (!m.resumed || match?.matchId != m.matchId) {
          _lastSeq = 0;
          _selectSeq = 0;
        }
        match = m;
        onMatch?.call(m);
        _set(RealtimePhase.battle);
        if (omakase) _sendOmakase();
      case EvMsg():
        if (m.seq <= _lastSeq) return; // replayed after a reconnect
        _lastSeq = m.seq;
        onEvents?.call(m);
      case SnapMsg():
        onSnap?.call(m);
      case SelMsg():
        onSel?.call(m);
      case EndMsg():
        end = m;
        onEnd?.call(m);
        _set(RealtimePhase.ended);
        unawaited(close());
      case ErrorMsg(:final code):
        _onError(code);
      case ByeMsg(:final reconnect):
        if (reconnect) {
          _reconnectNow();
        } else {
          _fail('うまく いかなかったよ');
        }
      case PongMsg() || CancelledMsg() || OmakaseAckMsg() || null:
        break;
    }
  }

  void _onError(String code) {
    if (code == 'UNAUTHENTICATED' && !_unauthRetried) {
      _unauthRetried = true; // refresh the token and retry silently once
      _reconnectNow();
      return;
    }
    if (code == 'DRAINING') {
      _reconnectNow();
      return;
    }
    final msg = realtimeErrorMessage(code);
    if (msg != null) {
      errorCode = code;
      _fail(msg);
    }
  }

  void _finishSilently() {
    end = EndMsg(
      matchId: match?.matchId ?? '',
      winner: null,
      reason: 'aborted',
      outcome: 'none',
      xp: 0,
      badge: null,
      badgeUp: false,
    );
    onEnd?.call(end!);
    _set(RealtimePhase.ended);
    unawaited(close());
  }

  void _drop() {
    unawaited(_sub?.cancel());
    _sub = null;
    final s = _socket;
    _socket = null;
    if (s != null) unawaited(s.close().catchError((Object _) {}));
  }

  void _onDrop() {
    if (_closed || phase == RealtimePhase.ended) return;
    _drop();
    _scheduleReconnect();
  }

  void _reconnectNow() {
    _drop();
    _retry?.cancel();
    _retry = Timer(Duration.zero, _open);
  }

  void _scheduleReconnect() {
    if (_closed) return;
    if (_failures >= backoff.length) {
      _fail('つながらなかったよ。ひとりで あそぼう');
      return;
    }
    final wait = backoff[_failures++];
    _retry?.cancel();
    _retry = Timer(wait, _open);
  }

  void _fail(String message) {
    error = message;
    _set(RealtimePhase.failed);
    unawaited(close());
  }

  /// The child picked [slot] (any time: さきどり while the gauge fills).
  void select(int slot) {
    if (phase != RealtimePhase.battle) return;
    _socket?.send(selectMsg(++_selectSeq, slot));
  }

  /// The child's おまかせ switch: while on, the server picks a random move,
  /// waits until its bars are there and uses it; off gives the child full
  /// control again. Needs a rev 2+ server.
  void setOmakase(bool on) {
    omakase = on;
    if (phase == RealtimePhase.battle) _sendOmakase();
  }

  void _sendOmakase() {
    if (serverRev < kOmakaseRevision) return;
    _socket?.send(omakaseMsg(omakase));
  }

  /// Leaves the queue / the screen. Safe to call twice.
  Future<void> close() async {
    _retry?.cancel();
    final s = _socket;
    if (s != null && phase == RealtimePhase.searching) {
      try {
        s.send(cancelMsg());
      } on Object {
        // already gone
      }
    }
    _closed = true;
    _drop();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
