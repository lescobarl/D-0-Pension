import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../services/retroactive/incremento_ladder.dart';

/// Bloque de recomendación "Escalón de tus Incrementos" (Art. 167 LSS).
///
/// Tarjeta autocontenida y movible: recibe un [IncrementoLadderAdvice] ya
/// calculado por [IncrementoLadder.compute] y únicamente se encarga de
/// renderizarlo. No recalcula nada ni depende del provider, por lo que puede
/// colocarse (moverse) en cualquier punto del árbol de widgets.
///
/// Asesora al usuario sobre el efecto "escalón" del redondeo de incrementos
/// (celda C25 del Excel): una sola semana decide si la pensión sube medio
/// incremento, un incremento completo o si se pierde medio incremento. Muestra:
/// 1. Estado actual del escalón.
/// 2. Decisión de SUBIR (si falta poco, ≤ ~1 mes) o de dejar de aportar (si la
///    inversión para el siguiente escalón es muy grande).
/// 3. Semanas Mod40 recortables SIN perder el escalón (ahorro).
///
/// Los números de semanas y meses se muestran SIN decimales (ej. "1,960
/// semanas", no "1,960.00") para mantener el bloque de recomendación limpio.
class IncrementoLadderCard extends StatelessWidget {
  final IncrementoLadderAdvice advice;

  const IncrementoLadderCard({super.key, required this.advice});

  @override
  Widget build(BuildContext context) {
    final a = advice;

    // --- Formatos de texto (todo deriva de [advice], sin hardcode) ---
    final incrementosLabel = _formatIncremento(a.incrementosActuales);
    final siguienteLabel = _formatIncremento(a.siguienteIncremento);
    final beneficioMedio = FormatUtils.formatCurrency(
      a.beneficioMedioIncrementoMensual,
    );
    final totalSemanas = FormatUtils.formatNumber(a.semanasTotales);
    final semanasAntes = FormatUtils.formatNumber(
      a.semanasTotales - a.semanasEnMod40,
    );
    final semanasM40 = FormatUtils.formatNumber(a.semanasEnMod40);
    final pisoActual = FormatUtils.formatNumber(a.pisoActualSemanas);
    final pisoSiguiente = FormatUtils.formatNumber(a.pisoSiguienteSemanas);
    final semanasParaSiguiente = FormatUtils.formatNumber(
      a.semanasParaSiguiente,
    );
    final semanasRecortables = FormatUtils.formatNumber(
      a.semanasRecortablesSinPerder,
    );
    final semanasM40Recortadas = FormatUtils.formatNumber(
      a.semanasEnMod40 - a.semanasRecortablesSinPerder,
    );
    final ahorro = FormatUtils.formatCurrency(a.ahorroEstimado);
    final mesesParaSubir = FormatUtils.formatNumber(a.mesesParaSubir);
    final inversionSubir = a.costoPorSemanaM40 > 0
        ? ' (≈ $mesesParaSubir meses, '
              '${FormatUtils.formatCurrency(a.costoParaSubir)})'
        : ' (≈ $mesesParaSubir meses)';

    // --- Decisión: SUBIR si conviene o dejar de aportar si no ---
    // Regla (derivada de la metadata): conviene SUBIR solo si falta poco
    // (≤ ~1 mes de aportación). Si falta más, la inversión para el siguiente
    // escalón es muy grande y cada semana Mod40 que se paga sin llegar al
    // siguiente piso no aumenta la pensión.
    final bool yaEnPisoSiguiente = a.semanasParaSiguiente <= 0;

    final IconData iconoDecision;
    final Color colorDecision;
    final String tituloDecision;
    final String detalleDecision;
    if (yaEnPisoSiguiente) {
      iconoDecision = Icons.arrow_upward;
      colorDecision = AppTheme.successColor;
      tituloDecision = 'SUBIR al siguiente escalón';
      detalleDecision =
          'Ya estás en el piso de $siguienteLabel incrementos: '
          'cualquier semana Mod40 adicional se acumula para el siguiente '
          'escalón.';
    } else if (a.recomiendaSubir) {
      iconoDecision = Icons.arrow_upward;
      colorDecision = AppTheme.successColor;
      tituloDecision = 'SUBIR al siguiente escalón';
      detalleDecision =
          'Te faltan solo $semanasParaSiguiente semanas Mod40 '
          'para la semana $pisoSiguiente → $siguienteLabel incrementos → '
          '+$beneficioMedio/mes de por vida. Es una aportación de menos de '
          'un mes: vale la pena.';
    } else {
      iconoDecision = Icons.trending_down;
      colorDecision = AppTheme.warningColor;
      tituloDecision = 'No conviene seguir aportando';
      detalleDecision =
          'Faltan $semanasParaSiguiente semanas Mod40'
          '$inversionSubir para subir a $siguienteLabel incrementos. Si '
          'sigues aportando sin llegar a la semana $pisoSiguiente, ese '
          'dinero no aumenta tu pensión.';
    }

    final mensajeAhorrar = a.semanasRecortablesSinPerder <= 0
        ? 'Ya estás en el piso de tu escalón: cualquier semana Mod40 que '
              'dejes de pagar baja el incremento.'
        : 'Puedes dejar de pagar $semanasRecortables semanas Mod40 '
              '($semanasM40 → $semanasM40Recortadas) y SIGUES en '
              '$incrementosLabel incrementos → ahorro ≈ $ahorro.';

    return Card(
      elevation: 0,
      color: AppTheme.accentLight.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFila(
              icon: Icons.info_outline,
              color: AppTheme.textSecondary,
              titulo: 'Estás en $incrementosLabel incrementos',
              detalle:
                  'Con $totalSemanas semanas cotizadas ($semanasAntes '
                  'antes + $semanasM40 Mod40). Piso del escalón: '
                  'semana $pisoActual.',
            ),
            const Divider(
              height: AppTheme.spacingLg,
              color: AppTheme.dividerColor,
            ),
            _buildFila(
              icon: iconoDecision,
              color: colorDecision,
              titulo: tituloDecision,
              detalle: detalleDecision,
            ),
            const Divider(
              height: AppTheme.spacingLg,
              color: AppTheme.dividerColor,
            ),
            _buildFila(
              icon: Icons.savings_outlined,
              color: AppTheme.warningColor,
              titulo: 'AHORRAR sin perder escalón',
              detalle: mensajeAhorrar,
            ),
          ],
        ),
      ),
    );
  }

  /// Fila estándar: ícono + título (en color) + detalle descriptivo.
  Widget _buildFila({
    required IconData icon,
    required Color color,
    required String titulo,
    required String detalle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppTheme.fontSizeBody, color: color),
        const SizedBox(width: AppTheme.spacingSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeBodySmall,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Formatea un escalón de incrementos: entero sin decimales, medio con 1.
  static String _formatIncremento(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }
}
