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

  /// Format a numeric value as Mexican Peso currency WITHOUT decimals.
  /// Used exclusively for final RESULTS (pensions, totals, increments) to
  /// keep the UI clean and uncluttered; calculation bases keep 2 decimals
  /// via [formatCurrency].
  /// Example: `\$1,234,567`
  static String formatCurrencyInt(double value) {
    final formatter = NumberFormat('#,##0', 'es_MX');
    return '\$${formatter.format(value.round())}';
  }

  /// Format a decimal ratio as a percentage string.
  /// Example: `0.3769` → `37.69%`
  static String formatPercent(double value) {
    final formatter = NumberFormat('#,##0.00', 'es_MX');
    return '${formatter.format(value * 100)}%';
  }

  /// Format a plain number with thousands separators and optional decimals.
  /// Example: `2090.29` → `2,090.29`; `2087` → `2,087`
  static String formatNumber(double value, {int decimals = 0}) {
    final suffix = decimals > 0 ? '.${List.filled(decimals, '0').join()}' : '';
    final formatter = NumberFormat('#,##0$suffix', 'es_MX');
    return formatter.format(value);
  }
}
