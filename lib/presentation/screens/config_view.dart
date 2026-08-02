import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../core/models/app_metadata.dart';
import '../../services/retroactive_provider.dart';

/// Configuration screen for authority-set values.
///
/// These values are published by the government (DOF, INEGI, etc.)
/// and change periodically. The user can update them here without
/// modifying the app's source code or JSON metadata.
///
/// Configurable values:
/// - Tasa de financiamiento
/// - Tasa de descuento
/// - Año base de pensión
class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> {
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
        final rules = provider.evaluator.metadata.financialRules;

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 4),

                // Tasas
                _buildTasasCard(provider, rules),
                const SizedBox(height: 4),

                // Info card
                _buildInfoCard(rules),
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
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.settings, color: AppTheme.accent, size: 16),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuración',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeCardTitle,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Tasas y parámetros de financiamiento.',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeBodySmall - 1,
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

  Widget _buildTasasCard(RetroactiveProvider provider, FinancialRules rules) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.dividerColor),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: AppTheme.primary, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Tasas de Interés',
                  style: TextStyle(fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildInfoRow('Tasa Financiamiento', '${(rules.tasaFinanciamiento * 100).toStringAsFixed(1)}%'),
            _buildInfoRow('Tasa Descuento', '${(rules.tasaDescuento * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(FinancialRules rules) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.dividerColor),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.primary, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Información',
                  style: TextStyle(fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildInfoRow('Año base', '${rules.baseYear}'),
            _buildInfoRow('UMA diaria (2024)', FormatUtils.formatCurrency(rules.umaDaily2024)),
            _buildInfoRow('Salario mínimo (2024)', FormatUtils.formatCurrency(rules.minWageDaily2024)),
            _buildInfoRow('Tasa inflación anual', '${(rules.inflationAnnualRate * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: AppTheme.fontSizeBodySmall, color: Colors.grey[700])),
          Text(value, style: const TextStyle(fontSize: AppTheme.fontSizeBodySmall, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
