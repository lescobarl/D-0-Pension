import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
                      'Esta aplicación NO es una aplicación oficial del Instituto '
                      'Mexicano del Seguro Social (IMSS) ni de ninguna dependencia de '
                      'gobierno. No está afiliada, respaldada ni patrocinada por el '
                      'IMSS. «Ley 73» e «IMSS» se mencionan únicamente para describir '
                      'el marco legal de cálculo que utiliza la herramienta.',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBodySmall,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Esta calculadora es una herramienta de estimación con fines '
                      'informativos: los resultados se generan a partir de los datos '
                      'que tú ingresas y de las tablas vigentes incluidas en la '
                      'aplicación (UMA, salario mínimo e inflación); no son un '
                      'cálculo oficial ni constituyen asesoría financiera, fiscal o '
                      'legal personalizada. El monto definitivo lo determina el IMSS '
                      'al validar tu expediente.',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBodySmall,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Consulta siempre la información oficial del IMSS en:',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBodySmall,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _openImss,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'https://www.gob.mx/imss',
                              style: TextStyle(
                                fontSize: AppTheme.fontSizeBodySmall,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildBulletBlock(
                      icon: Icons.check_circle_outline,
                      iconColor: AppTheme.successColor,
                      title: 'Esta herramienta SÍ puede ayudarte a:',
                      items: const [
                        'Estimar tu pensión mensual por Ley 73, con o sin Modalidad 40, conforme a la fórmula vigente.',
                        'Calcular inversión, retorno, pago retroactivo y flujos de pensión.',
                        'Proyectar el flujo de pensiones cobradas con actualización por inflación (versión PRO).',
                        'Capturar de manera simplificada los distintos escenarios de tu pensión.',
                        'Generar cualquier cantidad de escenarios sobre tu pensión.',
                        'Apoyarte con inteligencia artificial para mejorar tu estudio.',
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildBulletBlock(
                      icon: Icons.cancel_outlined,
                      iconColor: AppTheme.errorColor,
                      title: 'Esta herramienta NO puede:',
                      items: const [
                        'Garantizar montos exactos: el resultado puede variar (hasta ~10%) y solo se confirma cuando el IMSS valida tus datos.',
                        'Predecir con exactitud cambios futuros en leyes, tasas o indicadores económicos.',
                        'Sustituir resolución oficial del IMSS.',
                        'Corregir datos equivocados: el resultado depende de la información que captures.',
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

  /// Opens the official IMSS portal in the external browser.
  Future<void> _openImss() async {
    final uri = Uri.parse('https://www.gob.mx/imss');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
