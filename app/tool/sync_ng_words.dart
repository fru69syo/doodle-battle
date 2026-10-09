// Copies shared/ng_words/ng_words.json into the app's asset folder (Flutter
// cannot bundle files outside the package). The vector files are read
// straight from shared/ by the tests and are not bundled.
//   cd app && dart run tool/sync_ng_words.dart
import 'dart:io';

void main() {
  final src = File('../shared/ng_words/ng_words.json');
  final dst = File('assets/ng_words/ng_words.json');
  dst.parent.createSync(recursive: true);
  src.copySync(dst.path);
  stdout.writeln('synced ${src.path} -> ${dst.path}');
}
