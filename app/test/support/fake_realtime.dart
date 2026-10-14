import 'dart:async';
import 'dart:convert';

import 'package:doodle_battle/features/online/realtime/realtime_client.dart';

/// A scripted realtime server: records what the app sends, lets the test
/// push server messages and drop the connection.
class FakeRealtimeServer {
  final sockets = <FakeRealtimeSocket>[];
  final urls = <Uri>[];

  /// Upgrade failures to simulate before connecting (HTTP 503 …).
  int failNextConnects = 0;

  Future<RealtimeSocket> connect(Uri url) async {
    urls.add(url);
    if (failNextConnects > 0) {
      failNextConnects--;
      throw StateError('503');
    }
    final s = FakeRealtimeSocket();
    sockets.add(s);
    return s;
  }

  FakeRealtimeSocket get last => sockets.last;

  /// Every message the app sent on any socket, decoded.
  List<Map<String, Object?>> get sent => [
    for (final s in sockets)
      for (final f in s.sent) (jsonDecode(f) as Map).cast<String, Object?>(),
  ];

  List<String> get sentTypes => [for (final m in sent) m['t']! as String];

  void push(Map<String, Object?> msg) => last.push(msg);
}

class FakeRealtimeSocket implements RealtimeSocket {
  final _in = StreamController<String>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<String> get frames => _in.stream;

  @override
  void send(String frame) {
    if (!closed) sent.add(frame);
  }

  @override
  Future<void> close([int code = 1000]) async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void push(Map<String, Object?> msg) => _in.add(jsonEncode(msg));

  /// The network drops (the app should reconnect).
  Future<void> drop() async {
    if (!_in.isClosed) await _in.close();
  }
}

/// `FighterInfo` as the server sends it.
Map<String, Object?> fighterInfo(
  String name, {
  String displayName = 'あおい ドラゴン',
  bool ghost = false,
  int maxHp = 900,
}) => {
  'displayName': displayName,
  'characterName': name,
  'imagePath': 'snapshotImages/$name/image.png',
  'attr': 'gu',
  'moves': [
    {
      'slot': 0,
      'name': '$nameパンチ',
      'templateId': 'strike',
      'attr': 'gu',
      'spCost': 0,
    },
    {
      'slot': 1,
      'name': 'ふわふわ',
      'templateId': 'heal',
      'attr': 'none',
      'spCost': 20,
    },
  ],
  'maxHp': maxHp,
  'level': 50,
  'badge': 'rabbit',
  'isGhost': ghost,
};

Map<String, Object?> matchMsg({String you = 'a', bool resumed = false}) => {
  't': 'match',
  'matchId': 'm1',
  'you': you,
  'tickHz': 10,
  'decisionTicks': 50,
  'a': fighterInfo('ねこまる', displayName: 'げんきな うさぎ'),
  'b': fighterInfo('さかなくん', ghost: true),
  'resumed': resumed,
};

Map<String, Object?> sideView({
  int hp = 900,
  int gauge = 0,
  bool ready = false,
}) => {
  'hp': hp,
  'maxHp': 900,
  'sp': 4000,
  'gauge': gauge,
  'ready': ready,
  'casting': false,
};
