/// [StageFeed] over the realtime server's stream (docs/REALTIME_PROTOCOL.md
/// §5): server events are buffered and played back ~200 ms behind the
/// newest server tick, translated with the same [translate] as local
/// battles. The child's character is always side 0 on the stage.
///
/// Protocol rev 3 (stackable gauge bars): there is no decision timer; the
/// gauge shown is the snapshot's bars, interpolated between 2 Hz snapshots.
/// The current server tick is extrapolated from the newest message with the
/// local clock.
library;

import '../../../domain/battle_v3/battle_v3.dart';
import '../../battle_stage/adapters/battle_v3_feed.dart' show translate;
import '../../battle_stage/stage_events.dart';
import 'realtime_messages.dart';

/// Display move of a server move (unknown templates fall back to a strike).
Move displayMove(PublicMove m) {
  final template = kTemplates.containsKey(m.template) ? m.template : 'strike';
  return Move(
    template: template,
    attr: Attr.tryParse(m.attr) ?? Attr.none,
    name: m.name,
    bars: m.bars,
    hits: m.hits,
    vfx: m.vfx ?? _defaultVfx(template),
    colour: m.colour ?? 'yellow',
  );
}

Duration Function() _stopwatchClock() {
  final sw = Stopwatch()..start();
  return () => sw.elapsed;
}

String _defaultVfx(String template) => switch (template) {
  'strike' => 'punch',
  'combo' => 'slash',
  'blast' => 'beam',
  'barrage' => 'stars',
  'heal' => 'hearts',
  'power_up' => 'glow',
  'weaken' => 'spiral',
  'poison' => 'bubbles',
  'paralyze' => 'sparks',
  'barrier' => 'shield',
  _ => 'burst',
};

class OnlineFeed implements StageFeed {
  OnlineFeed(this.match, {this.delayTicks = 2, Duration Function()? clock})
    : _swap = match.you == 1,
      _now = clock ?? _stopwatchClock(),
      moves = [
        for (final s in match.you == 1 ? const [1, 0] : const [0, 1])
          [for (final m in match.fighters[s].moves) displayMove(m)],
      ];

  final MatchMsg match;

  /// Playback delay behind the newest server tick (2 ticks = 200 ms).
  final int delayTicks;
  final bool _swap;

  /// Display moves per stage side.
  final List<List<Move>> moves;

  final _buffer = <BattleEvent>[];
  double _clock = 0;
  int _newest = 0;
  bool _started = false;
  bool _ended = false;
  final _views = <SideView?>[null, null];
  int _snapTick = 0;
  final _status = [<String>{}, <String>{}];

  final Duration Function() _now;

  /// Called when the child's move went out (its `select` arrived from the
  /// server), in real time.
  void Function()? onMyAction;

  // Server tick estimate: the newest tick seen and when it arrived.
  int _anchorTick = 0;
  Duration _anchorAt = Duration.zero;
  bool _anchored = false;

  /// The server tick now, extrapolated from the newest message.
  double get serverTick {
    if (!_anchored) return 0;
    final dt = (_now() - _anchorAt).inMicroseconds / 1e6;
    return _anchorTick + dt * match.tickHz;
  }

  void _seen(int tick) {
    final est = serverTick;
    // Follow the server forward; resync when the local clock ran ahead.
    if (!_anchored || tick > est || est - tick > 5) {
      _anchorTick = tick;
      _anchorAt = _now();
      _anchored = true;
    }
  }

  int _side(Object? s) {
    final i = s is num ? s.toInt() : 0;
    return _swap ? 1 - i : i;
  }

