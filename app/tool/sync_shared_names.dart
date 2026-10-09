// Copies shared/names/display_name_words.json (the server's preset vocabulary
// for online display names, docs/BACKEND.md §5 setDisplayName) into the app's
// asset folder (Flutter cannot bundle files outside the package).
//   cd app && dart run tool/sync_shared_names.dart
// test/features/online/display_name_test.dart fails when the copies drift.
import 'dart:io';

void main() {
  final src = File('../shared/names/display_name_words.json');
  final dst = File('assets/names/display_name_words.json');
  dst.parent.createSync(recursive: true);
  src.copySync(dst.path);
  stdout.writeln('synced ${src.path} -> ${dst.path}');
}
