/// Messages of the realtime battle protocol v1 (docs/REALTIME_PROTOCOL.md,
/// `server/realtime/protocol.schema.json`). JSON text frames, one object per
/// frame, discriminated by `t`. Unknown fields and event types are ignored
/// (§10: additive changes keep `proto: 1`).
library;

import 'dart:convert';

const int kRealtimeProto = 1;

// --- client → server ------------------------------------------------------------

String helloMsg({
  required String idToken,
  String? appCheckToken,
  int? lastSeq,
}) => jsonEncode({
  't': 'hello',
  'proto': kRealtimeProto,
  'idToken': idToken,
  'appCheckToken': ?appCheckToken,
  'lastSeq': ?lastSeq,
});

String queueMsg(String snapshotId) =>
    jsonEncode({'t': 'queue', 'snapshotId': snapshotId});

String cancelMsg() => jsonEncode({'t': 'cancel'});

String selectMsg(int seq, int slot) =>
    jsonEncode({'t': 'select', 'seq': seq, 'slot': slot});

String pingMsg() => jsonEncode({'t': 'ping'});

// --- server → client ------------------------------------------------------------

int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
String _str(Object? v, [String d = '']) => v is String ? v : d;
Map<String, Object?> _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const {};

/// Side letter → index (0 = a, 1 = b).
int? sideIndex(Object? s) => s == 'a' ? 0 : (s == 'b' ? 1 : null);

/// A move as the server shows it (`MovePublic`). `vfx` / `colour` / `hits`
/// are optional extras (display only).
class PublicMove {
  const PublicMove({
    required this.slot,
    required this.name,
    required this.template,
    required this.attr,
    required this.spCost,
    this.vfx,
    this.colour,
    this.hits = 1,
  });

  final int slot;
  final String name;
  final String template;
  final String attr;
  final int spCost;
  final String? vfx;
  final String? colour;
  final int hits;

  factory PublicMove.fromJson(Map<String, Object?> j) => PublicMove(
    slot: _int(j['slot']),
    name: _str(j['name']),
    template: _str(j['templateId'], 'strike'),
    attr: _str(j['attr'], 'none'),
    spCost: _int(j['spCost']),
    vfx: j['vfx'] as String?,
    colour: j['colour'] as String?,
    hits: _int(j['hits'], 1).clamp(1, 3),
  );
}

/// `FighterInfo`.
class FighterInfo {
  const FighterInfo({
    required this.displayName,
    required this.characterName,
    required this.imagePath,
    required this.rig,
    required this.attr,
    required this.moves,
    required this.maxHp,
    required this.level,
    required this.badge,
    required this.isGhost,
    this.snapshotId,
  });

  /// Optional (not in protocol v1 yet): lets the child report the
  /// opponent's character (SPEC §9.4).
  final String? snapshotId;

  final String displayName;
  final String characterName;
  final String? imagePath;
  final Map<String, Object?>? rig;
  final String attr;
  final List<PublicMove> moves;
  final int maxHp;
  final int level;
  final String badge;
  final bool isGhost;

  factory FighterInfo.fromJson(Map<String, Object?> j) => FighterInfo(
    displayName: _str(j['displayName']),
    characterName: _str(j['characterName']),
    imagePath: j['imagePath'] as String?,
    rig: j['rig'] is Map ? (j['rig']! as Map).cast<String, Object?>() : null,
    attr: _str(j['attr'], 'none'),
    moves: [
      for (final m in (j['moves'] as List?) ?? const [])
        if (m is Map) PublicMove.fromJson(m.cast<String, Object?>()),
    ]..sort((a, b) => a.slot.compareTo(b.slot)),
    maxHp: _int(j['maxHp'], 1),
    level: _int(j['level'], 50),
    badge: _str(j['badge'], 'egg'),
    isGhost: j['isGhost'] == true,
    snapshotId: j['snapshotId'] as String?,
  );
}

/// `SideView`.
class SideView {
  const SideView({
    required this.hp,
    required this.maxHp,
    required this.sp,
    required this.gauge,
    required this.ready,
    required this.casting,
  });

  final int hp, maxHp;

  /// 1/100 SP (0..10000).
  final int sp;

  /// 0..10000.
  final int gauge;
  final bool ready, casting;

  factory SideView.fromJson(Map<String, Object?> j) => SideView(
    hp: _int(j['hp']),
    maxHp: _int(j['maxHp'], 1),
    sp: _int(j['sp']),
    gauge: _int(j['gauge']),
    ready: j['ready'] == true,
    casting: j['casting'] == true,
  );
}

sealed class ServerMsg {
  const ServerMsg();

