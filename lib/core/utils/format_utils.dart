import 'package:intl/intl.dart';

/// Shared formatting utilities for currency and percentage display.
///
/// Eliminates duplication of [formatCurrency] and [formatPercent]
/// across all 6 calculation model classes.
class FormatUtils {
  FormatUtils._();

  /// Format a numeric value as Mexican Peso currency.
  /// Example: `\$1,234,567.89`
  static String formatCurrency(double value) {
    final formatter = NumberFormat('#,##0.00', 'es_MX');
    return '\$${formatter.format(value)}';
  }

  /// Format a decimal ratio as a percentage string.
  /// Example: `0.3769` → `37.69%`
  static String formatPercent(double value) {
    final formatter = NumberFormat('#,##0.00', 'es_MX');
    return '${formatter.format(value * 100)}%';
  }
}
