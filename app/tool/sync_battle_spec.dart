// Copies shared/battle_spec/battle_spec.json into the app's asset folder
// (Flutter cannot bundle files outside the package).
//   cd app && dart run tool/sync_battle_spec.dart
import 'dart:io';

void main() {
  final src = File('../shared/battle_spec/battle_spec.json');
  final dst = File('assets/battle/battle_spec.json');
  dst.parent.createSync(recursive: true);
  src.copySync(dst.path);
  stdout.writeln('synced ${src.path} -> ${dst.path}');
}
