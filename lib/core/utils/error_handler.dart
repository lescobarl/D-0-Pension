import 'package:flutter/foundation.dart';

/// Centralized error handling and logging for the pension calculator.
class ErrorHandler {
  static final List<ErrorLog> _logs = [];
  
  /// Log an error with optional stack trace and context.
  static void logError(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
    bool fatal = false,
  }) {
    final log = ErrorLog(
      timestamp: DateTime.now(),
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      context: context,
      fatal: fatal,
    );
    
    _logs.add(log);
    
    // Print to console for development (only in debug builds)
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ERROR] ${log.toString()}');
    }
    
    // In production, you could send to analytics service
    // _sendToAnalytics(log);
  }
  
  /// Log a warning (non-critical issue).
  static void logWarning(String message, {String? context}) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[WARNING] $message ${context != null ? 'Context: $context' : ''}');
    }
  }
  
  /// Log informational message.
  static void logInfo(String message, {String? context}) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[INFO] $message ${context != null ? 'Context: $context' : ''}');
    }
  }

  /// Log a debug/diagnostic message (only in debug builds).
  ///
  /// No-op in release builds, so diagnostic tracing never reaches production.
  static void logDebug(String message, {String? context}) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[DEBUG] $message ${context != null ? 'Context: $context' : ''}');
    }
  }
  
  /// Get all error logs.
  static List<ErrorLog> getLogs() => List.unmodifiable(_logs);
  
  /// Clear all logs.
  static void clearLogs() => _logs.clear();
  
  /// Handle a calculation error gracefully.
  static String handleCalculationError(dynamic error, StackTrace stackTrace) {
    logError(error, stackTrace: stackTrace, context: 'Calculation error');
    
    // Return user-friendly error message
    if (error is FormatException) {
      return 'Error en el formato de datos. Verifica los valores ingresados.';
    } else if (error is ArgumentError) {
      return 'Datos inválidos para el cálculo. Revisa los valores.';
    } else if (error is StateError) {
      return 'El motor de cálculo no está inicializado. Reinicia la aplicación.';
    } else {
      return 'Error inesperado en el cálculo. Intenta nuevamente.';
    }
  }
  
  /// Handle a persistence error gracefully.
  static String handlePersistenceError(dynamic error, StackTrace stackTrace) {
    logError(error, stackTrace: stackTrace, context: 'Persistence error');
    
    return 'Error al guardar datos. Los cambios no se guardaron.';
  }
  
  /// Handle a network/API error gracefully.
  static String handleNetworkError(dynamic error, StackTrace stackTrace) {
    logError(error, stackTrace: stackTrace, context: 'Network error');
    
    return 'Error de conexión. Verifica tu internet e intenta nuevamente.';
  }
}

/// Represents a single error log entry.
class ErrorLog {
  final DateTime timestamp;
  final String error;
  final String? stackTrace;
  final String? context;
  final bool fatal;
  
  ErrorLog({
    required this.timestamp,
    required this.error,
    this.stackTrace,
    this.context,
    this.fatal = false,
  });
  
  @override
  String toString() {
    return 'ErrorLog{timestamp: $timestamp, error: $error, context: $context, fatal: $fatal}';
  }
  
  /// Convert to map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'error': error,
      'stackTrace': stackTrace,
      'context': context,
      'fatal': fatal,
    };
  }
}