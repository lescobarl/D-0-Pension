/// Represents the application metadata loaded from [assets/config/app_metadata.json].
class AppMetadata {
  final String appName;
  final String version;
  final String description;
  final List<TabConfig> tabs;
  final FinancialRules financialRules;
  final ThemeConfig theme;
  final LegalNotes legalNotes;
  final TestScenarios testScenarios;

  AppMetadata({
    required this.appName,
    required this.version,
    required this.description,
    required this.tabs,
    required this.financialRules,
    required this.theme,
    required this.legalNotes,
    TestScenarios? testScenarios,
  }) : testScenarios = testScenarios ?? TestScenarios.empty();

  factory AppMetadata.fromJson(Map<String, dynamic> json) {
    return AppMetadata(
      appName: json['app_name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tabs: (json['tabs'] as List<dynamic>?)
              ?.map((e) => TabConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      financialRules: FinancialRules.fromJson(
          json['financial_rules'] as Map<String, dynamic>? ?? {}),
      theme: ThemeConfig.fromJson(
          json['theme'] as Map<String, dynamic>? ?? {}),
      legalNotes: LegalNotes.fromJson(
          json['legal_notes'] as Map<String, dynamic>? ?? {}),
      testScenarios: json['test_scenarios'] != null
          ? TestScenarios.fromJson(json['test_scenarios'] as Map<String, dynamic>)
          : TestScenarios.empty(),
    );
  }
}

/// Default values for all user-input fields, sourced from the Excel calculator.
///
/// These values are used when no persisted data exists (first launch or after
/// data version bump). They are defined in [assets/config/app_metadata.json]
/// under the "default_values" key and reflect the current state of the Excel
/// calculator to ensure App and Excel start from identical inputs.
class DefaultValues {
  final DateTime fechaNacimiento;
  final int edadMinimaPension;
  final int semanasDescontadasAfore;
  final bool tieneEsposa;
  final int numeroHijos;
  final int numeroPadres;
  final double salarioPromedio250Semanas;
  final int totalSemanasSinMod40;
  final double edadRetiro;
  final double semanasAntesMod40;
  final double semanasEnMod40;
  final double totalSemanasConMod40;
  final double salarioDiarioPromedio;
  final double umaDiaria;
  final double salarioMinimoDiario;
  final int pensionYear;
  final int semanasCotizadas;
  final double salarioRegistrado;
  final double retroactiveYears;
  final double salarioDiario;
  final int edadRetiroSinMod40;
  final double participacionBancoMax;

  const DefaultValues({
    required this.fechaNacimiento,
    required this.edadMinimaPension,
    required this.semanasDescontadasAfore,
    required this.tieneEsposa,
    required this.numeroHijos,
    required this.numeroPadres,
    required this.salarioPromedio250Semanas,
    required this.totalSemanasSinMod40,
    required this.edadRetiro,
    required this.semanasAntesMod40,
    required this.semanasEnMod40,
    required this.totalSemanasConMod40,
    required this.salarioDiarioPromedio,
    required this.umaDiaria,
    required this.salarioMinimoDiario,
    required this.pensionYear,
    required this.semanasCotizadas,
    required this.salarioRegistrado,
    required this.retroactiveYears,
    required this.salarioDiario,
    required this.edadRetiroSinMod40,
    required this.participacionBancoMax,
  });

  factory DefaultValues.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String? key) {
      // No hardcoded date fallback. If key is missing or invalid, return epoch.
      // Real default comes from app_metadata.json (fecha_nacimiento).
      final str = json[key] as String?;
      if (str == null) return DateTime.fromMillisecondsSinceEpoch(0);
      try {
        return DateTime.parse(str);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    // NOTE: No hardcoded scenario values. All defaults come from app_metadata.json
    // (default_values section). If a key is missing, returns 0/empty neutral value
    // so the UI gracefully handles missing data.
    return DefaultValues(
      fechaNacimiento: parseDate('fecha_nacimiento'),
      edadMinimaPension: json['edad_minima_pension'] as int? ?? 0,
      semanasDescontadasAfore: json['semanas_descontadas_afore'] as int? ?? 0,
      tieneEsposa: json['tiene_esposa'] as bool? ?? false,
      numeroHijos: json['numero_hijos'] as int? ?? 0,
      numeroPadres: json['numero_padres'] as int? ?? 0,
      salarioPromedio250Semanas: (json['salario_promedio_250_semanas'] as num?)?.toDouble() ?? 0,
      totalSemanasSinMod40: json['total_semanas_sin_mod40'] as int? ?? 0,
      edadRetiro: (json['edad_retiro'] as num?)?.toDouble() ?? 0,
      semanasAntesMod40: (json['semanas_antes_mod40'] as num?)?.toDouble() ?? 0,
      semanasEnMod40: (json['semanas_en_mod40'] as num?)?.toDouble() ?? 0,
      totalSemanasConMod40: (json['total_semanas_con_mod40'] as num?)?.toDouble() ?? 0,
      salarioDiarioPromedio: (json['salario_diario_promedio'] as num?)?.toDouble() ?? 0,
      umaDiaria: (json['uma_diaria'] as num?)?.toDouble() ?? 0,
      salarioMinimoDiario: (json['salario_minimo_diario'] as num?)?.toDouble() ?? 0,
      pensionYear: json['pension_year'] as int? ?? 0,
      semanasCotizadas: json['semanas_cotizadas'] as int? ?? 0,
      salarioRegistrado: (json['salario_registrado'] as num?)?.toDouble() ?? 0,
      retroactiveYears: (json['retroactive_years'] as num?)?.toDouble() ?? 0,
      salarioDiario: (json['salario_diario'] as num?)?.toDouble() ?? 0,
      edadRetiroSinMod40: (json['edad_retiro_sin_mod40'] as num?)?.toInt() ?? 0,
      participacionBancoMax: (json['participacion_banco_max'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TabConfig {
  final String key;
  final String label;
  final String sheet;
  final String icon;

  TabConfig({
    required this.key,
    required this.label,
    required this.sheet,
    required this.icon,
  });

  factory TabConfig.fromJson(Map<String, dynamic> json) {
    return TabConfig(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      sheet: json['sheet'] as String? ?? '',
      icon: json['icon'] as String? ?? 'tab',
    );
  }
}

/// Entry in the UMA projection table, matching Excel's `_sheet_1` columns N (year) and O (UMA).
/// Historical values (2017-2026) are hardcoded; future years (2027+) are projected at 4.5% annual increase.
class UmaProjectionEntry {
  final int year;
  final double uma;

  const UmaProjectionEntry({required this.year, required this.uma});

  factory UmaProjectionEntry.fromJson(Map<String, dynamic> json) {
    return UmaProjectionEntry(
      year: json['year'] as int,
      uma: (json['uma'] as num).toDouble(),
    );
  }
}

/// Entry in the minimum wage projection table, matching Excel's `_sheet_1` columns N (year) and P (SM).
/// Historical values (2017-2026) are hardcoded; future years (2027+) are projected at 5.7% annual increase.
class MinWageProjectionEntry {
  final int year;
  final double minWage;

  const MinWageProjectionEntry({required this.year, required this.minWage});

  factory MinWageProjectionEntry.fromJson(Map<String, dynamic> json) {
    return MinWageProjectionEntry(
      year: json['year'] as int,
      minWage: (json['min_wage'] as num).toDouble(),
    );
  }
}

class FinancialRules {
  final int baseYear;
  final double umaDaily2024;
  final double minWageDaily2024;
  final double inflationAnnualRate;
  final List<UmaProjectionEntry> umaProjectionTable;
  final List<MinWageProjectionEntry> minWageProjectionTable;
  final Map<String, double> monthlyInflationRates;
  final double recargoMonthlyRate;
  final double recargoMonthlyRatePost2026;
  final int recargoYearThreshold;
  final int maxUmaMultiplier;
  final int maxRetroactiveYears;
  final int minRetroactiveYears;
  final double aforeRecoveryRate;
  final double aforeRetroactiveRecoveryRate;
  final List<YearFactor> inflationYearFactors;
  final List<CostoMod40Rate> costoMod40Rates;
  final List<PensionAgePercentage> pensionAgePercentages;
  final PensionAgeDropdown pensionAgeDropdown;
  final EdadRoundingRule edadRoundingRule;
  final double presidentialDecreeRate;
  final double aguinaldoFactor;
  final int daysInYear;
  final int weeksPerYear;
  final int minWeeksForIncrement;
  final int lifeExpectancyYears;
  final double asignacionEsposaPercentage;
  final double asignacionHijosPercentage;
  final double asignacionPadresPercentage;
  final double ayudaAsistencialNoBeneficiarios;
  final double ayudaAsistencialUnPadre;
  final int financingTermMonths;
  final int financingProcessingMonths;
  final double projectionP247;
  final double projectionAn247;
  final double minWageGrowthRate;
  final double tasaFinanciamiento;
  final double tasaDescuento;
  final List<UmasPercentage> cuantiaBasicaPercentages;
  final List<UmasPercentage> incrementoPercentages;
  final DateTime defaultStartDate;
  final DateTime defaultEndDate;
  final List<CreditTableEntry> creditTable;
  final PensionActualData? pensionActual;
  final DefaultValues defaultValues;
  final double flujoFactor;
  final int monthsWithAguinaldo;
  final int totalSemanasPromedio;
  final double capacidadPagoPorcentaje;
  final double forecastFactor;
  final double segundoFondeadorFactor;
  final double epsilonValor;
  final int redondeoCredito;
  final int inflacionAniosProyeccion;
  final List<VeredictoThreshold> veredictoThresholds;
  final String veredictoDefault;

  FinancialRules({
    required this.baseYear,
    required this.umaDaily2024,
    required this.minWageDaily2024,
    required this.inflationAnnualRate,
    required this.umaProjectionTable,
    required this.minWageProjectionTable,
    required this.monthlyInflationRates,
    required this.recargoMonthlyRate,
    required this.recargoMonthlyRatePost2026,
    required this.recargoYearThreshold,
    required this.maxUmaMultiplier,
    required this.maxRetroactiveYears,
    required this.minRetroactiveYears,
    required this.aforeRecoveryRate,
    required this.aforeRetroactiveRecoveryRate,
    required this.inflationYearFactors,
    required this.costoMod40Rates,
    required this.pensionAgePercentages,
    required this.pensionAgeDropdown,
    required this.edadRoundingRule,
    required this.presidentialDecreeRate,
    required this.aguinaldoFactor,
    required this.daysInYear,
    required this.weeksPerYear,
    required this.minWeeksForIncrement,
    required this.lifeExpectancyYears,
    required this.asignacionEsposaPercentage,
    required this.asignacionHijosPercentage,
    required this.asignacionPadresPercentage,
    required this.ayudaAsistencialNoBeneficiarios,
    required this.ayudaAsistencialUnPadre,
    required this.financingTermMonths,
    required this.financingProcessingMonths,
    required this.projectionP247,
    required this.projectionAn247,
    required this.minWageGrowthRate,
    required this.tasaFinanciamiento,
    required this.tasaDescuento,
    required this.cuantiaBasicaPercentages,
    required this.incrementoPercentages,
    required this.defaultStartDate,
    required this.defaultEndDate,
    required this.creditTable,
    required this.pensionActual,
    required this.defaultValues,
    required this.flujoFactor,
    required this.monthsWithAguinaldo,
    required this.totalSemanasPromedio,
    required this.capacidadPagoPorcentaje,
    required this.forecastFactor,
    required this.segundoFondeadorFactor,
    required this.epsilonValor,
    required this.redondeoCredito,
    required this.inflacionAniosProyeccion,
    required this.veredictoThresholds,
    required this.veredictoDefault,
  });

  factory FinancialRules.fromJson(Map<String, dynamic> json) {
    return FinancialRules(
      baseYear: _getInt(json, 'base_year'),
      umaDaily2024: _getDouble(json, 'uma_daily_2024'),
      minWageDaily2024: _getDouble(json, 'min_wage_daily_2024'),
      inflationAnnualRate: _getDouble(json, 'inflation_annual_rate'),
      umaProjectionTable: _getList(json, 'uma_projection_table', UmaProjectionEntry.fromJson),
      minWageProjectionTable: _getList(json, 'min_wage_projection_table', MinWageProjectionEntry.fromJson),
      monthlyInflationRates: _parseMonthlyInflationRates(json['monthly_inflation_rates'] as Map<String, dynamic>?),
      recargoMonthlyRate: _getDouble(json, 'recargo_monthly_rate'),
      recargoMonthlyRatePost2026: _getDouble(json, 'recargo_monthly_rate_post_2026'),
      recargoYearThreshold: _getInt(json, 'recargo_year_threshold'),
      maxUmaMultiplier: _getInt(json, 'max_uma_multiplier'),
      maxRetroactiveYears: _getInt(json, 'max_retroactive_years'),
      minRetroactiveYears: _getInt(json, 'min_retroactive_years'),
      aforeRecoveryRate: _getDouble(json, 'afore_recovery_rate'),
      aforeRetroactiveRecoveryRate: _getDouble(json, 'afore_retroactive_recovery_rate'),
      inflationYearFactors: _getList(json, 'inflation_year_factors', YearFactor.fromJson),
      costoMod40Rates: _getList(json, 'costo_mod40_rates', CostoMod40Rate.fromJson),
      pensionAgePercentages: _getList(json, 'pension_age_percentages', PensionAgePercentage.fromJson),
      pensionAgeDropdown: json['pension_age_dropdown'] != null
          ? PensionAgeDropdown.fromJson(json['pension_age_dropdown'] as Map<String, dynamic>)
          : PensionAgeDropdown.fromJson({}),
      edadRoundingRule: json['edad_rounding_rule'] != null
          ? EdadRoundingRule.fromJson(json['edad_rounding_rule'] as Map<String, dynamic>)
          : EdadRoundingRule.fromJson({}),
      presidentialDecreeRate: _getDouble(json, 'presidential_decree_rate'),
      aguinaldoFactor: _getDouble(json, 'aguinaldo_factor'),
      daysInYear: _getInt(json, 'days_in_year'),
      weeksPerYear: _getInt(json, 'weeks_per_year'),
      minWeeksForIncrement: _getInt(json, 'min_weeks_for_increment'),
      lifeExpectancyYears: _getInt(json, 'life_expectancy_years'),
      asignacionEsposaPercentage: _getDouble(json, 'asignacion_esposa_percentage'),
      asignacionHijosPercentage: _getDouble(json, 'asignacion_hijos_percentage'),
      asignacionPadresPercentage: _getDouble(json, 'asignacion_padres_percentage'),
      ayudaAsistencialNoBeneficiarios: _getDouble(json, 'ayuda_asistencial_no_beneficiarios'),
      ayudaAsistencialUnPadre: _getDouble(json, 'ayuda_asistencial_un_padre'),
      financingTermMonths: _getInt(json, 'financing_term_months'),
      financingProcessingMonths: _getInt(json, 'financing_processing_months'),
      projectionP247: _getDouble(json, 'projection_p247'),
      projectionAn247: _getDouble(json, 'projection_an247'),
      minWageGrowthRate: _getDouble(json, 'min_wage_growth_rate'),
      tasaFinanciamiento: _getDouble(json, 'tasa_financiamiento'),
      tasaDescuento: _getDouble(json, 'tasa_descuento'),
      cuantiaBasicaPercentages: _getList(json, 'cuantia_basica_percentages', UmasPercentage.fromJson),
      incrementoPercentages: _getList(json, 'incremento_percentages', UmasPercentage.fromJson),
      defaultStartDate: _parseDate(json['default_start_date'] as String?),
      defaultEndDate: _parseDate(json['default_end_date'] as String?),
      creditTable: _getList(json, 'credit_table', CreditTableEntry.fromJson),
      pensionActual: json['pension_actual'] != null
          ? PensionActualData.fromJson(json['pension_actual'] as Map<String, dynamic>)
          : null,
      defaultValues: json['default_values'] != null
          ? DefaultValues.fromJson(json['default_values'] as Map<String, dynamic>)
          : DefaultValues.fromJson({}),
      flujoFactor: _getDouble(json, 'flujo_factor'),
      monthsWithAguinaldo: _getInt(json, 'months_with_aguinaldo'),
      totalSemanasPromedio: _getInt(json, 'total_semanas_promedio'),
      capacidadPagoPorcentaje: _getDouble(json, 'capacidad_pago_porcentaje'),
      forecastFactor: _getDouble(json, 'forecast_factor'),
      segundoFondeadorFactor: _getDouble(json, 'segundo_fondeador_factor'),
      epsilonValor: _getDouble(json, 'epsilon_valor'),
      redondeoCredito: _getInt(json, 'redondeo_credito'),
      inflacionAniosProyeccion: _getInt(json, 'inflacion_anios_proyeccion'),
      veredictoThresholds: _getList(json, 'veredicto_thresholds', VeredictoThreshold.fromJson),
      veredictoDefault: json['veredicto_default'] as String? ?? (throw ArgumentError('Missing required field: financial_rules.veredicto_default in app_metadata.json')),
    );
  }

  /// Safely extract a required int from JSON, throwing if missing.
  static int _getInt(Map<String, dynamic> json, String key) {
    final val = json[key];
    if (val == null) {
      throw ArgumentError('Missing required field: financial_rules.$key in app_metadata.json');
    }
    return (val as num).toInt();
  }

  /// Safely extract a required double from JSON, throwing if missing.
  static double _getDouble(Map<String, dynamic> json, String key) {
    final val = json[key];
    if (val == null) {
      throw ArgumentError('Missing required field: financial_rules.$key in app_metadata.json');
    }
    return (val as num).toDouble();
  }

  /// Safely extract a required list from JSON, throwing if missing.
  static List<T> _getList<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final val = json[key];
    if (val == null) {
      throw ArgumentError('Missing required field: financial_rules.$key in app_metadata.json');
    }
    return (val as List<dynamic>).map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Parse a date string in "yyyy-MM-dd" format, throwing if missing.
  static DateTime _parseDate(String? dateStr) {
    if (dateStr == null) {
      throw ArgumentError('Missing required date field in app_metadata.json');
    }
    return DateTime.parse(dateStr);
  }

  /// Parse monthly inflation rates from JSON, throwing if missing.
  static Map<String, double> _parseMonthlyInflationRates(Map<String, dynamic>? json) {
    if (json == null) {
      throw ArgumentError('Missing required field: financial_rules.monthly_inflation_rates in app_metadata.json');
    }
    return json.map((key, value) => MapEntry(key, (value as num).toDouble()));
  }
}

class YearFactor {
  final int year;
  final double costo;

  YearFactor({required this.year, required this.costo});

  factory YearFactor.fromJson(Map<String, dynamic> json) {
    return YearFactor(
      year: json['year'] as int? ?? 0,
      costo: (json['costo'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CostoMod40Rate {
  final int yearStart;
  final int yearEnd;
  final double rate;

  CostoMod40Rate({
    required this.yearStart,
    required this.yearEnd,
    required this.rate,
  });

  factory CostoMod40Rate.fromJson(Map<String, dynamic> json) {
    return CostoMod40Rate(
      yearStart: json['year_start'] as int? ?? 0,
      yearEnd: json['year_end'] as int? ?? 0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PensionAgePercentage {
  final int age;
  final double percentage;
  final String type;

  PensionAgePercentage({
    required this.age,
    required this.percentage,
    required this.type,
  });

  factory PensionAgePercentage.fromJson(Map<String, dynamic> json) {
    return PensionAgePercentage(
      age: json['age'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] as String? ?? '',
    );
  }
}

/// Configuration for the "Edad de Retiro" dropdown in the data capture view.
///
/// The dropdown offers each integer year (60, 61, 62, ...) plus a fractional
/// option (60+fraccionThreshold, 61+fraccionThreshold, ...) representing the
/// "6 meses y 1 día" threshold from Art. 167 LSS 1973. The maximum age
/// (`maxAge`) only shows the integer (no fractional above it).
class PensionAgeDropdown {
  final int minAge;
  final int maxAge;
  final double fraccionThreshold;
  final String fraccionLabel;

  const PensionAgeDropdown({
    required this.minAge,
    required this.maxAge,
    required this.fraccionThreshold,
    required this.fraccionLabel,
  });

  factory PensionAgeDropdown.fromJson(Map<String, dynamic> json) {
    return PensionAgeDropdown(
      minAge: json['min_age'] as int? ?? 60,
      maxAge: json['max_age'] as int? ?? 65,
      fraccionThreshold:
          (json['fraccion_threshold'] as num?)?.toDouble() ?? 0.51,
      fraccionLabel: json['fraccion_label'] as String? ?? '6 meses y 1 día',
    );
  }

  /// Returns all available ages for the dropdown, e.g. [60, 60.51, 61, 61.51, ..., 65].
  List<double> get availableAges {
    final List<double> ages = [];
    for (int i = minAge; i < maxAge; i++) {
      ages.add(i.toDouble());
      ages.add(i + fraccionThreshold);
    }
    ages.add(maxAge.toDouble());
    return ages;
  }

  /// Snaps an arbitrary age onto the legal grid
  /// [minAge, minAge + fraccionThreshold, ..., maxAge], clamped to
  /// [minAge]..[maxAge], using the threshold-aware Art. 167 rounding rule:
  /// ages whose decimal part is >= [fraccionThreshold] round UP to the next
  /// integer year (e.g. 60.51 → 61), everything below rounds DOWN
  /// (e.g. 60.5 → 60). This mirrors `EdadRoundingRule.roundToInteger` and
  /// matches Excel's behavior for off-grid inputs.
  ///
  /// Coerces arbitrary AI/user values onto the grid so the dropdown never holds
  /// an off-grid value that would render blank (a `DropdownButton` has no
  /// matching item for it).
  double nearestAge(double age) {
    final list = availableAges;
    if (age <= list.first) return list.first;
    if (age >= list.last) return list.last;

    // Threshold-aware rounding matching the Art. 167 rule: >= fraccionThreshold
    // rounds up to the next integer year, below rounds down.
    final decimalPart = age - age.floor();
    final rounded = decimalPart >= (fraccionThreshold - 1e-10)
        ? age.ceil()
        : age.floor();

    // Clamp to integer years (no fractional value below minAge).
    if (rounded <= minAge) return minAge.toDouble();
    final upper = rounded.toDouble();
    // The lower half-step grid point below `upper` is `upper - 1 + fraccionThreshold`
    // (e.g. upper=61 → lower=60.51). Pick whichever is closer to `age`.
    final lower = upper - 1 + fraccionThreshold;
    return ((age - lower).abs() <= (upper - age).abs()) ? lower : upper;
  }
}

/// Configuration for the age-rounding rule used by `lookupEdadPorcentaje`.
///
/// Implements Art. 167 LSS 1973: "6 meses y un día o más se computará como un
/// año cumplido". The decimal part of the age is compared against
/// [sixMonthsThreshold] (with a small [sixMonthsEpsilon] tolerance for
/// floating-point precision). If the decimal is >= threshold, the age is
/// rounded UP to the next integer year.
class EdadRoundingRule {
  final double sixMonthsThreshold;
  final double sixMonthsEpsilon;

  /// Excel C25 formula: `IF(MOD(C24,1)>=27/52, 1, IF(MOD(C24,1)>=13/52, 0.5, 0))`
  /// The half-threshold for increment rounding (`>=27/52 ≈ 0.51923`).
  final double incrementHalfThreshold;

  /// The quarter-threshold for increment rounding (`>=13/52 = 0.25`).
  final double incrementQuarterThreshold;

  final String legalBasis;

  const EdadRoundingRule({
    required this.sixMonthsThreshold,
    required this.sixMonthsEpsilon,
    required this.incrementHalfThreshold,
    required this.incrementQuarterThreshold,
    required this.legalBasis,
  });

  factory EdadRoundingRule.fromJson(Map<String, dynamic> json) {
    final halfNum =
        json['increment_half_threshold_ratio'] as int? ?? 27;
    final halfDen =
        json['increment_half_threshold_denominator'] as int? ?? 52;
    final quarterNum =
        json['increment_quarter_threshold_ratio'] as int? ?? 13;
    final quarterDen =
        json['increment_quarter_threshold_denominator'] as int? ?? 52;
    return EdadRoundingRule(
      sixMonthsThreshold:
          (json['six_months_threshold'] as num?)?.toDouble() ?? 0.51,
      sixMonthsEpsilon:
          (json['six_months_epsilon'] as num?)?.toDouble() ?? 1e-10,
      incrementHalfThreshold: halfNum / halfDen,
      incrementQuarterThreshold: quarterNum / quarterDen,
      legalBasis: json['legal_basis'] as String? ?? '',
    );
  }

  /// Returns the integer age according to the "6 meses 1 día" rule.
  /// Example: 60.0 → 60, 60.5 → 60, 60.51 → 61, 61.5 → 61, 61.51 → 62.
  int roundToInteger(double edad) {
    final decimalPart = edad - edad.floor();
    return decimalPart >= (sixMonthsThreshold - sixMonthsEpsilon)
        ? edad.ceil()
        : edad.floor();
  }

  /// Rounds an increment count using Art. 167 LSS rules
  /// (matches Excel C25: `>=27/52 → +1, >=13/52 → +0.5, else → +0`).
  /// Returns the rounded value as a double (e.g. 31.0, 30.5, 30.0).
  /// Negative values are clamped to 0 (Excel clamps negative increments to 0).
  double roundIncrements(double rawIncrements) {
    // Excel clamps negative increments to 0
    if (rawIncrements < 0) {
      return 0.0;
    }
    
    final intPart = rawIncrements.floor();
    final fracPart = rawIncrements - intPart;
    if (fracPart >= incrementHalfThreshold) {
      return (intPart + 1).toDouble();
    } else if (fracPart >= incrementQuarterThreshold) {
      return intPart + 0.5;
    } else {
      return intPart.toDouble();
    }
  }
}

class ThemeConfig {
  final String primaryColor;
  final String accentColor;
  final String backgroundLight;
  final String cardBackground;
  final String textPrimary;
  final String textSecondary;
  final String errorColor;

  ThemeConfig({
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundLight,
    required this.cardBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.errorColor,
  });

  factory ThemeConfig.fromJson(Map<String, dynamic> json) {
    return ThemeConfig(
      primaryColor: json['primary_color'] as String? ?? '#004D40',
      accentColor: json['accent_color'] as String? ?? '#C5A059',
      backgroundLight: json['background_light'] as String? ?? '#F5F5F5',
      cardBackground: json['card_background'] as String? ?? '#FFFFFF',
      textPrimary: json['text_primary'] as String? ?? '#212121',
      textSecondary: json['text_secondary'] as String? ?? '#616161',
      errorColor: json['error_color'] as String? ?? '#D32F2F',
    );
  }
}

class UmasPercentage {
  final double umasMin;
  final double umasMax;
  final double percentage;

  UmasPercentage({
    required this.umasMin,
    required this.umasMax,
    required this.percentage,
  });

  factory UmasPercentage.fromJson(Map<String, dynamic> json) {
    return UmasPercentage(
      umasMin: (json['umas_min'] as num?)?.toDouble() ?? 0.0,
      umasMax: (json['umas_max'] as num?)?.toDouble() ?? double.infinity,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Entry in the credit table used by FORECAST.LINEAR for financing calculations.
/// Maps a credit [amount] to its corresponding [monthlyPayment].
class CreditTableEntry {
  final double amount;
  final double monthlyPayment;

  CreditTableEntry({required this.amount, required this.monthlyPayment});

  factory CreditTableEntry.fromJson(Map<String, dynamic> json) {
    return CreditTableEntry(
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      monthlyPayment: (json['monthly_payment'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Data from the "PENSIÓN ACTUAL" sheet — the user's current pension
/// calculation WITHOUT Modalidad 40, used as baseline for comparison.
class PensionActualData {
  final String nombre;
  final int edadPension;
  final String conyuge;
  final int hijosMenores;
  final int padresDependientes;
  final double edadFechaBaja;
  final int semanasCotizacion;
  final double salarioPromedio;
  final double aniosParaPensionarse;
  final double cuantiaBasicaPension;
  final double incrementosAnuales;
  final double asignacionesFamiliares;
  final double ayudaAsistencial;
  final double pensionMinimaAnio;
  final double totalPensionVejez;
  final double porcentajeEdad;
  final double totalPension;
  final String aplicaPensionMinima;
  final double importePensionAnual;
  final double importePensionMensual;
  final double aguinaldo;
  final double pensionMensualActualizada;

  PensionActualData({
    required this.nombre,
    required this.edadPension,
    required this.conyuge,
    required this.hijosMenores,
    required this.padresDependientes,
    required this.edadFechaBaja,
    required this.semanasCotizacion,
    required this.salarioPromedio,
    required this.aniosParaPensionarse,
    required this.cuantiaBasicaPension,
    required this.incrementosAnuales,
    required this.asignacionesFamiliares,
    required this.ayudaAsistencial,
    required this.pensionMinimaAnio,
    required this.totalPensionVejez,
    required this.porcentajeEdad,
    required this.totalPension,
    required this.aplicaPensionMinima,
    required this.importePensionAnual,
    required this.importePensionMensual,
    required this.aguinaldo,
    required this.pensionMensualActualizada,
  });

  factory PensionActualData.fromJson(Map<String, dynamic> json) {
    return PensionActualData(
      nombre: json['nombre'] as String? ?? '',
      edadPension: json['edad_pension'] as int? ?? 60,
      conyuge: json['conyuge'] as String? ?? 'NO',
      hijosMenores: json['hijos_menores'] as int? ?? 0,
      padresDependientes: json['padres_dependientes'] as int? ?? 0,
      edadFechaBaja: (json['edad_fecha_baja'] as num?)?.toDouble() ?? 0.0,
      semanasCotizacion: json['semanas_cotizacion'] as int? ?? 0,
      salarioPromedio: (json['salario_promedio'] as num?)?.toDouble() ?? 0.0,
      aniosParaPensionarse: (json['anios_para_pensionarse'] as num?)?.toDouble() ?? 0.0,
      cuantiaBasicaPension: (json['cuantia_basica_pension'] as num?)?.toDouble() ?? 0.0,
      incrementosAnuales: (json['incrementos_anuales'] as num?)?.toDouble() ?? 0.0,
      asignacionesFamiliares: (json['asignaciones_familiares'] as num?)?.toDouble() ?? 0.0,
      ayudaAsistencial: (json['ayuda_asistencial'] as num?)?.toDouble() ?? 0.0,
      pensionMinimaAnio: (json['pension_minima_anio'] as num?)?.toDouble() ?? 0.0,
      totalPensionVejez: (json['total_pension_vejez'] as num?)?.toDouble() ?? 0.0,
      porcentajeEdad: (json['porcentaje_edad'] as num?)?.toDouble() ?? 0.0,
      totalPension: (json['total_pension'] as num?)?.toDouble() ?? 0.0,
      aplicaPensionMinima: json['aplica_pension_minima'] as String? ?? 'NO',
      importePensionAnual: (json['importe_pension_anual'] as num?)?.toDouble() ?? 0.0,
      importePensionMensual: (json['importe_pension_mensual'] as num?)?.toDouble() ?? 0.0,
      aguinaldo: (json['aguinaldo'] as num?)?.toDouble() ?? 0.0,
      pensionMensualActualizada: (json['pension_mensual_actualizada'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class LegalNotes {
  final String pagoRetroactivo;
  final String factAsig;
  final String pensionMod40;
  final String costoMod40;
  final String inversion;
  final String financiamiento;

  LegalNotes({
    required this.pagoRetroactivo,
    required this.factAsig,
    required this.pensionMod40,
    required this.costoMod40,
    required this.inversion,
    required this.financiamiento,
  });

  factory LegalNotes.fromJson(Map<String, dynamic> json) {
    return LegalNotes(
      pagoRetroactivo:
          json['pago_retroactivo'] as String? ?? '',
      factAsig:
          json['fact_asig'] as String? ?? '',
      pensionMod40:
          json['pension_mod40'] as String? ?? '',
      costoMod40:
          json['costo_mod40'] as String? ?? '',
      inversion:
          json['inversion'] as String? ?? '',
      financiamiento:
          json['financiamiento'] as String? ?? '',
    );
  }
}

/// Test scenarios loaded from [assets/config/app_metadata.json] under the
/// "test_scenarios" key. Each scenario defines input parameters and expected
/// output values used by [test/validate_all_scenarios.dart] to validate the
/// calculation engine against known Excel outputs.
///
/// This eliminates hardcoded values in the test file and centralises scenario
/// data in the metadata configuration.
class TestScenarios {
  final TestScenario baseUser;
  final TestScenario seniorSolo;
  final TestScenario edadMediaPadres;
  final TestScenario jovenFamilia;

  const TestScenarios({
    required this.baseUser,
    required this.seniorSolo,
    required this.edadMediaPadres,
    required this.jovenFamilia,
  });

  /// Returns an empty [TestScenarios] with all scenarios initialised to
  /// [TestScenario.empty] so callers never deal with null.
  factory TestScenarios.empty() => TestScenarios(
        baseUser: TestScenario.empty(),
        seniorSolo: TestScenario.empty(),
        edadMediaPadres: TestScenario.empty(),
        jovenFamilia: TestScenario.empty(),
      );

  factory TestScenarios.fromJson(Map<String, dynamic> json) {
    return TestScenarios(
      baseUser: json['base_user'] != null
          ? TestScenario.fromJson(json['base_user'] as Map<String, dynamic>)
          : TestScenario.empty(),
      seniorSolo: json['senior_solo'] != null
          ? TestScenario.fromJson(json['senior_solo'] as Map<String, dynamic>)
          : TestScenario.empty(),
      edadMediaPadres: json['edad_media_padres'] != null
          ? TestScenario.fromJson(
              json['edad_media_padres'] as Map<String, dynamic>)
          : TestScenario.empty(),
      jovenFamilia: json['joven_familia'] != null
          ? TestScenario.fromJson(
              json['joven_familia'] as Map<String, dynamic>)
          : TestScenario.empty(),
    );
  }
}

/// A single test scenario with input parameters and expected output values.
///
/// Fields are nullable so that scenarios with different shapes (e.g. base_user
/// has no expected_* fields, joven_familia has no Mod40 fields) can share the
/// same class without requiring all fields to be present.
class TestScenario {
  // -- Description -----------------------------------------------------------
  final String? description;

  // -- Input parameters ------------------------------------------------------
  final double? salarioPromedio250Semanas;
  final double? salarioRegistradoMod40;
  final double? semanasEnMod40;
  final double? umaDiaria;
  final double? salarioMinimoDiario;
  final int? pensionYear;
  final double? semanasAntesMod40;
  final int? semanasCotizadasConMod40;
  final double? edadRetiro;
  final int? edadRetiroSinMod40;
  final int? numeroPadres;
  final double? salarioDiarioPromedio;
  final int? semanasCotizadas;
  final bool? tieneEsposa;
  final int? numeroHijos;

  // -- Expected output values ------------------------------------------------
  final double? expectedC30;
  final double? expectedC26;
  final double? expectedD16;
  final double? expectedSinM40;

  const TestScenario({
    this.description,
    this.salarioPromedio250Semanas,
    this.salarioRegistradoMod40,
    this.semanasEnMod40,
    this.umaDiaria,
    this.salarioMinimoDiario,
    this.pensionYear,
    this.semanasAntesMod40,
    this.semanasCotizadasConMod40,
    this.edadRetiro,
    this.edadRetiroSinMod40,
    this.numeroPadres,
    this.salarioDiarioPromedio,
    this.semanasCotizadas,
    this.tieneEsposa,
    this.numeroHijos,
    this.expectedC30,
    this.expectedC26,
    this.expectedD16,
    this.expectedSinM40,
  });

  /// Returns an empty [TestScenario] with all fields set to `null`.
  factory TestScenario.empty() => const TestScenario();

  factory TestScenario.fromJson(Map<String, dynamic> json) {
    return TestScenario(
      description: json['description'] as String?,
      salarioPromedio250Semanas:
          (json['salario_promedio_250_semanas'] as num?)?.toDouble(),
      salarioRegistradoMod40:
          (json['salario_registrado_mod40'] as num?)?.toDouble(),
      semanasEnMod40: (json['semanas_en_mod40'] as num?)?.toDouble(),
      umaDiaria: (json['uma_diaria'] as num?)?.toDouble(),
      salarioMinimoDiario:
          (json['salario_minimo_diario'] as num?)?.toDouble(),
      pensionYear: json['pension_year'] as int?,
      semanasAntesMod40: (json['semanas_antes_mod40'] as num?)?.toDouble(),
      semanasCotizadasConMod40: (json['semanas_cotizadas_con_mod40'] as num?)?.toInt(),
      edadRetiro: (json['edad_retiro'] as num?)?.toDouble(),
      edadRetiroSinMod40: (json['edad_retiro_sin_mod40'] as num?)?.toInt(),
      numeroPadres: json['numero_padres'] as int?,
      salarioDiarioPromedio:
          (json['salario_diario_promedio'] as num?)?.toDouble(),
      semanasCotizadas: json['semanas_cotizadas'] as int?,
      tieneEsposa: json['tiene_esposa'] as bool?,
      numeroHijos: json['numero_hijos'] as int?,
      expectedC30: (json['expected_c30'] as num?)?.toDouble(),
      expectedC26: (json['expected_c26'] as num?)?.toDouble(),
      expectedD16: (json['expected_d16'] as num?)?.toDouble(),
      expectedSinM40: (json['expected_sin_m40'] as num?)?.toDouble(),
    );
  }
}

/// Threshold entry for investment verdict based on recovery period (months).
///
/// Defined in [assets/config/app_metadata.json] under
/// "financial_rules.veredicto_thresholds".
class VeredictoThreshold {
  final int maxMeses;
  final String label;

  const VeredictoThreshold({
    required this.maxMeses,
    required this.label,
  });

  factory VeredictoThreshold.fromJson(Map<String, dynamic> json) {
    return VeredictoThreshold(
      maxMeses: json['max_meses'] as int? ?? 0,
      label: json['label'] as String? ?? '',
    );
  }
}
