import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';

/// A reusable highlighted card showing pension amounts (annual + monthly).
///
/// Features a gradient background and a copy-to-clipboard button for easy
/// value extraction.
class PensionCard extends StatelessWidget {
  final String title;
  final double annualAmount;
  final double monthlyAmount;

  /// Optional extra key-value lines to include when copying.
  /// Each entry is a pair of [label, value] strings.
  final List<List<String>>? extraCopyValues;

  const PensionCard({
    super.key,
    required this.title,
    required this.annualAmount,
    required this.monthlyAmount,
    this.extraCopyValues,
  });

  void _copyToClipboard(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln(title);
    buffer.writeln('Anual: ${FormatUtils.formatCurrency(annualAmount)}');
    buffer.writeln('Mensual (30 días): ${FormatUtils.formatCurrency(monthlyAmount)}');
    if (extraCopyValues != null && extraCopyValues!.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('--- DATOS DE CAPTURA ---');
      for (final entry in extraCopyValues!) {
        buffer.writeln('${entry[0]}: ${entry[1]}');
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Valores copiados al portapapeles'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            AppTheme.primaryDark,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          children: [
            // Title row with copy button
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeSectionTitle,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _copyToClipboard(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.copy,
                      size: 16,
                      color: AppTheme.accentLight,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSm),
            // Annual amount
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Column(
                children: [
                  const Text(
                    'Anual',
                    style: TextStyle(fontSize: AppTheme.fontSizeBodySmall, color: Colors.white60),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    FormatUtils.formatCurrency(annualAmount),
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeTotalLarge,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            // Monthly amount
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Column(
                children: [
                  const Text(
                    'Mensual (30 días)',
                    style: TextStyle(fontSize: AppTheme.fontSizeBodySmall, color: Colors.white60),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    FormatUtils.formatCurrency(monthlyAmount),
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeTotalMedium,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
