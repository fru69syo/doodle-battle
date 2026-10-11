import 'package:doodle_battle/core/providers.dart';
import 'package:doodle_battle/data/drawing_loop_storage.dart';
import 'package:doodle_battle/data/memory_character_repository.dart';
import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/features/drawing_loop/display_image.dart';
import 'package:doodle_battle/features/drawing_loop/parts/composite.dart';
import 'package:doodle_battle/features/puppet/character_puppet.dart';
import 'package:doodle_battle/features/puppet/editor/rig_edits.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/puppet_store.dart';
import 'package:doodle_battle/features/puppet/render/puppet_view.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

void main() {
  test(
    'stored character: edited rig, drawn parts as appendages, look',
    () async {
      final hero = samplePng(Sample.hero);
      final c = testCharacter(level: 50).copyWith(
        cosmetics: const CharacterCosmetics(
          parts: [
            CharacterPart(
              id: 'h1',
              type: PartType.hat,
              transform: PartTransform(cx: 0.5, cy: -0.05, scale: 0.4),
            ),
          ],
        ),
      );
      final loop = InMemoryDrawingLoopStorage();
      await loop.writeAsset(c.id, 'part_h1', samplePng(Sample.blob));
      final store = InMemoryPuppetStore();
      final container = ProviderContainer(
        overrides: [
          characterRepositoryProvider.overrideWithValue(
            InMemoryCharacterRepository([(c, hero)]),
          ),
          drawingLoopStorageProvider.overrideWithValue(loop),
          puppetStoreProvider.overrideWithValue(store),
          puppetBuilderProvider.overrideWithValue(
            PuppetBuilder(runner: syncRunner),
          ),
          compositeRunnerProvider.overrideWithValue(
            (r) async => renderComposite(r),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The child moved the right hand.
      final auto = autoRigPng(hero);
      final arm = auto.limbs.indexWhere((l) => l.kind == LimbKind.arm);
      await store.saveRig(c.id, RigEdits.moveTip(auto, arm, const P2(5, 5)));

      final spec = (await container.read(
        characterPuppetSpecProvider(c).future,
      ))!;
      expect(spec.look.legend, isTrue);
      final rig = spec.rig!;
      expect(rig.validate(), isNull);
      final hat = rig.limbs.firstWhere((l) => l.part == 'h1');
      expect(rig.limbs[hat.attach!].kind, LimbKind.head);
      expect(rig.limbs[arm].edited, isTrue, reason: 'the edit survives');
      expect(rig.width, greaterThan(auto.width * 0.5));
      // It builds.
      final mesh = buildPuppetSync(spec);
      expect(mesh.rig.limbs.length, rig.limbs.length);

      // Without parts: the stored rig on the base picture.
      final plain = (await container.read(
        characterPuppetSpecProvider(testCharacter(id: 'c_1', level: 3)).future,
      ))!;
      expect(plain.png, hero);
      expect(plain.rig!.limbs[arm].tip, const P2(5, 5));
      expect(plain.look.legend, isFalse);
      expect(pngSize(hero).$1, greaterThan(10));
    },
  );
}
