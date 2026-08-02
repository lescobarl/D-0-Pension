import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/pension_calculation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/format_utils.dart';
import '../../services/retroactive_provider.dart';
import '../widgets/result_row.dart';
import '../widgets/pension_card.dart';
import '../widgets/legal_note_card.dart';

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
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Builds a list of [label, value] pairs from ALL provider input values.
  /// These are passed to [PensionCard.extraCopyValues] so the copy button
  /// captures everything needed for diagnosis.
  List<List<String>> _buildExtraCopyValues(RetroactiveProvider provider) {
    final fmt = FormatUtils.formatCurrency;
    final values = <List<String>>[
      ['Fecha de Cálculo', _formatDate(provider.fechaCalculo)],
      ['Fecha de Nacimiento', _formatDate(provider.fechaNacimiento)],
      ['Salario Diario Promedio (250 sem)', fmt(provider.salarioDiarioPromedio)],
      ['Salario Promedio 250 Sem. (Anterior)', fmt(provider.salarioPromedio250Semanas)],
      ['Semanas Cotizadas (antes Mod40)', provider.semanasAntesMod40.toStringAsFixed(0)],
      ['Edad Retiro', '${provider.edadRetiro.toStringAsFixed(2)} años'],
      ['Tiene Esposa', provider.tieneEsposa ? 'SÍ' : 'NO'],
      ['Número de Hijos', provider.numeroHijos.toString()],
      ['Número de Padres', provider.numeroPadres.toString()],
      ['Inicio Mod40', _formatDate(provider.startDate)],
      ['Fin Mod40', _formatDate(provider.endDate)],
      ['Semanas en Mod40', provider.semanasEnMod40.toStringAsFixed(0)],
      ['Nuevo Salario Promedio (con M40)', fmt(provider.nuevoSalarioPromedio)],
      ['Salario Registrado (Mod40)', fmt(provider.salarioRegistrado)],
      ['UMA Diaria', '\$${provider.umaDiaria.toStringAsFixed(2)}'],
      ['Salario Mínimo Diario', '\$${provider.salarioMinimoDiario.toStringAsFixed(2)}'],
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
        values.add([
          '$label - Salario',
          '\$${p.salarioDiario.toStringAsFixed(4)}',
        ]);
        values.add([
          '$label - Semanas',
          p.semanas.toStringAsFixed(4),
        ]);
        values.add([
          '$label - Resultado',
          '\$${p.resultado.toStringAsFixed(2)}',
        ]);
      }
      final totalSemanas = periodos.fold<double>(0, (sum, p) => sum + p.semanas);
      final sumaResultados = periodos.fold<double>(0, (sum, p) => sum + p.resultado);
      final promedio = totalSemanas > 0 ? sumaResultados / totalSemanas : 0.0;
      values.add(['Total Semanas', totalSemanas.toStringAsFixed(4)]);
      values.add(['Promedio Ponderado', '\$${promedio.toStringAsFixed(4)}']);
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
      double porcentaje) {
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
    buffer.writeln('  Anual: ${FormatUtils.formatCurrency(actualAnual)}');
    buffer.writeln('  Mensual (30 días): ${FormatUtils.formatCurrency(actualMensual)}');
    buffer.writeln('');
    buffer.writeln('Pensión con Mod 40');
    buffer.writeln('  Anual: ${FormatUtils.formatCurrency(conMod40Anual)}');
    buffer.writeln('  Mensual (30 días): ${FormatUtils.formatCurrency(conMod40Mensual)}');
    buffer.writeln('');
    buffer.writeln('Incremento al aplicar Mod 40');
    buffer.writeln('  Incremento Mensual: ${FormatUtils.formatCurrency(incremento)}');
    buffer.writeln('  Incremento %: ${porcentaje.toStringAsFixed(2)}%');

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

        // Bloqueo legal (Ley 73): si no se cumplen las 500 semanas mínimas o
        // la edad de retiro aún no se alcanza, NO se muestran cálculos.
        if (!provider.esPensionAplicable) {
          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildElegibilidadBlocker(provider),
                  const SizedBox(height: 1),
                  _buildExpandableAgeTable(provider),
                  const SizedBox(height: 1),
                  LegalNoteCard(
                      note: provider.evaluator.metadata.legalNotes.pensionMod40),
                ],
              ),
            ),
          );
        }

        final pensionActual = provider.evaluator.metadata.financialRules.pensionActual;
        final pensionConMod40 = provider.pensionMod40Calculation;
        final factAsig = provider.factAsigCalculation;
        final factAsigSinMod40 = provider.factAsigSinMod40Calculation;

        final pensionActualMensual = factAsigSinMod40?.totalPensionMensual ??
            pensionActual?.pensionMensualActualizada ??
            0;
        final pensionActualAnual = factAsigSinMod40?.totalPensionAnual ??
            pensionActual?.importePensionAnual ?? 0;
        final pensionConMod40Mensual = pensionConMod40?.pensionMensual ?? 0;
        final pensionConMod40Anual = pensionConMod40?.pensionAnualFinal ?? 0;
        final incrementoMensual = pensionConMod40Mensual - pensionActualMensual;
        final incrementoPorcentaje = pensionActualMensual > 0
            ? (incrementoMensual / pensionActualMensual) * 100
            : 0.0;

        // DEBUG: Registrar valores para diagnóstico (solo en debug builds)
        ErrorHandler.logDebug('Pensión Actual Mensual: \$$pensionActualMensual');
        ErrorHandler.logDebug('Pensión con Mod40 Mensual: \$$pensionConMod40Mensual');
        ErrorHandler.logDebug('Incremento Mensual: \$$incrementoMensual');
        ErrorHandler.logDebug('Incremento %: $incrementoPorcentaje%');
        ErrorHandler.logDebug('FactAsigSinMod40 totalPensionMensual: ${factAsigSinMod40?.totalPensionMensual}');
        ErrorHandler.logDebug('PensionActual pensionMensualActualizada: ${pensionActual?.pensionMensualActualizada}');
        ErrorHandler.logDebug('PensionMod40Calculation: ${pensionConMod40?.pensionAnual100}, ${pensionConMod40?.porcentajePorEdad}, ${pensionConMod40?.tipoPension}');

        final extraValues = _buildExtraCopyValues(provider);

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(context, provider,
                    pensionActualMensual, pensionActualAnual,
                    pensionConMod40Mensual, pensionConMod40Anual,
                    incrementoMensual, incrementoPorcentaje),
                const SizedBox(height: 1),

                // Pensión Actual + Mod40: Cards and details side by side
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          // Pensión Actual Card
                          _buildPensionActualCard(pensionActual, factAsigSinMod40, provider, extraValues),
                          const SizedBox(height: 1),
                          // Expandible detail
                          if (factAsigSinMod40 != null) ...[
                            _buildExpandableSinMod40Detail(provider, factAsigSinMod40),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          // Pensión con Mod40 Card
                          _buildPensionMod40Card(pensionConMod40, factAsig, provider, extraValues),
                          const SizedBox(height: 1),
                          // Expandible detail
                          if (factAsig != null && pensionConMod40 != null) ...[
                            _buildExpandableConMod40Detail(provider, factAsig, pensionConMod40),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),

                // Incremento Comparativo
                if (pensionActualMensual > 0 && pensionConMod40Mensual > 0) ...[
                  _buildIncrementoComparativo(
                      pensionActualMensual, pensionConMod40Mensual,
                      incrementoMensual, incrementoPorcentaje),
                  const SizedBox(height: 1),
                ],

                // Expandable: Tabla de porcentajes por edad
                _buildExpandableAgeTable(provider),
                const SizedBox(height: 1),

                // Legal notes
                LegalNoteCard(note: provider.evaluator.metadata.legalNotes.pensionMod40),
              ],
            ),
          ),
        );
      },
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
      double porcentaje) {
    return Container(
      padding: const EdgeInsets.all(3),
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
                child: const Icon(Icons.elderly, color: AppTheme.accent, size: 14),
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
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text(
                        'Actual vs Mod40',
                        style: TextStyle(
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
                    context, provider,
                    actualMensual, actualAnual,
                    conMod40Mensual, conMod40Anual,
                    incremento, porcentaje),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_all, size: 10, color: AppTheme.accentLight),
                      SizedBox(width: 2),
                      Text('Copiar',
                          style: TextStyle(
                              fontSize: AppTheme.fontSizeBodySmall - 1,
                              color: AppTheme.accentLight,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Detail data inside the green header
          Row(
            children: [
              Expanded(
                child: _buildHeaderDetail('Sin Mod40', actualMensual, AppTheme.accentLight),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _buildHeaderDetail('Con Mod40', conMod40Mensual, AppTheme.accentLight),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _buildHeaderDetail('Incremento', incremento, Colors.greenAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderDetail(String label, double amount, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppTheme.fontSizeBodySmall - 1,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500)),
          Text(FormatUtils.formatCurrency(amount),
              style: TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  color: valueColor,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPensionActualCard(
      dynamic pensionActual, dynamic factAsigSinMod40,
      RetroactiveProvider provider, List<List<String>> extraValues) {
    final pensionMensual = factAsigSinMod40?.totalPensionMensual ??
        pensionActual?.pensionMensualActualizada ?? 0;
    final pensionAnual = factAsigSinMod40?.totalPensionAnual ??
        pensionActual?.importePensionAnual ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 0),
            const Divider(height: 4),
            PensionCard(
              title: 'Pensión Mensual Actual',
              annualAmount: pensionAnual,
              monthlyAmount: pensionMensual,
              extraCopyValues: extraValues,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableSinMod40Detail(RetroactiveProvider provider, dynamic calc) {
    return ExpansionTile(
      title: const Text('Detalle Fact. + Asig. (sin Mod 40)',
          style: TextStyle(
              fontSize: AppTheme.fontSizeCardTitle,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary)),
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
              ResultRow(label: 'Salario Promedio 250 Sem. (Anterior)',
                  value: FormatUtils.formatCurrency(provider.salarioPromedio250Semanas)),
              ResultRow(label: 'Año de Pensión',
                  value: provider.pensionYear.toString()),
              const Divider(height: 4),

              // Cuantía Básica
              _buildSectionTitle('Cuantía Básica de Pensión'),
              ResultRow(label: 'Salario en UMAS',
                  value: calc.salarioEnUMAs.toStringAsFixed(2)),
              ResultRow(label: '% Cuantía Básica',
                  value: FormatUtils.formatPercent(calc.porcentajeCuantiaBasica)),
              ResultRow(label: 'Cuantía Básica por Día',
                  value: FormatUtils.formatCurrency(calc.cuantiaBasicaPorDia)),
              ResultRow(label: 'Total Cuantía Básica Anual',
                  value: FormatUtils.formatCurrency(calc.totalCuantiaBasicaAnual)),
              const Divider(height: 4),

              // Incrementos
              _buildSectionTitle('Incrementos Anuales'),
              ResultRow(label: '% Incremento',
                  value: FormatUtils.formatPercent(calc.porcentajeIncremento)),
              ResultRow(label: 'Incremento Anual',
                  value: FormatUtils.formatCurrency(calc.incrementoAnual)),
              ResultRow(label: 'Número de Incrementos',
                  value: calc.numeroIncrementosRedondeado.toString()),
              ResultRow(label: 'Total Incrementos Anuales',
                  value: FormatUtils.formatCurrency(calc.totalIncrementosAnuales)),
              const Divider(height: 4),

              // Asignaciones
              _buildSectionTitle('Asignaciones Familiares'),
              ResultRow(label: 'Cónyuge',
                  value: calc.tieneEsposa ? 'SÍ' : 'NO'),
              ResultRow(label: 'Hijos',
                  value: calc.numeroHijos.toString()),
              ResultRow(label: 'Padres',
                  value: calc.numeroPadres.toString()),
              ResultRow(label: 'Asignación Esposa (15%)',
                  value: FormatUtils.formatCurrency(calc.asignacionEsposa)),
              ResultRow(label: 'Asignación Hijos (10% c/u)',
                  value: FormatUtils.formatCurrency(calc.asignacionHijos)),
              ResultRow(label: 'Asignación Padres (10% c/u)',
                  value: FormatUtils.formatCurrency(calc.asignacionPadres)),
              ResultRow(label: 'Total Asignaciones',
                  value: FormatUtils.formatCurrency(calc.cuantiaTotalAsignaciones),
                  isBold: true),
              if (calc.aplicaAyudaAsistencial) ...[
                ResultRow(label: 'Ayuda Asistencial',
                    value: FormatUtils.formatCurrency(calc.totalAyudaAsistencial)),
              ],
              const Divider(height: 4),

              // Decreto Presidencial
              _buildSectionTitle('Decreto Presidencial (11%)'),
              ResultRow(label: 'Base para Decreto',
                  value: FormatUtils.formatCurrency(calc.cuantiaMasAsignaciones)),
              ResultRow(label: 'Asignación Decreto',
                  value: FormatUtils.formatCurrency(calc.asignacionDecretoPresidencial)),
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
      List<List<String>> extraValues) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 0),
            if (pensionConMod40 != null) ...[
              const Divider(height: 4),
              PensionCard(
                title: 'Importe de Pensión con Mod 40',
                annualAmount: pensionConMod40.pensionAnualFinal,
                monthlyAmount: pensionConMod40.pensionMensual,
                extraCopyValues: extraValues,
              ),
            ] else ...[
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Complete los datos en CAPTURA para ver el cálculo.',
                    style: TextStyle(fontSize: AppTheme.fontSizeBody, color: AppTheme.textSecondary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableConMod40Detail(RetroactiveProvider provider, FactAsigCalculation calc, PensionMod40Calculation? pensionConMod40) {
    return ExpansionTile(
      title: const Text('Detalle Fact. + Asig. (con Mod 40)',
          style: TextStyle(
              fontSize: AppTheme.fontSizeCardTitle,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary)),
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
                ResultRow(label: 'Tipo de Pensión', value: pensionConMod40.tipoPension),
                ResultRow(label: 'Porcentaje por Edad',
                    value: FormatUtils.formatPercent(pensionConMod40.porcentajePorEdad)),
                ResultRow(label: 'Pensión Anual (100%)',
                    value: FormatUtils.formatCurrency(pensionConMod40.pensionAnual100)),
                ResultRow(label: 'Pensión Mínima Garantizada',
                    value: FormatUtils.formatCurrency(pensionConMod40.pensionMinimaGarantizada)),
                ResultRow(label: '¿Aplica Mínima?',
                    value: pensionConMod40.aplicaMinima ? 'SÍ' : 'NO'),
                const Divider(height: 4),
              ],

              // Elementos Clave (read-only display)
              _buildSectionTitle('Elementos Clave'),
              ResultRow(label: 'Salario Promedio 250 Sem. (Anterior)',
                  value: FormatUtils.formatCurrency(provider.salarioPromedio250Semanas)),
              ResultRow(label: 'Nuevo Salario Promedio 250 Sem. (con M40)',
                  value: FormatUtils.formatCurrency(provider.nuevoSalarioPromedio)),
              ResultRow(label: 'Año de Pensión',
                  value: provider.pensionYear.toString()),
              const Divider(height: 4),

              // Cuantía Básica
              _buildSectionTitle('Cuantía Básica de Pensión'),
              ResultRow(label: 'Salario en UMAS',
                  value: calc.salarioEnUMAs.toStringAsFixed(2)),
              ResultRow(label: '% Cuantía Básica',
                  value: FormatUtils.formatPercent(calc.porcentajeCuantiaBasica)),
              ResultRow(label: 'Cuantía Básica por Día',
                  value: FormatUtils.formatCurrency(calc.cuantiaBasicaPorDia)),
              ResultRow(label: 'Total Cuantía Básica Anual',
                  value: FormatUtils.formatCurrency(calc.totalCuantiaBasicaAnual)),
              const Divider(height: 4),

              // Incrementos
              _buildSectionTitle('Incrementos Anuales'),
              ResultRow(label: '% Incremento',
                  value: FormatUtils.formatPercent(calc.porcentajeIncremento)),
              ResultRow(label: 'Incremento Anual',
                  value: FormatUtils.formatCurrency(calc.incrementoAnual)),
              ResultRow(label: 'Número de Incrementos',
                  value: calc.numeroIncrementosRedondeado.toString()),
              ResultRow(label: 'Total Incrementos Anuales',
                  value: FormatUtils.formatCurrency(calc.totalIncrementosAnuales)),
              const Divider(height: 4),

              // Asignaciones
              _buildSectionTitle('Asignaciones Familiares'),
              ResultRow(label: 'Cónyuge',
                  value: calc.tieneEsposa ? 'SÍ' : 'NO'),
              ResultRow(label: 'Hijos',
                  value: calc.numeroHijos.toString()),
              ResultRow(label: 'Padres',
                  value: calc.numeroPadres.toString()),
              ResultRow(label: 'Asignación Esposa (15%)',
                  value: FormatUtils.formatCurrency(calc.asignacionEsposa)),
              ResultRow(label: 'Asignación Hijos (10% c/u)',
                  value: FormatUtils.formatCurrency(calc.asignacionHijos)),
              ResultRow(label: 'Asignación Padres (10% c/u)',
                  value: FormatUtils.formatCurrency(calc.asignacionPadres)),
              ResultRow(label: 'Total Asignaciones',
                  value: FormatUtils.formatCurrency(calc.cuantiaTotalAsignaciones),
                  isBold: true),
              if (calc.aplicaAyudaAsistencial) ...[
                ResultRow(label: 'Ayuda Asistencial',
                    value: FormatUtils.formatCurrency(calc.totalAyudaAsistencial)),
              ],
              const Divider(height: 4),

              // Decreto Presidencial
              _buildSectionTitle('Decreto Presidencial (11%)'),
              ResultRow(label: 'Base para Decreto',
                  value: FormatUtils.formatCurrency(calc.cuantiaMasAsignaciones)),
              ResultRow(label: 'Asignación Decreto',
                  value: FormatUtils.formatCurrency(calc.asignacionDecretoPresidencial)),
            ],
          ),
        ),
      ],
    );
  }

  void _copyIncrementoToClipboard(BuildContext context,
      double actual, double conMod40, double incremento, double porcentaje) {
    final text = 'INCREMENTO AL APLICAR MOD 40\n'
        'Pensión Actual (sin Mod 40): ${FormatUtils.formatCurrency(actual)}\n'
        'Pensión con Mod 40: ${FormatUtils.formatCurrency(conMod40)}\n'
        'Incremento Mensual: ${FormatUtils.formatCurrency(incremento)} ($porcentaje%)';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Valores copiados al portapapeles'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildIncrementoComparativo(
      double actual, double conMod40, double incremento, double porcentaje) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Incremento al aplicar Mod 40',
                      style: TextStyle(
                          fontSize: AppTheme.fontSizeCardTitle,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary)),
                ),
                InkWell(
                  onTap: () => _copyIncrementoToClipboard(context,
                      actual, conMod40, incremento, porcentaje),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.copy, size: 12, color: AppTheme.primary),
                  ),
                ),
              ],
            ),
            const Divider(height: 2),
            ResultRow(label: 'Pensión Actual (sin Mod 40)',
                value: FormatUtils.formatCurrency(actual)),
            ResultRow(label: 'Pensión con Mod 40',
                value: FormatUtils.formatCurrency(conMod40),
                valueColor: AppTheme.primary),
            const Divider(height: 2),
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
                        const Text('Incremento Mensual',
                            style: TextStyle(
                                fontSize: AppTheme.fontSizeBody,
                                color: AppTheme.textSecondary)),
                        Text(
                          '${FormatUtils.formatCurrency(incremento)} (${porcentaje.toStringAsFixed(2)}%)',
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

  Widget _buildExpandableAgeTable(RetroactiveProvider provider) {
    final rules = provider.evaluator.metadata.financialRules;
    return Card(
      child: ExpansionTile(
        title: const Text('Tabla de Porcentajes por Edad',
            style: TextStyle(
                fontSize: AppTheme.fontSizeCardTitle,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary)),
        subtitle: const Text('Porcentajes aplicables según la edad de retiro',
            style: TextStyle(fontSize: AppTheme.fontSizeBodySmall, color: AppTheme.textSecondary)),
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
                  DataColumn(label: Text('Tipo', style: TextStyle(fontSize: AppTheme.fontSizeTableHeader, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Edad', style: TextStyle(fontSize: AppTheme.fontSizeTableHeader, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('%', style: TextStyle(fontSize: AppTheme.fontSizeTableHeader, fontWeight: FontWeight.bold))),
                ],
                rows: rules.pensionAgePercentages.map((p) {
                  return DataRow(cells: [
                    DataCell(Text(p.type == 'vejez' ? 'Vejez' : 'Cesantía',
                        style: const TextStyle(fontSize: AppTheme.fontSizeTableData))),
                    DataCell(Text('${p.age}',
                        style: const TextStyle(fontSize: AppTheme.fontSizeTableData))),
                    DataCell(Text('${(p.percentage * 100).toInt()}%',
                        style: const TextStyle(
                            fontSize: AppTheme.fontSizeTableData, fontWeight: FontWeight.bold))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta bloqueadora que muestra por qué la pensión aún no es aplicable
  /// según la Ley 73 y cuándo el usuario alcanzará la edad de retiro.
  Widget _buildElegibilidadBlocker(RetroactiveProvider provider) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.errorColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gavel, color: AppTheme.errorColor, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Pensión NO aplicable todavía',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeCardTitle,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.errorColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'De acuerdo con la Ley del Seguro Social 1973 (Arts. 154 y 162) '
              'se requieren mínimo 500 semanas cotizadas y haber cumplido la '
              'edad de retiro. No se muestran cálculos de pensión porque aún '
              'no aplican legalmente.',
              style: TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            ...provider.requisitosPensionFaltantes.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cancel,
                        color: AppTheme.errorColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(
                            fontSize: AppTheme.fontSizeBodySmall,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            _buildFechaElegibilidad(provider),
            const SizedBox(height: 8),
            const Text(
              'Cuando cumplas los requisitos, la app calculará la pensión '
              'automáticamente.',
              style: TextStyle(
                  fontSize: AppTheme.fontSizeBodySmall,
                  color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Fila con la fecha estimada en la que el usuario alcanzará la edad de
  /// retiro seleccionada, calculada desde la fecha de nacimiento.
  Widget _buildFechaElegibilidad(RetroactiveProvider provider) {
    final edadRetiro = provider.edadRetiro;
    final nacimiento = provider.fechaNacimiento;
    final enteros = edadRetiro.floor();
    final fraccion = edadRetiro - enteros;
    final fechaEstimada = DateTime(
      nacimiento.year + enteros,
      nacimiento.month,
      nacimiento.day,
    ).add(Duration(days: (fraccion * 365.25).round()));
    final anosFaltantes = provider.edadRetiro - provider.edadActual;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.event_available,
            color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fecha estimada para alcanzar la edad de retiro',
                  style: TextStyle(
                      fontSize: AppTheme.fontSizeBodySmall,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(
                '${_formatDate(fechaEstimada)} '
                '(te faltan ${anosFaltantes.toStringAsFixed(2)} años)',
                style: const TextStyle(
                    fontSize: AppTheme.fontSizeBodySmall,
                    color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(title,
          style: const TextStyle(
              fontSize: AppTheme.fontSizeBody,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary)),
    );
  }
}
