import 'dart:convert';
import 'dart:io';

/// Reads a JSON object file; null when missing or corrupt.
Future<Map<String, Object?>?> readJsonFile(File file) async {
  try {
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// Writes [json] atomically (temp file + rename) so a crash never leaves a
/// half-written file.
Future<void> writeJsonFile(File file, Map<String, Object?> json) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(jsonEncode(json), flush: true);
  await tmp.rename(file.path);
}
