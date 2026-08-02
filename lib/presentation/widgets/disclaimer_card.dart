import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// DESCARGO DE RESPONSABILIDAD shown as a modal dialog.
///
/// Opened from the top-right AppBar button (info/shield icon) via
/// [DisclaimerCard.show]. A modal dialog is used instead of an inline
/// ExpansionTile so it always opens reliably regardless of scroll position
/// or surrounding layout constraints.
class DisclaimerCard {
  DisclaimerCard._();

  /// Opens the disclaimer as a modal dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _DisclaimerDialog(),
    );
  }
}

class _DisclaimerDialog extends StatelessWidget {
  const _DisclaimerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.gpp_maybe_outlined, color: AppTheme.accentLight, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Descargo de Responsabilidad',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeCardTitle,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Esta calculadora de pensiones por la Ley 73 y de Modalidad 40 fue '
                      'diseñada como una herramienta de estimación. Los resultados '
                      'dependen completamente de los datos ingresados por el usuario y '
                      'no constituyen asesoría financiera personalizada.',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBodySmall,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildBulletBlock(
                      icon: Icons.check_circle_outline,
                      iconColor: AppTheme.successColor,
                      title: 'Esta herramienta SÍ puede ayudarte a:',
                      items: const [
                        'Estimar tu pensión mensual por Ley 73 con o sin Modalidad 40.',
                        'Calcular inversión, retorno, pago retroactivo y flujos de pensión.',
                        'Comparar hasta 10 escenarios diferentes con proyección gráfica (versión PRO).',
                        'Calcular el flujo de pensiones cobradas con actualización por inflación (versión PRO).',
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildBulletBlock(
                      icon: Icons.cancel_outlined,
                      iconColor: AppTheme.errorColor,
                      title: 'Esta herramienta NO puede:',
                      items: const [
                        'Predecir con exactitud cambios futuros en leyes o indicadores económicos.',
                        'Reemplazar una asesoría financiera personalizada.',
                        'Garantizar los resultados si hay errores en los datos que ingresas.',
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Footer / close button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletBlock({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<String> items,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppTheme.fontSizeBodySmall,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(left: 10, top: 1),
                  child: Text(
                    '• $item',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeTableData,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
