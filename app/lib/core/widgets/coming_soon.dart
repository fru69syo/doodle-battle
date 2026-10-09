import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 「じゅんびちゅう」 badge for features that need the (not yet configured)
/// server.
class ComingSoonNote extends StatelessWidget {
  const ComingSoonNote({super.key, this.text = 'じゅんびちゅう'});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.gold,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.construction, color: AppColors.ink),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
