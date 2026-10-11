/// Which 2.5D look a character is drawn with (docs/PUPPET.md §0). The rule
/// reads the hidden late-bloomer state, so it lives in the domain layer;
/// UI code only ever receives the resulting look (`PuppetLook`).
library;

import 'battle_v3/battle_v3.dart';
import 'character_v2.dart';

/// True when [c] is drawn with the simple look (3 flat colours, body-only
/// rig, half effects): only the hidden late bloomer before its Lv50
/// rebuild. Every character gets the でんせつ look from Lv50.
bool drawsSimpleLook(CharacterV2 c, [V3Spec s = const V3Spec()]) {
  final g = c.genome(s);
  return g.isBloomer && !g.rebornAt(c.level);
}
