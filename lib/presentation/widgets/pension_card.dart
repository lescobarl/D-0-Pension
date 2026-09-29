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

  /// Optional compact key-value cells rendered inside the card as a single
  /// horizontal row, each entry distributed equally across the width.
  final List<List<String>>? inlineFields;

  /// Whether to show the copy-to-clipboard button in the title row.
  final bool showCopyButton;

  const PensionCard({
    super.key,
    required this.title,
    required this.annualAmount,
    required this.monthlyAmount,
    this.extraCopyValues,
    this.inlineFields,
    this.showCopyButton = true,
  });

  void _copyToClipboard(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln(title);
    buffer.writeln('Anual: ${FormatUtils.formatCurrencyInt(annualAmount)}');
    buffer.writeln(
      'Mensual (30 días): ${FormatUtils.formatCurrencyInt(monthlyAmount)}',
    );
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
          colors: [AppTheme.primary, AppTheme.primaryDark],
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
        padding: const EdgeInsets.all(2),
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
                if (showCopyButton)
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
            const SizedBox(height: 2),
            // Annual amount: "Anual: $X" en una sola línea (ahorra altura).
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Row(
                children: [
                  const Text(
                    'Anual:',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeBodySmall,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      FormatUtils.formatCurrencyInt(annualAmount),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: AppTheme.fontSizeTotalLarge,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            // Monthly amount: "Mensual (30 días): $X" en una sola línea.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Row(
                children: [
                  const Text(
                    'Mensual (30 días):',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeBodySmall,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      FormatUtils.formatCurrencyInt(monthlyAmount),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: AppTheme.fontSizeTotalMedium,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentLight,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (inlineFields != null && inlineFields!.isNotEmpty) ...[
              const SizedBox(height: 2),
              // Responsivo: en celular (< 600) los campos se apilan en
              // columna para evitar amontonamiento; en pantallas anchas
              // se muestran en una sola fila.
              LayoutBuilder(
                builder: (context, constraints) {
                  final cells = <Widget>[
                    for (final field in inlineFields!)
                      _buildInlineFieldCell(field),
                  ];
                  if (constraints.maxWidth < 600) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < cells.length; i++) ...[
                          if (i > 0) const SizedBox(height: 2),
                          cells[i],
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < cells.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppTheme.spacingSm),
                        Expanded(child: cells[i]),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Celda compacta para un campo [label, value] dentro de la tarjeta.
  /// Muestra "Nombre: Valor" en una sola línea (nombre a la izquierda,
  /// valor a la derecha) para ahorrar altura.
  Widget _buildInlineFieldCell(List<String> field) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              field[0],
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBodySmall - 2,
                color: Colors.white60,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              field[1],
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBodySmall,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentLight,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
