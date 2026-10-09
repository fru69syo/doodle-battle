import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Large, colourful, rounded menu button for children (≥ 72 dp tall).
class BigActionButton extends StatelessWidget {
  const BigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = AppColors.primary,
    this.subtitle,
    this.height = 88,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: enabled ? color : AppColors.disabled,
        borderRadius: BorderRadius.circular(32),
        elevation: enabled ? 4 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 44, color: Colors.white),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