  /// Parses one frame; null for unknown / malformed messages.
  static ServerMsg? parse(String frame) {
    final Object? raw;
    try {
      raw = jsonDecode(frame);
    } on FormatException {
      return null;
    }
    if (raw is! Map) return null;
    final j = raw.cast<String, Object?>();
    return switch (j['t']) {
      'welcome' => WelcomeMsg(inMatch: j['inMatch'] == true),
      'queued' => const QueuedMsg(),
      'cancelled' => const CancelledMsg(),
      'match' => MatchMsg(
        matchId: _str(j['matchId']),
        you: sideIndex(j['you']) ?? 0,
        tickHz: _int(j['tickHz'], 10),
        decisionTicks: _int(j['decisionTicks'], 50),
        fighters: [
          FighterInfo.fromJson(_map(j['a'])),
          FighterInfo.fromJson(_map(j['b'])),
        ],
        resumed: j['resumed'] == true,
      ),
      'ev' => EvMsg(
        seq: _int(j['seq']),
        tick: _int(j['tick']),
        events: [
          for (final e in (j['events'] as List?) ?? const [])
            if (e is Map) e.cast<String, Object?>(),
        ],
      ),
      'snap' => SnapMsg(
        tick: _int(j['tick']),
        sides: [
          SideView.fromJson(_map(j['a'])),
          SideView.fromJson(_map(j['b'])),
        ],
      ),
      'sel' => SelMsg(
        seq: _int(j['seq']),
        slot: _int(j['slot']),
        accepted: j['accepted'] == true,
        queued: j['queued'] == true,
        reason: j['reason'] as String?,
      ),
      'end' => EndMsg(
        matchId: _str(j['matchId']),
        winner: sideIndex(j['winner']),
        reason: _str(j['reason'], 'ko'),
        outcome: _str(_map(j['you'])['outcome'], 'none'),
        xp: _int(_map(j['you'])['xp']),
        badge: _map(j['you'])['badge'] as String?,
        badgeUp: _map(j['you'])['badgeUp'] == true,
      ),
      'pong' => const PongMsg(),
      'error' => ErrorMsg(_str(j['code'], 'INTERNAL')),
      'bye' => ByeMsg(
        reason: _str(j['reason']),
        reconnect: j['reconnect'] == true,
      ),
      _ => null,
    };
  }
}

class WelcomeMsg extends ServerMsg {
  const WelcomeMsg({required this.inMatch});
  final bool inMatch;
}

class QueuedMsg extends ServerMsg {
  const QueuedMsg();
}

class CancelledMsg extends ServerMsg {
  const CancelledMsg();
}

class MatchMsg extends ServerMsg {
  const MatchMsg({
    required this.matchId,
    required this.you,
    required this.tickHz,
    required this.decisionTicks,
    required this.fighters,
    required this.resumed,
  });
  final String matchId;

  /// 0 = a, 1 = b.
  final int you;
  final int tickHz, decisionTicks;
  final List<FighterInfo> fighters;
  final bool resumed;
}

class EvMsg extends ServerMsg {
  const EvMsg({required this.seq, required this.tick, required this.events});
  final int seq, tick;
  final List<Map<String, Object?>> events;
}

class SnapMsg extends ServerMsg {
  const SnapMsg({required this.tick, required this.sides});
  final int tick;
  final List<SideView> sides;
}

class SelMsg extends ServerMsg {
  const SelMsg({
    required this.seq,
    required this.slot,
    required this.accepted,
    required this.queued,
    this.reason,
  });
  final int seq, slot;
  final bool accepted, queued;
  final String? reason;
}

class EndMsg extends ServerMsg {
  const EndMsg({
    required this.matchId,
    required this.winner,
    required this.reason,
    required this.outcome,
    required this.xp,
    required this.badge,
    required this.badgeUp,
  });
  final String matchId;
  final int? winner;

  /// ko / timeout / forfeit / aborted.
  final String reason;

  /// win / lose / none.
  final String outcome;
  final int xp;
  final String? badge;
  final bool badgeUp;
}

class PongMsg extends ServerMsg {
  const PongMsg();
}

class ErrorMsg extends ServerMsg {
  const ErrorMsg(this.code);
  final String code;
}

class ByeMsg extends ServerMsg {
  const ByeMsg({required this.reason, required this.reconnect});
  final String reason;
  final bool reconnect;
}

/// Kid message for a protocol error code (§6); null = handled silently.
String? realtimeErrorMessage(String code) => switch (code) {
  'CONSENT_REQUIRED' => 'おうちのひとに オンラインを ゆるして もらってね',
  'LEVEL_TOO_LOW' => 'レベル5に なったら オンラインで あそべるよ',
  'NOT_FOUND' || 'NOT_OWNER' => 'もういちど とうろく してね',
  'APP_CHECK_FAILED' => 'いまは つながらないよ',
  'PROTOCOL_VERSION' => 'アプリを あたらしく してね',
  'UNAUTHENTICATED' ||
  'DRAINING' ||
  'RATE_LIMITED' ||
  'ALREADY_IN_MATCH' ||
  'NOT_IN_MATCH' ||
  'BAD_MESSAGE' => null,
  _ => 'うまく いかなかったよ',
};
