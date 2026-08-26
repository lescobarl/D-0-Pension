import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A reusable row displaying a label and value pair.
///
/// Used across multiple views (FactAsig, PensionMod40, Inversion, etc.)
/// to eliminate duplicated [_buildResultRow] methods.
///
/// Compact design for mobile with clear visual hierarchy.
class ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;
  final IconData? leadingIcon;

  const ResultRow({
    super.key,
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 16, color: AppTheme.textHint),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: AppTheme.textSecondary,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 180),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: valueColor != null
                    ? valueColor!.withValues(alpha: 0.08)
                    : (isBold
                          ? AppTheme.primary.withValues(alpha: 0.08)
                          : null),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: AppTheme.fontSizeResultValue,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color:
                      valueColor ??
                      (isBold ? AppTheme.primary : AppTheme.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
