import 'dart:convert';
import 'dart:typed_data';

import 'glb_writer.dart';

/// Parsed GLB container: the JSON document and the BIN chunk.
///
/// Performs the structural checks of glTF 2.0 §4.4 (header, chunk types,
/// lengths, 4-byte alignment) and throws [FormatException] on violation.
/// Used by tests and by debug tooling.
class GlbDocument {
  GlbDocument._(this.json, this.bin, this.totalLength);

  factory GlbDocument.parse(Uint8List bytes) {
    if (bytes.length < 20) throw const FormatException('GLB too short');
    final bd = ByteData.sublistView(bytes);
    if (bd.getUint32(0, Endian.little) != GlbWriter.glbMagic) {
      throw const FormatException('bad GLB magic');
    }
    final version = bd.getUint32(4, Endian.little);
    if (version != 2) throw FormatException('unsupported GLB version $version');
    final length = bd.getUint32(8, Endian.little);
    if (length != bytes.length) {
      throw FormatException('header length $length != ${bytes.length}');
    }
    var o = 12;
    final jsonLen = bd.getUint32(o, Endian.little);
    if (bd.getUint32(o + 4, Endian.little) != GlbWriter.chunkJson) {
      throw const FormatException('first chunk is not JSON');
    }
    if (jsonLen % 4 != 0) throw const FormatException('JSON chunk unaligned');
    o += 8;
    if (o + jsonLen > length) {
      throw const FormatException('JSON chunk overflow');
    }
    final json = jsonDecode(
      utf8.decode(bytes.sublist(o, o + jsonLen)),
    ) as Map<String, Object?>;
    o += jsonLen;
    Uint8List? bin;
    if (o < length) {
      final binLen = bd.getUint32(o, Endian.little);
      if (bd.getUint32(o + 4, Endian.little) != GlbWriter.chunkBin) {
        throw const FormatException('second chunk is not BIN');
      }
      if (binLen % 4 != 0) throw const FormatException('BIN chunk unaligned');
      o += 8;
      if (o + binLen > length) throw const FormatException('BIN overflow');
      bin = Uint8List.sublistView(bytes, o, o + binLen);
      o += binLen;
    }
    if (o != length) throw const FormatException('trailing bytes after chunks');
    return GlbDocument._(json, bin, length);
  }

  final Map<String, Object?> json;
  final Uint8List? bin;
  final int totalLength;

  List<Map<String, Object?>> list(String key) =>
      ((json[key] as List?) ?? const []).cast<Map<String, Object?>>();

  /// Raw bytes of bufferView [index].
  Uint8List bufferViewBytes(int index) {
    final view = list('bufferViews')[index];
    final offset = (view['byteOffset'] as int?) ?? 0;
    final len = view['byteLength']! as int;
    return Uint8List.sublistView(bin!, offset, offset + len);
  }

  /// Float values of a FLOAT accessor (tightly packed).
  Float32List floatAccessor(int index) {
    final a = list('accessors')[index];
    if (a['componentType'] != GltfComponentType.float) {
      throw const FormatException('not a float accessor');
    }
    final bytes = bufferViewBytes(a['bufferView']! as int);
    final n =
        (a['count']! as int) * GlbWriter.componentsOf(a['type']! as String);
    final copy = Uint8List.fromList(bytes.sublist(0, n * 4));
    return copy.buffer.asFloat32List();
  }

  /// Bytes of image [index] (embedded via bufferView).
  Uint8List imageBytes(int index) =>
      bufferViewBytes(list('images')[index]['bufferView']! as int);

  /// Checks internal consistency of buffers, bufferViews, accessors and
  /// references. Returns a list of human readable problems (empty if OK).
  List<String> validate() {
    final problems = <String>[];
    final buffers = list('buffers');
    if (buffers.length != 1) problems.add('expected exactly one buffer');
    final binLen = bin?.length ?? 0;
    if (buffers.isNotEmpty) {
      final bl = buffers.first['byteLength'] as int;
      if (bl > binLen || binLen - bl > 3) {
        problems.add('buffer.byteLength $bl does not match BIN $binLen');
      }
    }
    final views = list('bufferViews');
    for (final (i, v) in views.indexed) {
      final off = (v['byteOffset'] as int?) ?? 0;
      final len = v['byteLength'] as int;
      if (off + len > binLen) problems.add('bufferView $i out of range');
      if (off % 4 != 0) problems.add('bufferView $i not 4-byte aligned');
    }
    for (final (i, a) in list('accessors').indexed) {
      final view = a['bufferView'] as int?;
      if (view == null || view >= views.length) {
        problems.add('accessor $i bad bufferView');
        continue;
      }
      final compSize = switch (a['componentType']) {
        5120 || 5121 => 1,
        5122 || 5123 => 2,
        5125 || 5126 => 4,
        _ => 0,
      };
      if (compSize == 0) problems.add('accessor $i bad componentType');
      final need =
          (a['count'] as int) *
          GlbWriter.componentsOf(a['type'] as String) *
          compSize;
      final have =
          (views[view]['byteLength'] as int) - ((a['byteOffset'] as int?) ?? 0);
      if (need > have) problems.add('accessor $i needs $need > $have bytes');
    }
    final accessors = list('accessors');
    for (final (mi, m) in list('meshes').indexed) {
      for (final p in (m['primitives'] as List).cast<Map<String, Object?>>()) {
        final attrs = (p['attributes'] as Map).cast<String, int>();
        final pos = attrs['POSITION'];
        if (pos == null) {
          problems.add('mesh $mi primitive without POSITION');
        } else if (!accessors[pos].containsKey('min') ||
            !accessors[pos].containsKey('max')) {
          problems.add('mesh $mi POSITION without min/max');
        }
        final counts = attrs.values.map((i) => accessors[i]['count']).toSet();
        if (counts.length != 1) {
          problems.add('mesh $mi attribute count mismatch');
        }
        final mat = p['material'] as int?;
        if (mat != null && mat >= list('materials').length) {
          problems.add('mesh $mi bad material');
        }
      }
    }
    final nodes = list('nodes');
    for (final (i, n) in nodes.indexed) {
      final mesh = n['mesh'] as int?;
      if (mesh != null && mesh >= list('meshes').length) {
        problems.add('node $i bad mesh');
      }
      for (final c in ((n['children'] as List?) ?? const []).cast<int>()) {
        if (c >= nodes.length) problems.add('node $i bad child');
      }
    }
    for (final (i, t) in list('textures').indexed) {
      if ((t['source'] as int) >= list('images').length) {
        problems.add('texture $i bad source');
      }
    }
    return problems;
  }
}
