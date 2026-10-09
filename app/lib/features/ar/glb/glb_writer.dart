import 'dart:convert';
import 'dart:typed_data';

/// glTF component types.
abstract final class GltfComponentType {
  static const unsignedShort = 5123;
  static const unsignedInt = 5125;
  static const float = 5126;
}

/// glTF bufferView targets.
abstract final class GltfTarget {
  static const arrayBuffer = 34962;
  static const elementArrayBuffer = 34963;
}

/// Minimal writer for a single-buffer glTF 2.0 binary (.glb).
///
/// Collects binary payloads into one buffer (each bufferView 4-byte aligned)
/// and serialises `{json, bin}` into the GLB container described in the
/// glTF 2.0 spec §4.4.
class GlbWriter {
  final _bin = BytesBuilder(copy: false);
  int _length = 0;

  final bufferViews = <Map<String, Object?>>[];
  final accessors = <Map<String, Object?>>[];

  int get binLength => _length;

  /// Appends [data] as a new bufferView and returns its index.
  int addBufferView(Uint8List data, {int? target}) {
    _pad();
    final view = <String, Object?>{
      'buffer': 0,
      'byteOffset': _length,
      'byteLength': data.length,
    };
    if (target != null) view['target'] = target;
    _bin.add(data);
    _length += data.length;
    bufferViews.add(view);
    return bufferViews.length - 1;
  }

  /// Adds a float accessor (SCALAR/VEC2/VEC3/VEC4) with its own bufferView.
  int addFloatAccessor(
    List<double> values,
    String type, {
    int? target = GltfTarget.arrayBuffer,
    bool withBounds = false,
  }) {
    final n = componentsOf(type);
    if (values.length % n != 0) {
      throw ArgumentError(
        'values length ${values.length} not a multiple of $n',
      );
    }
    final data = Float32List.fromList(values);
    final view = addBufferView(data.buffer.asUint8List(), target: target);
    final accessor = <String, Object?>{
      'bufferView': view,
      'componentType': GltfComponentType.float,
      'count': values.length ~/ n,
      'type': type,
    };
    if (withBounds) {
      final min = List<double>.filled(n, double.infinity);
      final max = List<double>.filled(n, double.negativeInfinity);
      for (var i = 0; i < data.length; i++) {
        final c = i % n;
        // Use the float32-rounded values so bounds match the stored data.
        if (data[i] < min[c]) min[c] = data[i];
        if (data[i] > max[c]) max[c] = data[i];
      }
      accessor['min'] = min;
      accessor['max'] = max;
    }
    accessors.add(accessor);
    return accessors.length - 1;
  }

  /// Adds an UNSIGNED_SHORT index accessor.
  int addIndexAccessor(List<int> indices) {
    final data = Uint16List.fromList(indices);
    final view = addBufferView(
      data.buffer.asUint8List(),
      target: GltfTarget.elementArrayBuffer,
    );
    accessors.add({
      'bufferView': view,
      'componentType': GltfComponentType.unsignedShort,
      'count': indices.length,
      'type': 'SCALAR',
    });
    return accessors.length - 1;
  }

  /// Serialises the GLB. [json] must not contain `buffers`, `bufferViews` or
  /// `accessors`; they are filled in from this writer.
  Uint8List build(Map<String, Object?> json) {
    _pad();
    final doc = <String, Object?>{
      ...json,
      if (accessors.isNotEmpty) 'accessors': accessors,
      if (bufferViews.isNotEmpty) 'bufferViews': bufferViews,
      'buffers': [
        {'byteLength': _length},
      ],
    };
    final jsonBytes = utf8.encode(jsonEncode(doc));
    final jsonPadded = _align4(jsonBytes.length);
    final bin = _bin.toBytes();
    final binPadded = _align4(bin.length);
    final total = 12 + 8 + jsonPadded + 8 + binPadded;

    final out = Uint8List(total);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, glbMagic, Endian.little);
    bd.setUint32(4, 2, Endian.little);
    bd.setUint32(8, total, Endian.little);
    var o = 12;
    bd.setUint32(o, jsonPadded, Endian.little);
    bd.setUint32(o + 4, chunkJson, Endian.little);
    o += 8;
    out.setRange(o, o + jsonBytes.length, jsonBytes);
    // JSON chunk is padded with spaces (0x20).
    out.fillRange(o + jsonBytes.length, o + jsonPadded, 0x20);
    o += jsonPadded;
    bd.setUint32(o, binPadded, Endian.little);
    bd.setUint32(o + 4, chunkBin, Endian.little);
    o += 8;
    out.setRange(o, o + bin.length, bin);
    // BIN chunk padding is already zero.
    return out;
  }

  void _pad() {
    final pad = _align4(_length) - _length;
    if (pad > 0) {
      _bin.add(Uint8List(pad));
      _length += pad;
    }
  }

  static int _align4(int n) => (n + 3) & ~3;

  static const glbMagic = 0x46546C67; // "glTF"
  static const chunkJson = 0x4E4F534A; // "JSON"
  static const chunkBin = 0x004E4942; // "BIN\0"

  static int componentsOf(String type) => switch (type) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    'MAT4' => 16,
    _ => throw ArgumentError('unknown accessor type $type'),
  };
}
