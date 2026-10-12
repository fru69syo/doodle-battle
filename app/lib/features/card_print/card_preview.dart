import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/element_badge.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/stats.dart';
import 'card_content.dart';

/// On-screen preview of a printed card (same [CardContent] and the same
/// layout as `card_pdf.dart`, drawn with Flutter widgets so it works without
/// a platform rasteriser). Laid out at 4 logical px per mm and scaled.
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.card, this.width = 252});

  final CardContent card;
  final double width;

  static const _u = 4.0; // px per mm in the unscaled layout

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * cardHeightMm / cardWidthMm,
    child: FittedBox(
      child: SizedBox(
        width: cardWidthMm * _u,
        height: cardHeightMm * _u,
        child: _CardBody(card: card),
      ),
    ),
  );
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.card});
  final CardContent card;

  static const _u = CardPreview._u;

  @override
  Widget build(BuildContext context) {
    final el = AppColors.element(card.element);
    final (Color frame, double frameWidth) = switch (card.stage) {
      EvolutionStage.normal => (el, 1.4 * _u),
      EvolutionStage.kagayaki => (el, 2.0 * _u),
      EvolutionStage.densetsu => (AppColors.gold, 2.4 * _u),
    };
    final accent = card.stage == EvolutionStage.densetsu ? AppColors.gold : el;
    final bodyColour = switch (card.background) {
      CardBackground.plain => Color.lerp(Colors.white, el, 0.12)!,
      CardBackground.hoshi => const Color(0xFFFFF3B0),
      CardBackground.hana => const Color(0xFFFFE0EE),
      CardBackground.niji => const Color(0xFFEFF4FF),
    };
    const ink = AppColors.ink;
    Widget stat(StatKind k) => Expanded(
      child: Row(
        children: [
          SizedBox(
            width: 11 * _u,
            child: Text(
              cardStatLabel(k),
              style: const TextStyle(fontSize: 8.5, color: ink),
            ),
          ),
          for (var i = 0; i < cardMaxStars; i++)
            Icon(
              Icons.star_rounded,
              size: 2.9 * _u,
              color: i < (card.stars[k] ?? 1)
                  ? AppColors.gold
                  : const Color(0xFFD9D3C7),
            ),
        ],
      ),
    );
    Widget move(String name) => Expanded(
      child: Container(
        height: 4.6 * _u,
        margin: const EdgeInsets.all(0.4 * _u),
        padding: const EdgeInsets.symmetric(horizontal: _u),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: el, width: 0.8),
          borderRadius: BorderRadius.circular(2.3 * _u),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ),
    );
    final image = card.image;
    return Container(
      padding: EdgeInsets.all(frameWidth),
      decoration: BoxDecoration(
        color: frame,
        borderRadius: BorderRadius.circular(3 * _u),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(2 * _u, 1.6 * _u, 2 * _u, 1.4 * _u),
        decoration: BoxDecoration(
          color: bodyColour,
          borderRadius: BorderRadius.circular(2 * _u),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      card.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                ),
                Text(
                  'Lv${card.level}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1.2 * _u),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      padding: const EdgeInsets.all(1.5 * _u),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2 * _u),
                        border: Border.all(
                          color: accent,
                          width: card.stage == EvolutionStage.normal
                              ? 0.8
                              : 1.6,
                        ),
                      ),
                      child: image == null
                          ? Icon(elementIcon(card.element), color: el, size: 80)
                          : Image.memory(image, fit: BoxFit.contain),
                    ),
                  ),
                  if (card.stage != EvolutionStage.normal)
                    Positioned(
                      left: _u,
                      top: _u,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 1.4 * _u,
                          vertical: 0.3 * _u,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2 * _u),
                        ),
                        child: Text(
                          cardStageLabel(card.stage),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 1.4 * _u),
            Align(
              alignment: Alignment.centerLeft,
              child: ElementBadge(card.element),
            ),
            const SizedBox(height: 1.2 * _u),
            Row(children: [stat(StatKind.hp), stat(StatKind.atk)]),
            const SizedBox(height: 0.6 * _u),
            Row(children: [stat(StatKind.def), stat(StatKind.spd)]),
            const SizedBox(height: 1.2 * _u),
            Row(children: [move(card.moves[0]), move(card.moves[1])]),
            Row(children: [move(card.moves[2]), move(card.moves[3])]),
            const SizedBox(height: 1.2 * _u),
            Row(
              children: [
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      appDisplayName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Spacer(),
                Text(
                  'うまれた ひ ${cardDateLabel(card.date)}',
                  style: const TextStyle(fontSize: 7.5, color: ink),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
