import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/pension_calculation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/input_validator.dart';
import '../../services/retroactive_provider.dart';
import '../../services/retroactive/incremento_ladder.dart';
import '../widgets/result_row.dart';
import '../widgets/pension_card.dart';
import '../widgets/legal_note_card.dart';
import '../widgets/incremento_ladder_card.dart';

/// Consolidated view for all pension-related data.
///
/// Shows pensión actual vs Mod40 side by side with expandable detail sections:
/// - Pensión Actual (summary card with expandable detail inside)
/// - Pensión con Mod40 (summary card with expandable detail inside)
/// - Expandable: Tabla de porcentajes por edad
class PensionView extends StatefulWidget {
  const PensionView({super.key});

  @override
  State<PensionView> createState() => _PensionViewState();
}

class _PensionViewState extends State<PensionView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Builds a list of [label, value] pairs from ALL provider input values.
  /// These are passed to [PensionCard.extraCopyValues] so the copy button
  /// captures everything needed for diagnosis.
  List<List<String>> _buildExtraCopyValues(RetroactiveProvider provider) {
    final fmt = FormatUtils.formatCurrency;
    final values = <List<String>>[
      ['Fecha de Cálculo', _formatDate(provider.fechaCalculo)],
      ['Fecha de Nacimiento', _formatDate(provider.fechaNacimiento)],
      [
        'Salario Diario Promedio (250 sem)',
        fmt(provider.salarioDiarioPromedio),
      ],
      [
        'Salario Promedio 250 Sem. (Anterior)',
        fmt(provider.salarioPromedio250Semanas),
      ],
      ['Semanas Cotizadas (antes M40)', provider.semanasCotizadas.toString()],
      ['Semanas antes Mod40', provider.semanasAntesMod40.toStringAsFixed(0)],
      ['Edad Retiro', '${provider.edadRetiro.toStringAsFixed(2)} años'],
      ['Tiene Esposa', provider.tieneEsposa ? 'SÍ' : 'NO'],
      ['Número de Hijos', provider.numeroHijos.toString()],
      ['Número de Padres', provider.numeroPadres.toString()],
      if (provider.modalidad40OptOut)
        ['Modalidad 40 (aportaciones voluntarias)', 'NO']
      else ...[
        ['Inicio Mod40', _formatDate(provider.startDate)],
        ['Fin Mod40', _formatDate(provider.endDate)],
        ['Semanas en Mod40', provider.semanasEnMod40.toStringAsFixed(0)],
        [
          'Nuevo Salario Promedio (con M40)',
          fmt(provider.nuevoSalarioPromedio),
        ],
        ['Salario Registrado (Mod40)', fmt(provider.salarioRegistrado)],
      ],
      ['UMA Diaria', '\$${provider.umaDiaria.toStringAsFixed(2)}'],
      [
        'Salario Mínimo Diario',
        '\$${provider.salarioMinimoDiario.toStringAsFixed(2)}',
      ],
      ['Año de Pensión', provider.pensionYear.toString()],
    ];
    // Add desglose periodos detail
    final periodos = provider.periodos;
    if (periodos.isNotEmpty) {
      values.add(['', '']);
      values.add(['--- DESGLOSE SAL. PROM (periodos) ---', '']);
      for (int i = 0; i < periodos.length; i++) {
        final p = periodos[i];
        final label = p.esMod40 ? 'Mod40' : 'Periodo ${i + 1}';
        values.add(['$label - Salario', fmt(p.salarioDiario)]);
        values.add(['$label - Semanas', p.semanas.round().toString()]);
        values.add([
          '$label - Resultado',
          FormatUtils.formatCurrencyInt(p.resultado),
        ]);
      }
      final totalSemanas = periodos.fold<double>(
        0,
        (sum, p) => sum + p.semanas,
      );
      final sumaResultados = periodos.fold<double>(
        0,
        (sum, p) => sum + p.resultado,
      );
      final promedio = totalSemanas > 0 ? sumaResultados / totalSemanas : 0.0;
      values.add(['Total Semanas', totalSemanas.round().toString()]);
      values.add(['Promedio Ponderado', fmt(promedio)]);
    }
    return values;
  }

  /// Copies ALL data (inputs + outputs) to clipboard in one action.
  void _copyAllToClipboard(
    BuildContext context,
    RetroactiveProvider provider,
    double actualMensual,
    double actualAnual,
    double conMod40Mensual,
    double conMod40Anual,
    double incremento,
    double porcentaje,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('=== PENSION CALCULATION - COMPLETE DATA ===');
    buffer.writeln('');

    // Inputs
    buffer.writeln('--- INPUTS (CAPTURA) ---');
    for (final entry in _buildExtraCopyValues(provider)) {
      buffer.writeln('${entry[0]}: ${entry[1]}');
    }

    // Outputs
    buffer.writeln('');
    buffer.writeln('--- OUTPUTS (PENSIÓN) ---');
    buffer.writeln('Pensión Actual (sin Mod 40)');
    buffer.writeln('  Anual: ${FormatUtils.formatCurrencyInt(actualAnual)}');
    buffer.writeln(
      '  Mensual (30 días): ${FormatUtils.formatCurrencyInt(actualMensual)}',
    );
    if (provider.modalidad40OptOut) {
      buffer.writeln('');
      buffer.writeln('Pensión con Mod 40: No aplica');
      buffer.writeln(
        '  (Elegiste no hacer aportaciones voluntarias de Modalidad 40)',
      );
    } else {
      buffer.writeln('');
      buffer.writeln('Pensión con Mod 40');
      buffer.writeln(
        '  Anual: ${FormatUtils.formatCurrencyInt(conMod40Anual)}',
      );
      buffer.writeln(
        '  Mensual (30 días): ${FormatUtils.formatCurrencyInt(conMod40Mensual)}',
      );
      buffer.writeln('');
      buffer.writeln('Incremento al aplicar Mod 40');
      buffer.writeln(
        '  Incremento Mensual: ${FormatUtils.formatCurrencyInt(incremento)}',
      );
      buffer.writeln('  Incremento %: ${porcentaje.toStringAsFixed(2)}%');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Todos los valores copiados al portapapeles'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetroactiveProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // ── Regla A (Ley 73) y errores bloqueantes ──
        // Si hay errores que impiden calcular (por ejemplo, la Ley 73 NO
        // aplica por nacimiento o alta posteriores a 1997-07-01), NO se muestra
        // pensión alguna: se bloquea con un panel rojo que pide corregir en la
        // pestaña Captura. Así jamás se proyecta una pensión de Ley 73 a quien
        // no le corresponde (regiría la Ley 1997).
        if (provider.hasBlockingErrors) {
          final errores = provider.validacionesGlobales
              .where((v) => !v.isValid)
              .toList();
          return _buildErrorBloqueo(errores);
        }

        // Sin errores bloqueantes, la pensión se proyecta a la edad de retiro
        // seleccionada: no existe bloqueo por edad. La única advertencia
        // (informativa) es la falta de semanas, que se muestra en Captura.

        final pensionActual =
            provider.evaluator.metadata.financialRules.pensionActual;
        final pensionConMod40 = provider.pensionMod40Calculation;
        final factAsig = provider.factAsigCalculation;
        final factAsigSinMod40 = provider.factAsigSinMod40Calculation;

        final pensionActualMensual =
            factAsigSinMod40?.totalPensionMensual ??
            pensionActual?.pensionMensualActualizada ??
            0;
        final pensionActualAnual =
            factAsigSinMod40?.totalPensionAnual ??
            pensionActual?.importePensionAnual ??
            0;
        final pensionConMod40Mensual = pensionConMod40?.pensionMensual ?? 0;
        final pensionConMod40Anual = pensionConMod40?.pensionAnualFinal ?? 0;
        final incrementoMensual = pensionConMod40Mensual - pensionActualMensual;
        final incrementoPorcentaje = pensionActualMensual > 0
            ? (incrementoMensual / pensionActualMensual) * 100
            : 0.0;

        // DEBUG: Registrar valores para diagnóstico (solo en debug builds)
        ErrorHandler.logDebug(
          'Pensión Actual Mensual: \$$pensionActualMensual',
        );
        ErrorHandler.logDebug(
          'Pensión con Mod40 Mensual: \$$pensionConMod40Mensual',
        );
        ErrorHandler.logDebug('Incremento Mensual: \$$incrementoMensual');
        ErrorHandler.logDebug('Incremento %: $incrementoPorcentaje%');
        ErrorHandler.logDebug(
          'FactAsigSinMod40 totalPensionMensual: ${factAsigSinMod40?.totalPensionMensual}',
        );
        ErrorHandler.logDebug(
          'PensionActual pensionMensualActualizada: ${pensionActual?.pensionMensualActualizada}',
        );
        ErrorHandler.logDebug(
          'PensionMod40Calculation: ${pensionConMod40?.pensionAnual100}, ${pensionConMod40?.porcentajePorEdad}, ${pensionConMod40?.tipoPension}',
        );

        final extraValues = _buildExtraCopyValues(provider);

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(
                  context,
                  provider,
                  pensionActualMensual,
                  pensionActualAnual,
                  pensionConMod40Mensual,
                  pensionConMod40Anual,
                  incrementoMensual,
                  incrementoPorcentaje,
                ),
                const SizedBox(height: AppTheme.spacingXs),

                // Pensión Actual + Mod40: tarjetas y detalles (responsivo).
                // Celular = estándar: se apilan en columna vertical; en
                // pantallas anchas (>= 600px) se muestran lado a lado.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final actualSide = _buildPensionActualSide(
                      pensionActual,
                      factAsigSinMod40,
                      provider,
                      extraValues,
                    );
                    final mod40Side = _buildPensionMod40Side(
                      pensionConMod40,
                      factAsig,
                      provider,
                      extraValues,
                    );
                    if (constraints.maxWidth >= 600) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: actualSide),
                          const SizedBox(width: AppTheme.spacingSm),
                          Expanded(child: mod40Side),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        actualSide,
                        const SizedBox(height: AppTheme.spacingXs),
                        mod40Side,
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppTheme.spacingXs),

                // Escalón de tus Incrementos (Art. 167 LSS)
                if (!provider.modalidad40OptOut &&
                    factAsig != null &&
                    pensionConMod40 != null &&
                    provider.costoMod40Calculation != null &&
                    pensionConMod40Mensual > 0 &&
                    factAsig.numeroIncrementosRedondeado > 0) ...[
                  _buildIncrementoLadder(
                    provider,
                    factAsig,
                    pensionConMod40,
                    provider.costoMod40Calculation!,
                  ),
                  const SizedBox(height: AppTheme.spacingXs),
                ],

                // Incremento Comparativo
                if (!provider.modalidad40OptOut &&
                    pensionActualMensual > 0 &&
                    pensionConMod40Mensual > 0) ...[
                  _buildIncrementoComparativo(
                    pensionActualMensual,
                    pensionConMod40Mensual,
                    incrementoMensual,
                    incrementoPorcentaje,
                  ),
                  const SizedBox(height: AppTheme.spacingXs),
                ],

                // Expandable: Tabla de porcentajes por edad
                _buildExpandableAgeTable(provider),
                const SizedBox(height: AppTheme.spacingXs),

                // Legal notes
                LegalNoteCard(
                  note: provider.evaluator.metadata.legalNotes.pensionMod40,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Panel rojo de bloqueo: se muestra cuando hay errores que impiden calcular
  /// la pensión (Regla A / Ley 73, mínimo de semanas, etc.). Sustituye a las
  /// tarjetas de pensión para NO proyectar un monto inválido o de un régimen
  /// que no corresponde al asegurado.
  Widget _buildErrorBloqueo(List<ValidationResult> errores) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEF9A9A), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error, color: Color(0xFFC62828), size: 24),
                const SizedBox(width: AppTheme.spacingSm),
                Expanded(
                  child: Text(
                    'No se puede calcular tu pensión',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeCardTitle,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFC62828),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              'Corrige los errores en la pestaña Captura para continuar. '
              'Mientras haya datos que impiden el cálculo (por ejemplo, si la '
              'Ley 73 no aplica), no se mostrará un monto de pensión.',
              style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: const Color(0xFFB71C1C),
                height: 1.3,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            for (final v in errores) _buildValidationRowBloqueo(v),
          ],
        ),
      ),
    );
  }

  /// Renglón compacto de un error bloqueante (icono + mensaje).
  Widget _buildValidationRowBloqueo(ValidationResult v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error, size: 15, color: Color(0xFFC62828)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              v.message,
              style: TextStyle(
                fontSize: AppTheme.fontSizeBodySmall,
                color: const Color(0xFFC62828),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    RetroactiveProvider provider,
    double actualMensual,
    double actualAnual,
    double conMod40Mensual,
    double conMod40Anual,
    double incremento,
    double porcentaje,
  ) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.elderly,
                  color: AppTheme.accent,
                  size: 14,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Pensión',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBody,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        provider.modalidad40OptOut
                            ? 'Sin Modalidad 40'
                            : 'Actual vs Mod40',
                        style: const TextStyle(
                          fontSize: AppTheme.fontSizeBodySmall - 1,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Copy All button
              InkWell(
                onTap: () => _copyAllToClipboard(
                  context,
                  provider,
                  actualMensual,
                  actualAnual,
                  conMod40Mensual,
                  conMod40Anual,
                  incremento,
                  porcentaje,
                ),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy_all,
                        size: 10,
                        color: AppTheme.accentLight,
                      ),
                      SizedBox(width: 2),
                      Text(
                        'Copiar',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeBodySmall - 1,
                          color: AppTheme.accentLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Detail data inside the green header (responsivo).
          // Celular = estándar: se acomodan con Wrap; ancho usa Row+Expanded.
          LayoutBuilder(
            builder: (context, constraints) {
              final items = <Widget>[
                _buildHeaderDetail(
                  'Sin Mod40',
                  FormatUtils.formatCurrencyInt(actualMensual),
                  AppTheme.accentLight,
                ),
                if (!provider.modalidad40OptOut) ...[
                  _buildHeaderDetail(
                    'Con Mod40',
                    FormatUtils.formatCurrencyInt(conMod40Mensual),
                    AppTheme.accentLight,
                  ),
                  _buildHeaderDetail(
                    'Incremento',
                    FormatUtils.formatCurrencyInt(incremento),
                    Colors.greenAccent,
                  ),
                ],
                _buildHeaderDetail(
                  'Fecha de pensión',
                  _formatDate(provider.fechaPension),
                  AppTheme.accentLight,
                ),
                if (!provider.modalidad40OptOut)
                  _buildHeaderDetail(
                    'Inicio de aportaciones Mod40',
                    _formatDate(provider.startDate),
                    AppTheme.accentLight,
                  ),
              ];
              if (constraints.maxWidth < 600) {
                return Wrap(
                  spacing: AppTheme.spacingXs,
                  runSpacing: AppTheme.spacingXs,
                  children: items,
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(child: items[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Celda compacta "Nombre: Valor" en una sola línea (ahorra altura).
  Widget _buildHeaderDetail(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Both label and value are Flexible so this compact cell never
          // overflows in the desktop Row branch (5 equal Expanded cells of
          // ~160px each). Long labels such as "Inicio de aportaciones Mod40"
          // truncate with an ellipsis instead of overflowing the header.
          Flexible(
            child: Text(
              '$label:',
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBodySmall - 1,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPensionActualCard(
    dynamic pensionActual,
    dynamic factAsigSinMod40,
    RetroactiveProvider provider,
    List<List<String>> extraValues,
  ) {
    final pensionMensual =
        factAsigSinMod40?.totalPensionMensual ??
        pensionActual?.pensionMensualActualizada ??
        0;
    final pensionAnual =
        factAsigSinMod40?.totalPensionAnual ??
        pensionActual?.importePensionAnual ??
        0;

    return PensionCard(
      title: 'Pensión Actual',
      annualAmount: pensionAnual,
      monthlyAmount: pensionMensual,
      extraCopyValues: extraValues,
      showCopyButton: false,
      inlineFields: [
        [
          'Salario Promedio 250 Semanas',
          provider.salarioPromedio250Semanas.toStringAsFixed(2),
        ],
        ['Semanas cotizadas IMSS', provider.semanasCotizadas.toString()],
      ],
    );
  }

  /// Columna lateral "Pensión Actual": tarjeta + detalle expandible.
  Widget _buildPensionActualSide(
    dynamic pensionActual,
    dynamic factAsigSinMod40,
    RetroactiveProvider provider,
    List<List<String>> extraValues,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPensionActualCard(
          pensionActual,
          factAsigSinMod40,
          provider,
          extraValues,
        ),
        const SizedBox(height: AppTheme.spacingXs),
        if (factAsigSinMod40 != null) ...[
          _buildExpandableSinMod40Detail(provider, factAsigSinMod40),
        ],
      ],
    );
  }

  Widget _buildExpandableSinMod40Detail(
    RetroactiveProvider provider,
    dynamic calc,
  ) {
    return ExpansionTile(
      title: const Text(
        'Detalle Fact. + Asig. (sin Mod 40)',
        style: TextStyle(
          fontSize: AppTheme.fontSizeCardTitle,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Elementos Clave (read-only display)
              _buildSectionTitle('Elementos Clave'),
              ResultRow(
                label: 'Salario Promedio 250 Sem. (Anterior)',
                value: FormatUtils.formatCurrency(
                  provider.salarioPromedio250Semanas,
                ),
              ),
              ResultRow(
                label: 'Año de Pensión',
                value: provider.pensionYear.toString(),
              ),
              const Divider(height: 2),

              // Cuantía Básica
              _buildSectionTitle('Cuantía Básica de Pensión'),
              ResultRow(
                label: 'Salario en UMAS',
                value: calc.salarioEnUMAs.toStringAsFixed(2),
              ),
              ResultRow(
                label: '% Cuantía Básica',
                value: FormatUtils.formatPercent(calc.porcentajeCuantiaBasica),
              ),
              ResultRow(
                label: 'Cuantía Básica por Día',
                value: FormatUtils.formatCurrency(calc.cuantiaBasicaPorDia),
              ),
              ResultRow(
                label: 'Total Cuantía Básica Anual',
                value: FormatUtils.formatCurrencyInt(
                  calc.totalCuantiaBasicaAnual,
                ),
              ),
              const Divider(height: 2),

              // Incrementos
              _buildSectionTitle('Incrementos Anuales'),
              ResultRow(
                label: '% Incremento',
                value: FormatUtils.formatPercent(calc.porcentajeIncremento),
              ),
              ResultRow(
                label: 'Incremento Anual',
                value: FormatUtils.formatCurrencyInt(calc.incrementoAnual),
              ),
              ResultRow(
                label: 'Número de Incrementos',
                value: calc.numeroIncrementosRedondeado.toString(),
              ),
              ResultRow(
                label: 'Total Incrementos Anuales',
                value: FormatUtils.formatCurrencyInt(
                  calc.totalIncrementosAnuales,
                ),
              ),
              const Divider(height: 2),

              // Asignaciones
              _buildSectionTitle('Asignaciones Familiares'),
              ResultRow(
                label: 'Cónyuge',
                value: calc.tieneEsposa ? 'SÍ' : 'NO',
              ),
              ResultRow(label: 'Hijos', value: calc.numeroHijos.toString()),
              ResultRow(label: 'Padres', value: calc.numeroPadres.toString()),
              ResultRow(
                label: 'Asignación Esposa (15%)',
                value: FormatUtils.formatCurrencyInt(calc.asignacionEsposa),
              ),
              ResultRow(
                label: 'Asignación Hijos (10% c/u)',
                value: FormatUtils.formatCurrencyInt(calc.asignacionHijos),
              ),
              ResultRow(
                label: 'Asignación Padres (10% c/u)',
                value: FormatUtils.formatCurrencyInt(calc.asignacionPadres),
              ),
              ResultRow(
                label: 'Total Asignaciones',
                value: FormatUtils.formatCurrencyInt(
                  calc.cuantiaTotalAsignaciones,
                ),
                isBold: true,
              ),
              if (calc.aplicaAyudaAsistencial) ...[
                ResultRow(
                  label: 'Ayuda Asistencial',
                  value: FormatUtils.formatCurrencyInt(
                    calc.totalAyudaAsistencial,
                  ),
                ),
              ],
              const Divider(height: 2),

              // Decreto Presidencial
              _buildSectionTitle('Decreto Presidencial (11%)'),
              ResultRow(
                label: 'Base para Decreto',
                value: FormatUtils.formatCurrencyInt(
                  calc.cuantiaMasAsignaciones,
                ),
              ),
              ResultRow(
                label: 'Asignación Decreto',
                value: FormatUtils.formatCurrencyInt(
                  calc.asignacionDecretoPresidencial,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPensionMod40Card(
    PensionMod40Calculation? pensionConMod40,
    FactAsigCalculation? factAsig,
    RetroactiveProvider provider,
    List<List<String>> extraValues,
  ) {
    if (provider.modalidad40OptOut) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Modalidad 40',
              style: TextStyle(
                fontSize: AppTheme.fontSizeCardTitle,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Elegiste no hacer aportaciones voluntarias de Modalidad 40. '
              'Tu pensión se calculó con las semanas que cotizaste ante el IMSS.',
              style: TextStyle(
                fontSize: AppTheme.fontSizeInput,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    if (pensionConMod40 == null) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          'Complete los datos en CAPTURA para ver el cálculo.',
          style: TextStyle(
            fontSize: AppTheme.fontSizeBody,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }
    return PensionCard(
      title: 'Pensión con Mod 40',
      annualAmount: pensionConMod40.pensionAnualFinal,
      monthlyAmount: pensionConMod40.pensionMensual,
      extraCopyValues: extraValues,
      showCopyButton: false,
      inlineFields: [
        ['Semanas en Mod40', provider.semanasEnMod40.round().toString()],
        [
          'Salario Promedio (con Mod40)',
          provider.nuevoSalarioPromedio.toStringAsFixed(2),
        ],
        [
          'Semanas Totales (IMSS+M40)',
          provider.totalSemanasConMod40.round().toString(),
        ],
      ],
    );
  }

  /// Columna lateral "Pensión con Mod40": tarjeta + detalle expandible.
  Widget _buildPensionMod40Side(
    PensionMod40Calculation? pensionConMod40,
    FactAsigCalculation? factAsig,
    RetroactiveProvider provider,
    List<List<String>> extraValues,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPensionMod40Card(
          pensionConMod40,
          factAsig,
          provider,
          extraValues,
        ),
        const SizedBox(height: AppTheme.spacingXs),
        if (!provider.modalidad40OptOut &&
            factAsig != null &&
            pensionConMod40 != null) ...[
          _buildExpandableConMod40Detail(provider, factAsig, pensionConMod40),
        ],
      ],
    );
  }

  Widget _buildExpandableConMod40Detail(
    RetroactiveProvider provider,
    FactAsigCalculation calc,
    PensionMod40Calculation? pensionConMod40,
  ) {
    return ExpansionTile(
      title: const Text(
        'Detalle Fact. + Asig. (con Mod 40)',
        style: TextStyle(
          fontSize: AppTheme.fontSizeCardTitle,
          fontWeight: FontWeight.w600,
          color: AppTheme.primary,
        ),
      ),
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Datos de Pensión (moved from visible area)
              if (pensionConMod40 != null) ...[
                _buildSectionTitle('Datos de Pensión'),
                ResultRow(
                  label: 'Tipo de Pensión',
                  value: pensionConMod40.tipoPension,
                ),
                ResultRow(
                  label: 'Porcentaje por Edad',
                  value: FormatUtils.formatPercent(
                    pensionConMod40.porcentajePorEdad,
                  ),
                ),
                ResultRow(
                  label: 'Pensión Anual (100%)',
                  value: FormatUtils.formatCurrencyInt(
                    pensionConMod40.pensionAnual100,
                  ),
                ),
                ResultRow(
                  label: 'Pensión Mínima Garantizada',
                  value: FormatUtils.formatCurrencyInt(
                    pensionConMod40.pensionMinimaGarantizada,
                  ),
                ),
                ResultRow(
                  label: '¿Aplica Mínima?',
                  value: pensionConMod40.aplicaMinima ? 'SÍ' : 'NO',
                ),
                const Divider(height: 2),
              ],

              // Elementos Clave (read-only display)
              _buildSectionTitle('Elementos Clave'),
              ResultRow(
                label: 'Salario Promedio 250 Sem. (Anterior)',
                value: FormatUtils.formatCurrency(
                  provider.salarioPromedio250Semanas,
                ),
              ),
              ResultRow(
                label: 'Nuevo Salario Promedio 250 Sem. (con M40)',
                value: FormatUtils.formatCurrency(
                  provider.nuevoSalarioPromedio,
                ),
              ),
              ResultRow(
                label: 'Año de Pensión',
                value: provider.pensionYear.toString(),
              ),
              const Divider(height: 2),

              // Cuantía Básica
              _buildSectionTitle('Cuantía Básica de Pensión'),
              ResultRow(
                label: 'Salario en UMAS',
                value: calc.salarioEnUMAs.toStringAsFixed(2),
              ),
              ResultRow(
                label: '% Cuantía Básica',
                value: FormatUtils.formatPercent(calc.porcentajeCuantiaBasica),
              ),
              ResultRow(
                label: 'Cuantía Básica por Día',
                value: FormatUtils.formatCurrency(calc.cuantiaBasicaPorDia),
              ),
              ResultRow(
                label: 'Total Cuantía Básica Anual',
                value: FormatUtils.formatCurrencyInt(
                  calc.totalCuantiaBasicaAnual,
                ),
              ),
              const Divider(height: 2),

              // Incrementos
              _buildSectionTitle('Incrementos Anuales'),
              ResultRow(
                label: '% Incremento',
                value: FormatUtils.formatPercent(calc.porcentajeIncremento),
              ),
              ResultRow(
                label: 'Incremento Anual',
                value: FormatUtils.formatCurrencyInt(calc.incrementoAnual),
              ),
              ResultRow(
                label: 'Número de Incrementos',
                value: calc.numeroIncrementosRedondeado.toString(),
              ),
              ResultRow(
                label: 'Total Incrementos Anuales',
                value: FormatUtils.formatCurrencyInt(
                  calc.totalIncrementosAnuales,
                ),
              ),
              const Divider(height: 2),

              // Asignaciones
              _buildSectionTitle('Asignaciones Familiares'),
              ResultRow(
                label: 'Cónyuge',
                value: calc.tieneEsposa ? 'SÍ' : 'NO',
              ),
              ResultRow(label: 'Hijos', value: calc.numeroHijos.toString()),
              ResultRow(label: 'Padres', value: calc.numeroPadres.toString()),
              ResultRow(
                label: 'Asignación Esposa (15%)',
                value: FormatUtils.formatCurrencyInt(calc.asignacionEsposa),
              ),
              ResultRow(
                label: 'Asignación Hijos (10% c/u)',
                value: FormatUtils.formatCurrencyInt(calc.asignacionHijos),
              ),
              ResultRow(
                label: 'Asignación Padres (10% c/u)',
                value: FormatUtils.formatCurrencyInt(calc.asignacionPadres),
              ),
              ResultRow(
                label: 'Total Asignaciones',
                value: FormatUtils.formatCurrencyInt(
                  calc.cuantiaTotalAsignaciones,
                ),
                isBold: true,
              ),
              if (calc.aplicaAyudaAsistencial) ...[
                ResultRow(
                  label: 'Ayuda Asistencial',
                  value: FormatUtils.formatCurrencyInt(
                    calc.totalAyudaAsistencial,
                  ),
                ),
              ],
              const Divider(height: 2),

              // Decreto Presidencial
              _buildSectionTitle('Decreto Presidencial (11%)'),
              ResultRow(
                label: 'Base para Decreto',
                value: FormatUtils.formatCurrencyInt(
                  calc.cuantiaMasAsignaciones,
                ),
              ),
              ResultRow(
                label: 'Asignación Decreto',
                value: FormatUtils.formatCurrencyInt(
                  calc.asignacionDecretoPresidencial,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIncrementoComparativo(
    double actual,
    double conMod40,
    double incremento,
    double porcentaje,
  ) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Incremento al aplicar Mod 40',
              style: TextStyle(
                fontSize: AppTheme.fontSizeCardTitle,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
            const Divider(height: 1),
            ResultRow(
              label: 'Pensión Actual (sin Mod 40)',
              value: FormatUtils.formatCurrencyInt(actual),
            ),
            ResultRow(
              label: 'Pensión con Mod 40',
              value: FormatUtils.formatCurrencyInt(conMod40),
              valueColor: AppTheme.primary,
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: incremento > 0
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    incremento > 0 ? Icons.trending_up : Icons.trending_down,
                    color: incremento > 0 ? AppTheme.primary : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Incremento Mensual',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeBody,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '${FormatUtils.formatCurrencyInt(incremento)} (${porcentaje.toStringAsFixed(2)}%)',
                          style: const TextStyle(
                            fontSize: AppTheme.fontSizeTotalMedium,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
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

  /// Construye el bloque de recomendación "Escalón de tus Incrementos".
  ///
  /// Calcula la asesoría (sin hardcode) a partir de las reglas de metadata y de
  /// los resultados del motor, y la entrega a [IncrementoLadderCard].
  Widget _buildIncrementoLadder(
    RetroactiveProvider provider,
    FactAsigCalculation factAsig,
    PensionMod40Calculation pensionConMod40,
    CostoMod40Calculation costoMod40,
  ) {
    final rules = provider.evaluator.metadata.financialRules;
    final advice = IncrementoLadder.compute(
      rules: rules,
      semanasTotales: provider.semanasAntesMod40 + provider.semanasEnMod40,
      semanasEnMod40: provider.semanasEnMod40,
      factAsig: factAsig,
      pensionMod40: pensionConMod40,
      costoMod40: costoMod40,
      pensionYear: provider.pensionYear,
    );
    return IncrementoLadderCard(advice: advice);
  }

  Widget _buildExpandableAgeTable(RetroactiveProvider provider) {
    final rules = provider.evaluator.metadata.financialRules;
    return Card(
      child: ExpansionTile(
        title: const Text(
          'Tabla de Porcentajes por Edad',
          style: TextStyle(
            fontSize: AppTheme.fontSizeCardTitle,
            fontWeight: FontWeight.w600,
            color: AppTheme.primary,
          ),
        ),
        subtitle: const Text(
          'Porcentajes aplicables según la edad de retiro',
          style: TextStyle(
            fontSize: AppTheme.fontSizeBodySmall,
            color: AppTheme.textSecondary,
          ),
        ),
        initiallyExpanded: false,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                dataRowMinHeight: 28,
                dataRowMaxHeight: 36,
                headingRowHeight: 32,
                columns: const [
                  DataColumn(
                    label: Text(
                      'Tipo',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeTableHeader,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Edad',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeTableHeader,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      '%',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeTableHeader,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                rows: rules.pensionAgePercentages.map((p) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          p.type == 'vejez' ? 'Vejez' : 'Cesantía',
                          style: const TextStyle(
                            fontSize: AppTheme.fontSizeTableData,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${p.age}',
                          style: const TextStyle(
                            fontSize: AppTheme.fontSizeTableData,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${(p.percentage * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: AppTheme.fontSizeTableData,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: AppTheme.fontSizeBody,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
