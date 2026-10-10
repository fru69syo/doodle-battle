import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../battle_ui/move_labels.dart';
import '../monetization/card_frames.dart';
import '../monetization/monetization_service.dart';
import 'card_content.dart';
import 'card_output.dart';
import 'card_pdf.dart';
import 'card_preview.dart';

/// What the parent asked for.
enum CardAction { print, share }

/// Preview of the cards for [characterIds], then print / share (both behind
/// the parental gate).
class CardPrintScreen extends ConsumerStatefulWidget {
  const CardPrintScreen({super.key, required this.characterIds});
  final List<String> characterIds;

  @override
  ConsumerState<CardPrintScreen> createState() => _CardPrintScreenState();
}

class _CardPrintScreenState extends ConsumerState<CardPrintScreen> {
  CardLayout _layout = CardLayout.a4Sheet;
  bool _busy = false;

  /// Card contents once the spec and every picture are loaded.
  List<CardContent>? _cards(List<Character> chars, BattleSpec spec) {
    final framesOwned =
        ref
            .watch(settingsProvider)
            .value
            ?.entitlements
            .contains(Product.framePack.id) ??
        false;
    final out = <CardContent>[];
    for (final id in widget.characterIds) {
      final c = chars.where((x) => x.id == id).firstOrNull;
      if (c == null) continue;
      final image = ref.watch(characterImageProvider(c.id));
      if (image.isLoading) return null;
      out.add(
        cardContentFor(
          spec,
          c,
          image: image.value,
          moveLabel: characterMoveLabel,
          background: framesOwned
              ? _background(CardFrame.byId(c.cardFrame))
              : CardBackground.plain,
        ),
      );
    }
    return out;
  }

  static CardBackground _background(CardFrame? f) => switch (f) {
    null => CardBackground.plain,
    CardFrame.hoshi => CardBackground.hoshi,
    CardFrame.hana => CardBackground.hana,
    CardFrame.niji => CardBackground.niji,
  };

  Future<void> _send(CardAction action, List<CardContent> cards) async {
    if (_busy) return;
    // Printing and sharing leave the app: an adult has to pass the gate.
    final ok = await ref.read(parentalGateProvider).verify(context);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    var failed = false;
    try {
      final fonts = await ref.read(cardFontsProvider.future);
      final pdf = await buildCardPdf(cards, fonts: fonts, layout: _layout);
      final out = ref.read(cardOutputProvider);
      final now = ref.read(clockProvider)();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      switch (action) {
        case CardAction.print:
          await out.printPdf(pdf, name: 'らくがきバトル カード');
        case CardAction.share:
          await out.sharePdf(pdf, filename: 'rakugaki_cards_$stamp.pdf');
      }
    } on Object {
      failed = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (failed) {
      await showKidMessage(
        context,
        'うまく できなかったよ。もういちど ためしてね',
        icon: Icons.sentiment_dissatisfied,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chars = ref.watch(charactersProvider).value;
    final spec = ref.watch(battleSpecProvider).value;
    final cards = chars == null || spec == null ? null : _cards(chars, spec);
    return Scaffold(
      appBar: AppBar(title: const Text('キャラカード')),
      body: SafeArea(
        child: cards == null
            ? const Center(child: CircularProgressIndicator())
            : cards.isEmpty
            ? const Center(
                child: Text(
                  'キャラが みつからないよ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (i, c) in cards.indexed)
                        CardPreview(
                          key: Key('card-preview-$i'),
                          card: c,
                          width: cards.length == 1 ? 252 : 160,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: SegmentedButton<CardLayout>(
                      key: const Key('card-layout'),
                      segments: const [
                        ButtonSegment(
                          value: CardLayout.a4Sheet,
                          icon: Icon(Icons.grid_view),
                          label: Text('A4に ならべる'),
                        ),
                        ButtonSegment(
                          value: CardLayout.single,
                          icon: Icon(Icons.crop_portrait),
                          label: Text('1まいずつ'),
                        ),
                      ],
                      selected: {_layout},
                      onSelectionChanged: (s) =>
                          setState(() => _layout = s.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'いんさつと おくるのは おうちのひとと いっしょに してね',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('card-print'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                    ),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(),
                          )
                        : const Icon(Icons.print),
                    label: const Text('いんさつ する'),
                    onPressed: _busy
                        ? null
                        : () => _send(CardAction.print, cards),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('card-share'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('PDFで おくる・ほぞん'),
                    onPressed: _busy
                        ? null
                        : () => _send(CardAction.share, cards),
                  ),
                ],
              ),
      ),
    );
  }
}
