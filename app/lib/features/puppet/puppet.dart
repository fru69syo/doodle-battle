/// 2.5D puppets: a child's drawing auto-rigged into a 2D mesh with skinned
/// limbs, animated with procedural clips and drawn with
/// `Canvas.drawVertices`. See docs/PUPPET.md.
library;

export 'anim/clips.dart' show Anim, kAnimLength, kAnimImpact, AnimContext;
export 'editor/character_joints_page.dart';
export 'editor/joint_editor_screen.dart' show JointEditorScreen;
export 'mesh/puppet_mesh.dart' show PuppetMesh, BuildOptions;
export 'puppet_builder.dart';
export 'puppet_look.dart';
export 'puppet_parts.dart';
export 'puppet_store.dart';
export 'render/aura.dart';
export 'render/puppet_sprite.dart';
export 'render/puppet_view.dart';
export 'rig/character_rig.dart';
export 'rig/limb_hints.dart' show HintStroke, LimbHint;
