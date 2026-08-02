/// Constants used throughout the pension calculation app.
/// This helps avoid magic numbers and makes the code more maintainable.
class PensionConstants {
  // UMA calculation
  static const double salarioRegistradoUmas = 25.0;
  
  // Date ranges
  static final DateTime minDate = DateTime(1950);
  static final DateTime maxDate = DateTime(2100);
  
  // Validation ranges
  static const int minSemanas = 1;
  static const int maxSemanas = 2500;
  static const double minSalario = 0.0;
  static const double maxSalario = 1000000.0;
  static const int minEdadRetiro = 60;
  static const int maxEdadRetiro = 75;
  static const int minAnoPension = 2020;
  static const int maxAnoPension = 2100;

  // Requisitos legales (Ley del Seguro Social 1973)
  /// Mínimo de semanas cotizadas para acceder a pensión (Art. 154 y 162 LSS 1973).
  static const int minSemanasLey73 = 500;
  /// Edad mínima para Cesantía en Edad Avanzada (Art. 154 LSS 1973).
  static const int minEdadPensionLey73 = 60;
  /// Edad para pensión de Vejez al 100% (Art. 162 LSS 1973).
  static const int edadVejezLey73 = 65;
  
  // Default values
  static const double defaultUmaDiaria = 133.87;
  static const double defaultSalarioRegistrado = 3346.75; // 25 * 133.87
  
  // Financial constants
  static const double porcentajeEsposa = 0.15;
  static const double porcentajeHijo = 0.10;
  static const double porcentajePadre = 0.10;
  
  // UI constants
  static const double cardElevation = 2.0;
  static const double cardBorderRadius = 8.0;
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  
  // Date formatting
  static const String dateFormatDisplay = 'dd/MM/yyyy';
  static const String dateFormatInput = 'yyyyMMdd';
  static const String dateFormatStorage = 'yyyy-MM-dd';
  
  // Error messages
  static const String errorDateInvalid = 'Fecha inválida';
  static const String errorDateRange = 'Fecha fuera de rango válido (1950-2100)';
  static const String errorSalarioInvalid = 'Salario inválido';
  static const String errorSemanasInvalid = 'Número de semanas inválido (1-2500)';
  static const String errorEdadInvalid = 'Edad de retiro inválida (60-75)';
  static const String errorAnoInvalid = 'Año de pensión inválido (2020-2100)';
  static const String errorMinSemanasLey73 =
      'Se requieren mínimo 500 semanas cotizadas para acceder a pensión (Ley 73, Art. 154/162)';
  static const String errorEdadRetiroNoAlcanzada =
      'Debes haber cumplido la edad de retiro seleccionada para que la pensión aplique (Ley 73)';
}