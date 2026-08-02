import 'pension_constants.dart';

/// Result of a validation operation
class ValidationResult {
  final bool isValid;
  final bool isWarning;
  final String message;
  
  const ValidationResult._({
    required this.isValid,
    required this.isWarning,
    required this.message,
  });
  
  /// Creates a valid validation result
  factory ValidationResult.valid() => const ValidationResult._(
    isValid: true,
    isWarning: false,
    message: '',
  );
  
  /// Creates a warning validation result
  factory ValidationResult.warning(String message) => ValidationResult._(
    isValid: true,  // Warning still allows submission
    isWarning: true,
    message: message,
  );
  
  /// Creates an error validation result
  factory ValidationResult.error(String message) => ValidationResult._(
    isValid: false,
    isWarning: false,
    message: message,
  );
}

/// Function type for validation functions
typedef ValidationFunction = ValidationResult Function(String value);

/// Input validation utilities for the pension calculator.
/// Provides consistent validation across the entire application.
class InputValidator {
  /// Validates a date string in format YYYYMMDD or YYYY-MM-DD.
  /// Returns ValidationResult.
  static ValidationResult validateDate(String value) {
    if (value.isEmpty) return ValidationResult.valid();
    
    final cleaned = value.replaceAll('-', '');
    if (cleaned.length != 8) {
      return ValidationResult.error(PensionConstants.errorDateInvalid);
    }
    
    try {
      final year = int.parse(cleaned.substring(0, 4));
      final month = int.parse(cleaned.substring(4, 6));
      final day = int.parse(cleaned.substring(6, 8));
      
      final date = DateTime(year, month, day);
      
      // Check if date is valid (e.g., not Feb 30)
      if (date.year != year || date.month != month || date.day != day) {
        return ValidationResult.error(PensionConstants.errorDateInvalid);
      }
      
      // Check range
      if (date.isBefore(PensionConstants.minDate) ||
          date.isAfter(PensionConstants.maxDate)) {
        return ValidationResult.error(PensionConstants.errorDateRange);
      }
      
      return ValidationResult.valid();
    } catch (e) {
      return ValidationResult.error(PensionConstants.errorDateInvalid);
    }
  }
  
  /// Validates a salary value.
  /// Returns ValidationResult.
  static ValidationResult validateSalary(String value) {
    if (value.isEmpty) return ValidationResult.valid();
    
    final parsed = double.tryParse(value.replaceAll(',', ''));
    if (parsed == null) {
      return ValidationResult.error(PensionConstants.errorSalarioInvalid);
    }
    
    if (parsed < PensionConstants.minSalario ||
        parsed > PensionConstants.maxSalario) {
      return ValidationResult.error(
        'Salario debe estar entre \$${PensionConstants.minSalario} y \$${PensionConstants.maxSalario}'
      );
    }
    
    return ValidationResult.valid();
  }
  
  /// Validates number of weeks.
  /// Returns ValidationResult.
  static ValidationResult validateWeeks(String value) {
    if (value.isEmpty) return ValidationResult.valid();
    
    final parsed = int.tryParse(value);
    if (parsed == null) {
      return ValidationResult.error(PensionConstants.errorSemanasInvalid);
    }
    
    if (parsed < PensionConstants.minSemanas ||
        parsed > PensionConstants.maxSemanas) {
      return ValidationResult.error(
        'Semanas deben estar entre ${PensionConstants.minSemanas} y ${PensionConstants.maxSemanas}'
      );
    }
    
    return ValidationResult.valid();
  }
  
  /// Validates retirement age.
  /// Returns ValidationResult.
  static ValidationResult validateRetirementAge(String value) {
    if (value.isEmpty) return ValidationResult.valid();
    
    final parsed = int.tryParse(value);
    if (parsed == null) {
      return ValidationResult.error(PensionConstants.errorEdadInvalid);
    }
    
    if (parsed < PensionConstants.minEdadRetiro ||
        parsed > PensionConstants.maxEdadRetiro) {
      return ValidationResult.error(
        'Edad de retiro debe estar entre ${PensionConstants.minEdadRetiro} y ${PensionConstants.maxEdadRetiro} años'
      );
    }
    
    return ValidationResult.valid();
  }
  
  /// Validates pension year.
  /// Returns ValidationResult.
  static ValidationResult validatePensionYear(String value) {
    if (value.isEmpty) return ValidationResult.valid();
    
    final parsed = int.tryParse(value);
    if (parsed == null) {
      return ValidationResult.error(PensionConstants.errorAnoInvalid);
    }
    
    if (parsed < PensionConstants.minAnoPension ||
        parsed > PensionConstants.maxAnoPension) {
      return ValidationResult.error(
        'Año de pensión debe estar entre ${PensionConstants.minAnoPension} y ${PensionConstants.maxAnoPension}'
      );
    }
    
    return ValidationResult.valid();
  }

  /// Calcula la edad actual (años con fracción decimal) entre [fechaNacimiento]
  /// y [fechaCalculo]. Usa 365.25 días por año para manejar años bisiestos.
  static double calcularEdadActual(DateTime fechaNacimiento, DateTime fechaCalculo) {
    if (fechaCalculo.isBefore(fechaNacimiento)) return 0;
    final days = fechaCalculo.difference(fechaNacimiento).inDays;
    return days / 365.25;
  }

  /// Valida el requisito legal de mínimo 500 semanas cotizadas (Ley 73).
  /// Retorna un [ValidationResult.warning] cuando el mínimo no se cumple, para
  /// permitir la captura del valor real pero alertar sobre la elegibilidad.
  static ValidationResult validateMinSemanasLey73(int semanas) {
    if (semanas < PensionConstants.minSemanasLey73) {
      return ValidationResult.warning(
        'Faltan ${PensionConstants.minSemanasLey73 - semanas} semanas para el mínimo '
        'legal de ${PensionConstants.minSemanasLey73} (Ley 73).',
      );
    }
    return ValidationResult.valid();
  }

  /// Formats a number with thousands separators.
  static String formatNumber(double value) {
    return value.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
  
  /// Parses a formatted number string back to double.
  static double? parseFormattedNumber(String value) {
    final cleaned = value.replaceAll(',', '').replaceAll('\$', '').trim();
    return double.tryParse(cleaned);
  }
  
  /// Auto-formats a date string from YYYYMMDD to YYYY-MM-DD.
  static String autoFormatDate(String input) {
    final cleaned = input.replaceAll('-', '');
    if (cleaned.length != 8) return input;
    
    try {
      final year = cleaned.substring(0, 4);
      final month = cleaned.substring(4, 6);
      final day = cleaned.substring(6, 8);
      return '$year-$month-$day';
    } catch (e) {
      return input;
    }
  }
}