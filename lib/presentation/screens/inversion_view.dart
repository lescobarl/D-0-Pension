import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/pension_calculation.dart';
import '../../core/models/retroactive_calculation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../services/retroactive_provider.dart';
import '../widgets/result_row.dart';
import '../widgets/info_row.dart';
import '../widgets/legal_note_card.dart';

/// Consolidated view for all investment/financing data.
///
/// Shows in a single scrollable view:
/// - Costo Mod40 (year-by-year table + summary)
/// - Pago Retroactivo (slider + results)
/// - Financiamiento (participaciones, plan de pagos, proyección)
/// - Segundo Fondeador
/// - Inversión (mejora pensión, análisis, ganancia, termómetro)
class InversionView extends StatefulWidget {
  const InversionView({super.key});

  @override
  State<InversionView> createState() => _InversionViewState();
}

class _InversionViewState extends State<InversionView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetroactiveProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final costoCalc = provider.costoMod40Calculation;
        final retroCalc = provider.retroactiveCalculation;
        final finCalc = provider.financiamientoCalculation;
        final invCalc = provider.inversionCalculation;

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: AppTheme.spacingXs),

                // 1. COSTO MOD 40
                _buildCostoMod40Section(provider, costoCalc),
                const SizedBox(height: AppTheme.spacingXs),

                // 2. PAGO RETROACTIVO + MEJORA DE PENSIÓN (single collapsible block)
                _buildPagoRetroactivoYMejoraSection(provider, retroCalc, invCalc),
                const SizedBox(height: AppTheme.spacingXs),

                // 3. FINANCIAMIENTO
                _buildFinanciamientoSection(provider, finCalc),
                const SizedBox(height: AppTheme.spacingXs),

                // Legal notes
                LegalNoteCard(note: provider.evaluator.metadata.legalNotes.inversion),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.trending_up, color: AppTheme.accent, size: 18),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          const Expanded(
            child: Row(
              children: [
                Text(
                  'Inversión',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeCardTitle,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  'Costo, retroactivo, financiamiento',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeBodySmall - 2,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 1. COSTO MOD 40
  // ============================================================

  Widget _buildCostoMod40Section(RetroactiveProvider provider, CostoMod40Calculation? calc) {
    return Card(
      child: ExpansionTile(
        title: const Text('Costo Mod. 40',
            style: TextStyle(
                fontSize: AppTheme.fontSizeCardTitle,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary)),
        initiallyExpanded: true,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Salario registrado input
                _buildSalarioRegistradoInput(provider),
                const SizedBox(height: AppTheme.spacingXs),
                if (calc != null) ...[
                  _buildCostoTable(calc),
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildCostoSummary(calc),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalarioRegistradoInput(RetroactiveProvider provider) {
    return Row(
      children: [
        const Text('Salario Registrado: ',
            style: TextStyle(fontSize: AppTheme.fontSizeBody, color: AppTheme.textSecondary)),
        const SizedBox(width: 8),
        SizedBox(
          width: 160,
          child: TextField(
            controller: TextEditingController(
              text: provider.salarioRegistrado.toStringAsFixed(2),
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: AppTheme.fontSizeInput),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            onSubmitted: (v) {
              final parsed = double.tryParse(v);
              if (parsed != null) provider.setSalarioRegistrado(parsed);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCostoTable(CostoMod40Calculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Detalle Año por Año',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 12,
            dataRowMinHeight: 20,
            dataRowMaxHeight: 26,
            headingRowHeight: 24,
            columns: const [
              DataColumn(label: Text('Año', style: TextStyle(fontSize: AppTheme.fontSizeTableHeader, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Tasa', style: TextStyle(fontSize: AppTheme.fontSizeTableHeader, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Cuotas', style: TextStyle(fontSize: AppTheme.fontSizeTableHeader, fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Costo Anual', style: TextStyle(fontSize: AppTheme.fontSizeTableHeader, fontWeight: FontWeight.bold))),
            ],
            rows: calc.yearlyCosts.map((y) {
              return DataRow(cells: [
                DataCell(Text('${y.yearStart}', style: const TextStyle(fontSize: AppTheme.fontSizeTableData))),
                DataCell(Text('${(y.tasa * 100).toStringAsFixed(2)}%', style: const TextStyle(fontSize: AppTheme.fontSizeTableData))),
                DataCell(Text(y.diasPagados.toString(), style: const TextStyle(fontSize: AppTheme.fontSizeTableData))),
                DataCell(Text(FormatUtils.formatCurrency(y.cuotaAnual), style: const TextStyle(fontSize: AppTheme.fontSizeTableData))),
              ]);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCostoSummary(CostoMod40Calculation calc) {
    return Column(
      children: [
        const Divider(height: 4),
        ResultRow(label: 'Inversión Neta',
            value: FormatUtils.formatCurrency(calc.inversionNeta), isBold: true),
        ResultRow(label: 'Recuperación AFORE',
            value: FormatUtils.formatCurrency(calc.recuperacionAfore)),
        const Divider(height: 4),
        ResultRow(label: 'Inversión Total',
            value: FormatUtils.formatCurrency(calc.inversionTotal), isBold: true,
            valueColor: AppTheme.primary),
      ],
    );
  }

  // ============================================================
  // 2. PAGO RETROACTIVO
  // ============================================================

  Widget _buildPagoRetroactivoYMejoraSection(RetroactiveProvider provider,
      RetroactiveCalculation? retroCalc, InversionCalculation? invCalc) {
    final pensionConMod40 = provider.pensionMod40Calculation?.pensionMensual ?? 0;
    final pensionSinMod40 = provider.inversionCalculation?.pensionMensualSinMod40 ??
        provider.factAsigSinMod40Calculation?.totalPensionMensual ??
        provider.evaluator.metadata.financialRules.pensionActual?.pensionMensualActualizada ?? 0;

    return Card(
      child: ExpansionTile(
        title: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Pago Retroactivo y Mejora de Pensión',
              style: TextStyle(fontSize: AppTheme.fontSizeBodySmall, color: Colors.white)),
        ),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: false,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- PAGO RETROACTIVO ---
                const Text('Pago Retroactivo',
                    style: TextStyle(
                        fontSize: AppTheme.fontSizeBody,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const Divider(height: 4),
                _buildRetroactiveSlider(provider),
                if (retroCalc != null) ...[
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildRetroactiveResults(retroCalc),
                ],
                const Divider(height: 8),
                // --- MEJORA DE PENSIÓN ---
                const Text('Mejora de Pensión',
                    style: TextStyle(
                        fontSize: AppTheme.fontSizeBody,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const Divider(height: 4),
                _buildMejoraComparativa(pensionSinMod40, pensionConMod40),
                if (invCalc != null) ...[
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildAnalisisInversion(invCalc),
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildGanancia(invCalc),
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildTermometro(invCalc),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetroactiveSlider(RetroactiveProvider provider) {
    final rules = provider.evaluator.metadata.financialRules;
    final minYears = rules.minRetroactiveYears.toDouble();
    final maxYears = rules.maxRetroactiveYears.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Años Retroactivos: ',
                style: TextStyle(fontSize: AppTheme.fontSizeBody, color: AppTheme.textSecondary)),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: TextEditingController(
                  text: provider.retroactiveYears.toStringAsFixed(2),
                ),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: AppTheme.fontSizeInput),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                ),
                onSubmitted: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null) provider.setRetroactiveYears(parsed);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingXs),
        Slider(
          value: provider.retroactiveYears.clamp(minYears, maxYears),
          min: minYears,
          max: maxYears,
          divisions: (maxYears - minYears).toInt() * 4,
          activeColor: AppTheme.accent,
          label: '${provider.retroactiveYears.toStringAsFixed(2)} años',
          onChanged: (v) => provider.setRetroactiveYears(v),
        ),
      ],
    );
  }

  Widget _buildRetroactiveResults(RetroactiveCalculation calc) {
    return Column(
      children: [
        const Divider(height: 4),
        ResultRow(label: 'Costo Modalidad 40',
            value: FormatUtils.formatCurrency(calc.costoModalidad40)),
        ResultRow(label: 'Actualizaciones',
            value: FormatUtils.formatCurrency(calc.actualizaciones)),
        ResultRow(label: 'Recargos',
            value: FormatUtils.formatCurrency(calc.recargos)),
        ResultRow(label: 'Recuperación AFORE',
            value: FormatUtils.formatCurrency(calc.recuperacionAfore)),
        const Divider(height: 4),
        ResultRow(label: 'Costo Total',
            value: FormatUtils.formatCurrency(calc.costoTotal), isBold: true,
            valueColor: AppTheme.primary),
      ],
    );
  }

  // ============================================================
  // 3. INVERSIÓN (Mejora pensión)
  // ============================================================

  Widget _buildMejoraComparativa(double sinMod40, double conMod40) {
    final diferencia = conMod40 - sinMod40;
    final porcentaje = sinMod40 > 0 ? (diferencia / sinMod40) * 100 : 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sin Modalidad 40',
                      style: TextStyle(
                          fontSize: AppTheme.fontSizeBody,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 2),
                  Text(FormatUtils.formatCurrency(sinMod40),
                      style: const TextStyle(
                          fontSize: AppTheme.fontSizeTotalMedium,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Con Modalidad 40',
                      style: TextStyle(
                          fontSize: AppTheme.fontSizeBody,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary)),
                  const SizedBox(height: 2),
                  Text(FormatUtils.formatCurrency(conMod40),
                      style: const TextStyle(
                          fontSize: AppTheme.fontSizeTotalMedium,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingXs),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: diferencia > 0
                ? AppTheme.primary.withValues(alpha: 0.08)
                : Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(diferencia > 0 ? Icons.trending_up : Icons.trending_down,
                  color: diferencia > 0 ? AppTheme.primary : Colors.red, size: 18),
              const SizedBox(width: 6),
              Text('Diferencia: ${FormatUtils.formatCurrency(diferencia)} (${
                  porcentaje.toStringAsFixed(2)}%)',
                  style: const TextStyle(
                      fontSize: AppTheme.fontSizeBody,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalisisInversion(InversionCalculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 4),
        const Text('Análisis de Inversión',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 2),
        ResultRow(
          label: 'Flujos de pensión hasta los 80 años',
          value:
              'Sin Mod. 40: ${FormatUtils.formatCurrency(calc.flujoHasta80SinMod40)}  |  Con Mod. 40: ${FormatUtils.formatCurrency(calc.flujoHasta80ConMod40)}',
        ),
        ResultRow(label: 'Inversión Neta',
            value: FormatUtils.formatCurrency(calc.inversionNeta)),
        ResultRow(label: 'Recuperación AFORE',
            value: FormatUtils.formatCurrency(calc.recuperacionAfore)),
        ResultRow(label: 'Tasa de Rendimiento',
            value: FormatUtils.formatPercent(calc.tasaRendimiento)),
      ],
    );
  }

  Widget _buildGanancia(InversionCalculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 4),
        ResultRow(label: 'Ganancia Total',
            value: FormatUtils.formatCurrency(calc.gananciaTotal), isBold: true,
            valueColor: AppTheme.primary),
        ResultRow(label: 'Ganancia Mensual',
            value: FormatUtils.formatCurrency(calc.mejoraPension)),
        ResultRow(label: 'Periodo Recuperación',
            value: '${calc.periodoRecuperacionMeses.toStringAsFixed(2)} meses'),
      ],
    );
  }

  Widget _buildTermometro(InversionCalculation calc) {
    // Verdict color: green for good investments, orange for risky ones.
    final bool esBuena = calc.veredicto == 'Excelente Inversión' ||
        calc.veredicto == 'Buena Inversión' ||
        calc.veredicto == 'Inversión Aceptable';
    final Color verdictColor = esBuena ? Colors.green : Colors.orange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 4),
        const Text('Rendimiento de Inversión',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: AppTheme.spacingXs),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: calc.tasaRendimiento.clamp(0.0, 1.0),
            minHeight: 16,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
          ),
        ),
        const SizedBox(height: 2),
        Text('${(calc.tasaRendimiento * 100).toStringAsFixed(2)}% de rendimiento',
            style: const TextStyle(
                fontSize: AppTheme.fontSizeBodySmall,
                color: AppTheme.textSecondary)),
        const SizedBox(height: AppTheme.spacingXs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: verdictColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: verdictColor),
          ),
          child: Row(
            children: [
              Icon(
                esBuena ? Icons.check_circle : Icons.warning,
                color: verdictColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(calc.veredicto,
                        style: TextStyle(
                            fontSize: AppTheme.fontSizeCardTitle,
                            fontWeight: FontWeight.bold,
                            color: verdictColor)),
                    Text('Periodo de recuperación: ${calc.periodoRecuperacionMeses.toStringAsFixed(2)} meses',
                        style: const TextStyle(
                            fontSize: AppTheme.fontSizeBodySmall,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 4. FINANCIAMIENTO
  // ============================================================

  Widget _buildFinanciamientoSection(RetroactiveProvider provider, FinanciamientoCalculation? calc) {
    return Card(
      child: ExpansionTile(
        title: const Text('Financiamiento',
            style: TextStyle(
                fontSize: AppTheme.fontSizeCardTitle,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary)),
        subtitle: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Crédito, participaciones y plan de pagos',
              style: TextStyle(fontSize: AppTheme.fontSizeBodySmall, color: Colors.white)),
        ),
        initiallyExpanded: false,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (calc != null) ...[
                  _buildParticipaciones(calc),
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildCostoFinanciamiento(calc),
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildPlanPagos(calc),
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildPensionProjection(calc),
                  const SizedBox(height: AppTheme.spacingXs),
                  _buildFinanciamientoTermometro(calc),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.all(6.0),
                    child: Text('Complete los datos en CAPTURA para ver el financiamiento.',
                        style: TextStyle(fontSize: AppTheme.fontSizeBody, color: AppTheme.textSecondary)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipaciones(FinanciamientoCalculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Participaciones',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const Divider(height: 4),
        ResultRow(label: 'Inversión Total',
            value: FormatUtils.formatCurrency(calc.inversionTotal)),
        ResultRow(label: 'Participación Banco',
            value: FormatUtils.formatCurrency(calc.participacionBanco)),
        ResultRow(label: 'Participación Propia',
            value: FormatUtils.formatCurrency(calc.participacionPropia)),
        InfoRow(label: '% Banco', value: '${(calc.porcentajeBanco * 100).toStringAsFixed(1)}%'),
        InfoRow(label: '% Propio', value: '${(calc.porcentajePropio * 100).toStringAsFixed(1)}%'),
      ],
    );
  }

  Widget _buildCostoFinanciamiento(FinanciamientoCalculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 4),
        const Text('Costo Financiamiento',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const Divider(height: 4),
        ResultRow(label: 'Monto Crédito',
            value: FormatUtils.formatCurrency(calc.montoCredito)),
        ResultRow(label: 'Duración Trámite',
            value: '${calc.duracionTramiteMeses} meses'),
        ResultRow(label: 'Costo Financiamiento',
            value: FormatUtils.formatCurrency(calc.costoFinanciamiento)),
        ResultRow(label: 'Monto Máximo a Pagar',
            value: FormatUtils.formatCurrency(calc.montoMaximoPagar)),
      ],
    );
  }

  Widget _buildPlanPagos(FinanciamientoCalculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 4),
        const Text('Plan de Pagos',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const Divider(height: 4),
        ResultRow(label: 'Monto Crédito Redondeado',
            value: FormatUtils.formatCurrency(calc.montoCreditoRedondeado)),
        ResultRow(label: 'Plazo',
            value: '${calc.plazoMeses} meses'),
        ResultRow(label: 'Descuento Mensual',
            value: FormatUtils.formatCurrency(calc.descuentoMensual), isBold: true),
      ],
    );
  }

  Widget _buildPensionProjection(FinanciamientoCalculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 4),
        const Text('Proyección Pensión',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const Divider(height: 4),
        ResultRow(label: 'Pensión Mensual Inmediata',
            value: FormatUtils.formatCurrency(calc.pensionMensualInmediata)),
        ResultRow(label: 'Pensión Mensual Liquidación',
            value: FormatUtils.formatCurrency(calc.pensionMensualLiquidacion)),
        ResultRow(label: 'Flujo hasta 80 años',
            value: FormatUtils.formatCurrency(calc.flujoHasta80)),
        ResultRow(label: 'Periodos Recuperación',
            value: '${calc.periodosRecuperacionMeses.toStringAsFixed(2)} meses'),
      ],
    );
  }

  Widget _buildFinanciamientoTermometro(FinanciamientoCalculation calc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 4),
        const Text('Veredicto',
            style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
                const SizedBox(height: AppTheme.spacingXs),
                Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: calc.veredicto == 'RECOMENDABLE'
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: calc.veredicto == 'RECOMENDABLE' ? Colors.green : Colors.orange,
            ),
          ),
          child: Row(
            children: [
              Icon(
                calc.veredicto == 'RECOMENDABLE'
                    ? Icons.check_circle
                    : Icons.warning,
                color: calc.veredicto == 'RECOMENDABLE' ? Colors.green : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(calc.veredicto,
                        style: TextStyle(
                            fontSize: AppTheme.fontSizeCardTitle,
                            fontWeight: FontWeight.bold,
                            color: calc.veredicto == 'RECOMENDABLE'
                                ? Colors.green
                                : Colors.orange)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
