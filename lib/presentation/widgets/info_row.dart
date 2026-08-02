import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A reusable row displaying a label and value with space-between layout.
///
/// Used in FinanciamientoView and CostoMod40View to eliminate
/// duplicated [_buildInfoRow] methods.
///
/// Compact design for mobile with clear visual hierarchy.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? labelColor;
  final Color? valueColor;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.isBold = false,
    this.labelColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isBold ? AppTheme.fontSizeBody : AppTheme.fontSizeBody,
                color: labelColor ?? AppTheme.textSecondary,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: isBold ? AppTheme.fontSizeTotalMedium : AppTheme.fontSizeResultValue,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? (isBold ? AppTheme.accent : AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