  /// Server events of one `ev` message.
  void addEvents(EvMsg m) {
    _seen(m.tick);
    for (final raw in m.events) {
      final type = raw['type'];
      if (type is! String) continue;
      final tick = raw['tick'] is num ? (raw['tick']! as num).toInt() : m.tick;
      final mine = raw['side'] == match.you;
      if (mine && type == 'select') onMyAction?.call();
      final data = <String, Object>{};
      for (final e in raw.entries) {
        if (e.key == 'tick' || e.key == 'type') continue;
        final v = e.value;
        if (const {'side', 'target', 'winner'}.contains(e.key) && v is num) {
          data[e.key] = _side(v);
        } else if (v is num) {
          data[e.key] = v.toInt();
        } else if (v is String) {
          data[e.key] = v;
        }
      }
      _buffer.add(BattleEvent(tick, type, data));
    }
    if (m.tick > _newest) _newest = m.tick;
    if (!_started) {
      _started = true;
      _clock = (m.tick - delayTicks).toDouble();
    }
  }

  void addSnap(SnapMsg m) {
    _views[_swap ? 1 : 0] = m.sides[0];
    _views[_swap ? 0 : 1] = m.sides[1];
    _snapTick = m.tick;
    if (m.tick > _newest) _newest = m.tick;
    _seen(m.tick);
  }

  /// The match ended: make sure the stage shows the K.O. (a forfeit has no
  /// engine `end` event).
  void finish(int? winner) {
    _flush = true;
    if (_ended || winner == null || _buffer.any((e) => e.type == 'end')) {
      return;
    }
    _buffer.add(
      BattleEvent(_newest, 'end', {'winner': _swap ? 1 - winner : winner}),
    );
  }

  bool _flush = false;

  /// Snapshot view of stage side [side] (null before the first `snap`).
  SideView? view(int side) => _views[side];

  @override
  List<StageEvent> advance(double dt) {
    if (!_started && !_flush) return const [];
    _clock += dt * match.tickHz;
    final target = (_newest - delayTicks).toDouble();
    // Never run ahead of the server; catch up when far behind.
    if (_clock > target) _clock = target;
    if (target - _clock > 10) _clock = target - 2;
    final due = <BattleEvent>[];
    while (_buffer.isNotEmpty && _buffer.first.tick <= _clock) {
      due.add(_buffer.removeAt(0));
    }
    // After the server's `end`, play out everything left.
    if (_flush) {
      due.addAll(_buffer);
      _buffer.clear();
    }
    for (final e in due) {
      _track(e);
    }
    final out = translate(
      due,
      moves: (side, slot) =>
          slot < moves[side].length ? moves[side][slot] : moves[side].first,
      tickHz: match.tickHz,
    );
    if (out.any((e) => e is StageEnd)) _ended = true;
    return out;
  }

  void _track(BattleEvent e) {
    switch (e.type) {
      case 'status':
        _status[e.i('target') ?? 0].add(e.s('status') ?? '');
      case 'shield':
        _status[e.i('side') ?? 0].add('shield');
      case 'stage':
        _status[e.i('side') ?? 0].add((e.i('stage') ?? 0) > 0 ? 'up' : 'down');
      case 'expire':
        final kind = e.s('kind') ?? '';
        final s = _status[e.i('side') ?? 0];
        if (const {'poison', 'paralyze', 'shield'}.contains(kind)) {
          s.remove(kind);
        } else {
          s
            ..remove('up')
            ..remove('down');
        }
    }
  }

  @override
  StageFighterState fighter(int side) {
    final v = _views[side];
    final maxHp = match.fighters[_swap ? 1 - side : side].maxHp;
    final s = _status[side];
    final maxBars =
        v?.maxBars ?? match.fighters[_swap ? 1 - side : side].maxBars;
    var gauge = (v?.gauge ?? 0) / 10000;
    if (v != null && !v.casting && v.bars < maxBars) {
      // Interpolate between snaps (≈ 280 per tick at equal speed).
      gauge += (_clock - _snapTick).clamp(0, 5) * 280 / 10000;
    }
    return StageFighterState(
      maxHp: v?.maxHp ?? maxHp,
      gauge: gauge.clamp(0.0, maxBars.toDouble()),
      maxBars: maxBars,
      casting: v?.casting ?? false,
      poisoned: s.contains('poison'),
      paralyzed: s.contains('paralyze'),
      shield: s.contains('shield') ? 0.3 : 0,
      statUp: s.contains('up'),
      statDown: s.contains('down'),
    );
  }
}
