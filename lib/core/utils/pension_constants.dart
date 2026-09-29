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

  /// Fecha límite de aplicabilidad de la Ley 73: se requiere haber cotizado
  /// con anterioridad al 1 de julio de 1997 (régimen anterior a la Ley 1997).
  static final DateTime fechaLimiteLey73 = DateTime(1997, 7, 1);

  // ── Vigencia / conservación de derechos (Art. 150 LSS 1973) ──

  /// Fracción del tiempo cotizado durante la cual se conservan los derechos
  /// después de la baja: la cuarta parte (Art. 150 LSS 1973).
  static const double fraccionConservacionDerechos = 0.25;

  /// Piso mínimo de conservación de derechos: 12 meses. Si la cuarta parte
  /// del tiempo cotizado fuera menor, se amplía a este mínimo (Art. 150).
  static const int minMesesConservacionDerechos = 12;

  /// Semanas por año, para convertir semanas cotizadas a años.
  static const double semanasPorAnio = 52.0;

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
  static const String dateFormatDisplay = 'yyyy-MM-dd';
  static const String dateFormatInput = 'yyyyMMdd';
  static const String dateFormatStorage = 'yyyy-MM-dd';

  // Error messages
  static const String errorDateInvalid = 'Fecha inválida';
  static const String errorDateRange =
      'Fecha fuera de rango válido (1950-2100)';
  static const String errorSalarioInvalid = 'Salario inválido';
  static const String errorSemanasInvalid =
      'Número de semanas inválido (1-2500)';
  static const String errorEdadInvalid = 'Edad de retiro inválida (60-75)';
  static const String errorAnoInvalid = 'Año de pensión inválido (2020-2100)';
  static const String errorMinSemanasLey73 =
      'Se requieren mínimo 500 semanas cotizadas para acceder a pensión (Ley 73, Art. 154/162)';
  static const String errorEdadRetiroNoAlcanzada =
      'Debes haber cumplido la edad de retiro seleccionada para que la pensión aplique (Ley 73)';
  static const String warningLey73NoAplica =
      'La fecha de nacimiento es posterior al 1 de julio de 1997: es probable '
      'que NO estés amparado por la Ley del Seguro Social 1973 (aplicaría la Ley 1997). '
      'Verifica tu régimen de cotización.';
  static const String errorLey73FechaAltaPosterior =
      'La fecha de alta en el IMSS es posterior al 1 de julio de 1997: '
      'es probable que NO estés amparado por la Ley del Seguro Social 1973 '
      '(aplicaría la Ley 1997). Verifica tu régimen de cotización.';
  static const String warningLey73SinFechaAlta =
      'Para confirmar que aplica la Ley 1973, necesitamos tu fecha de alta '
      'en el IMSS (cuándo empezaste a cotizar). Si no la recuerdas, puedes '
      'dejarla vacía y capturarla más adelante en la pestaña Captura.';
  static const String warningVigenciaDerechosExcedida =
      'La fecha de cálculo excede la vigencia de derechos (Art. 150 LSS 1973): '
      'el asegurado que deja de cotizar conserva sus derechos por la cuarta '
      'parte del tiempo cotizado (mínimo 12 meses) contado desde la fecha de '
      'baja. Al superarse ese límite, el derecho a la pensión se pierde; '
      'reincorpora la cotización antes de la fecha límite para conservarlo.';
  static const String errorFechaCalculoMenorNacimiento =
      'La fecha de cálculo no puede ser anterior a la fecha de nacimiento.';
  static const String errorEdadNoPlausible =
      'La edad calculada no es plausible; verifica las fechas de nacimiento y de cálculo.';
}
