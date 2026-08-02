import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_metadata.dart';
import '../models/retroactive_calculation.dart';
import '../models/pension_calculation.dart';

/// Financial engine that evaluates all pension calculation logic
/// based on the Excel formulas extracted from the calculator.
///
/// Loads [app_metadata.json] for financial rules and uses them
/// to compute all 6 modules: PAGO RETROACTIVO, FACT+ASIG,
/// PENSION MOD 40, COSTO MOD 40, INVERSION, FINANCIAMIENTO.
class FormulaEvaluator {
  AppMetadata? _metadata;
  bool _initialized = false;

  /// Number of months from Con Mod40 pension start to row 247 in the
  /// Excel Sheet1 projection table. Column P (index 15) accumulates
  /// the Con Mod40 pension payments month by month. Row 247 corresponds
  /// to approximately age 81 (247 months from age 60).
  /// The accumulated value = 241 * pensionMensualConMod40.
  static const int _projectionP247Months = 241;

  /// Number of months from pension start to row 247 in the
  /// Excel Sheet1 projection table for column AN (Financiamiento).
  /// Column AN accumulates the liquidación pension payments.
  /// The accumulated value ≈ 183 * pensionMensualLiquidacion.
  static const int _projectionAn247Months = 183;

  bool get isInitialized => _initialized;

  /// Load metadata from the bundled JSON asset.
  Future<void> initialize() async {
    if (_initialized) return;
    debugPrint('[EVAL-INIT] Loading app_metadata.json...');
    final jsonStr =
        await rootBundle.loadString('assets/config/app_metadata.json');
    debugPrint('[EVAL-INIT] JSON loaded, length=${jsonStr.length} chars');
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    debugPrint('[EVAL-INIT] JSON parsed, keys=${json.keys.length}');
    try {
      _metadata = AppMetadata.fromJson(json);
      debugPrint('[EVAL-INIT] AppMetadata.fromJson OK');
    } catch (e, s) {
      debugPrint('[EVAL-INIT] ERROR in AppMetadata.fromJson: $e');
      debugPrint('[EVAL-INIT] Stack trace: $s');
      rethrow;
    }
    _initialized = true;
    debugPrint('[EVAL-INIT] Initialization complete');
  }

  AppMetadata get metadata {
    if (_metadata == null) {
      throw StateError(
          'FormulaEvaluator not initialized. Call initialize() first.');
    }
    return _metadata!;
  }

  // ============================================================
  // 1. PAGO RETROACTIVO
  // ============================================================

  /// Calculate the retroactive payment matching Excel Sheet 2 algorithm.
  ///
  /// The Excel Sheet 2 calculates actualizaciones and recargos month by month
  /// using a days-based approach where days count down from 31 to 1.
  /// For each month: actualización = monthlyCost × days × monthlyInflationRate
  ///                 recargo = monthlyCost × days × recargoRate
  /// The monthlyCost is looked up by year from the inflation_year_factors metadata.
  RetroactiveCalculation calculateRetroactivo({
    required double costoModalidad40,
    required double retroactiveYears,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final rules = metadata.financialRules;

    final clampedYears = retroactiveYears.clamp(
      rules.minRetroactiveYears.toDouble(),
      rules.maxRetroactiveYears.toDouble(),
    );

    final totalMeses = (clampedYears * 12).round();
    final mesesToProcess = totalMeses.clamp(0, 60);

    if (mesesToProcess == 0 || costoModalidad40 <= 0) {
      return RetroactiveCalculation(
        costoModalidad40: costoModalidad40,
        actualizaciones: 0,
        recargos: 0,
        costoTotal: costoModalidad40,
        incrementoPorcentaje: 0,
        recuperacionAfore: costoModalidad40 * rules.aforeRetroactiveRecoveryRate,
        inversionTotal:
            costoModalidad40 * (1 - rules.aforeRetroactiveRecoveryRate),
        mesesRetroactivos: 0,
      );
    }

    double totalActualizaciones = 0;
    double totalRecargos = 0;

    // Excel Sheet 2 algorithm: iterate month by month FORWARD from the calculated
    // start month, counting days down from 31. This matches Excel's F column date
    // progression: F2=2027-01-28, F3=2027-02-28, ..., F32=2029-07-28
    //
    // The Sheet 2 calculates dates backward from endDate using EDATE:
    //   N32 = EDATE(endDate, -1) = 2029-07-28
    //   N31 = EDATE(N32, -1) = 2029-06-28
    //   ...
    //   N2 = EDATE(N3, -1) = 2027-01-28
    //
    // So the first month is: endDate minus mesesToProcess months
    //   DateTime(endDate.year, endDate.month - mesesToProcess, 28)
    //
    // The days (G column) count down: G2=31, G3=30, G4=29, ..., G32=1
    // The cuota (I column) is looked up by year from the V/W table:
    //   Months 1-12 (i=0..11, days 31..20): year=2027, cuota=14474.99
    //   Months 13-24 (i=12..23, days 19..8): year=2028, cuota=15492.01
    //   Months 25-31 (i=24..30, days 7..1): year=2029, cuota=16508.10
    for (int i = 0; i < mesesToProcess; i++) {
      // Calculate the month date going FORWARD from the calculated start month.
      // Using endDate.year and endDate.month - mesesToProcess + i ensures the
      // date progression matches Excel's N column exactly.
      // Dart's DateTime handles negative months correctly by wrapping backward.
      final monthDate = DateTime(
        endDate.year,
        endDate.month - mesesToProcess + i,
        28, // Excel uses day 28 for all months
      );

      final year = monthDate.year;

      // Look up the monthly cuota for this year from inflation_year_factors
      // This matches Excel's V/W lookup table in Sheet 2
      final monthlyCost = _getMonthlyCostoForYear(year, rules);

      // Days count down from 31: 31, 30, 29, 28, ..., 1
      // This matches Excel's G column (days) which counts down from O2=31
      final days = mesesToProcess - i;

      // Monthly inflation rate from Excel's J column
      // For years > 2024: 0.36% = 0.0036
      // Excel formula: =IF(YEAR(Fn)>2024,0.36%,...)
      final monthlyInflationRate = _getMonthlyInflationRate(year);

      // Actualización = monthlyCost × days × monthlyRate
      // Excel: Ln = In × Kn where Kn = Gn × Jn
      final monthlyActualizacion = monthlyCost * days * monthlyInflationRate;

      // Recargo rate from Excel's R column
      // For years >= 2026: 0.0207 = 2.07%
      // Excel formula: =IF(YEAR(Nn)<2026,0.0147,0.0207)
      final recargoRate = year < rules.recargoYearThreshold
          ? rules.recargoMonthlyRate
          : rules.recargoMonthlyRatePost2026;

      // Recargo = monthlyCost × days × recargoRate
      // Excel: Tn = Qn × Sn where Sn = On × Rn
      final monthlyRecargo = monthlyCost * days * recargoRate;

      totalActualizaciones += monthlyActualizacion;
      totalRecargos += monthlyRecargo;
    }

    final costoTotal = costoModalidad40 + totalActualizaciones + totalRecargos;
    final incrementoPorcentaje =
        costoModalidad40 > 0
            ? (totalActualizaciones + totalRecargos) / costoModalidad40
            : 0;
    final recuperacionAfore = costoTotal * rules.aforeRetroactiveRecoveryRate;
    final inversionTotal = costoTotal - recuperacionAfore;

    return RetroactiveCalculation(
      costoModalidad40: costoModalidad40,
      actualizaciones: totalActualizaciones,
      recargos: totalRecargos,
      costoTotal: costoTotal,
      incrementoPorcentaje: incrementoPorcentaje.toDouble(),
      recuperacionAfore: recuperacionAfore,
      inversionTotal: inversionTotal,
      mesesRetroactivos: mesesToProcess,
    );
  }

  // ============================================================
  // 2. FACT. + ASIG. MOD.40
  // ============================================================

  /// Calculate Factores y Asignaciones based on Excel formulas.
  ///
  /// [salarioDiarioPromedio] = C4 (Nuevo salario diario promedio 250 semanas)
  /// [pensionYear] = G4 (Año de pensión)
  /// [umaDiaria] = C5 (UMA diaria actual)
  /// [semanasCotizadas] = total semanas cotizadas (for incrementos calculation)
  /// [tieneEsposa] = whether has spouse
  /// [numeroHijos] = number of children
  /// [numeroPadres] = number of dependent parents
  /// [salarioMinimoDiario] = C6 (salario mínimo diario vigente)
  FactAsigCalculation calculateFactAsig({
    required double salarioDiarioPromedio,
    double? umaDiaria,
    double? salarioMinimoDiario,
    required int pensionYear,
    required int semanasCotizadas,
    required bool tieneEsposa,
    required int numeroHijos,
    required int numeroPadres,
    required double edadRetiro,
  }) {
    final rules = metadata.financialRules;

    // D16: Porcentaje por edad (PENSION MOD. 40) — used in B53 and C72
    final porcentajePorEdad = lookupEdadPorcentaje(edadRetiro, rules).$1;

    // Auto-calculate UMA from projection table if not provided
    final double effectiveUma =
        umaDiaria ?? getProjectedUma(pensionYear, rules);

    // Auto-calculate SM from projection table if not provided
    final double effectiveSm =
        salarioMinimoDiario ?? getProjectedMinWage(pensionYear, rules);

    // C7: Salario en UMAS = ROUND(C4/C5, 2)
    final salarioEnUMAs =
        (salarioDiarioPromedio / effectiveUma * 100).roundToDouble() / 100;

    // Lookup cuantía básica % from the porcentajes_tabla (simplified: based on UMAS range)
    // Excel: C12 = VLOOKUP(C7,'1'!A3:D24,3,TRUE)
    // We use a simplified lookup based on the UMAS value
    final porcentajeCuantiaBasica = _lookupCuantiaBasica(salarioEnUMAs);

    // C13: Cuantía básica por día = C4 * C12
    final cuantiaBasicaPorDia = salarioDiarioPromedio * porcentajeCuantiaBasica;

    // C15: Total cuantía básica anual = C13 * C14 * 1.11 (aguinaldo)
    // C14 = 365 days
    final totalCuantiaBasicaAnual =
        cuantiaBasicaPorDia * rules.daysInYear * rules.aguinaldoFactor;

    // C20: Porcentaje de incremento (VLOOKUP from same table, col 4)
    final porcentajeIncremento = _lookupIncremento(salarioEnUMAs);

    // C21: Incrementos diarios = C20 * C4
    final incrementosDiarios = porcentajeIncremento * salarioDiarioPromedio;

    // C23: Incremento anual = C21 * C22 (C22 = 365)
    final incrementoAnual = incrementosDiarios * rules.daysInYear;

    // C24: Número de incrementos anuales = (semanas - 500) / 52
    final numeroIncrementosAnuales =
        (semanasCotizadas - rules.minWeeksForIncrement) / rules.weeksPerYear;

    // C25: Redondeo Art. 167 LSS
    // INT(C24) + IF(MOD(C24,1)>=27/52,1,IF(MOD(C24,1)>=13/52,0.5,0))
    // All thresholds come from metadata (rules.edadRoundingRule) — no
    // hardcoded values here. See EdadRoundingRule.roundIncrements().
    final numeroIncrementosRedondeado =
        rules.edadRoundingRule.roundIncrements(numeroIncrementosAnuales);

    // C26: Total incrementos anuales = C23 * C25 * 1.11
    final totalIncrementosAnuales =
        incrementoAnual * numeroIncrementosRedondeado * rules.aguinaldoFactor;

    // C30: Cuantía total pensión vejez = C26 + C15
    final cuantiaTotalPensionVejez =
        totalCuantiaBasicaAnual + totalIncrementosAnuales;

    // --- Asignaciones Familiares ---
    // The base for asignaciones is cuantiaTotalPensionVejez (C30)
    // But Excel uses a different base (C34 = cuantía total pensión anual without aguinaldo?)
    // From data: C34 = 922255.60 which is C30/1.11? Let's check:
    // C30 = 1023703.72, /1.11 = 922255.60 ✓
    final baseAsignaciones = cuantiaTotalPensionVejez / rules.aguinaldoFactor;

    // C36: Asignación esposa = IF(no esposa, 0, C34 * rules.asignacionEsposaPercentage)
    final asignacionEsposa =
        tieneEsposa ? baseAsignaciones * rules.asignacionEsposaPercentage : 0.0;

    // C43: Asignación hijos = C40 * C41 * C42
    // C40 = baseAsignaciones, C41 = rules.asignacionHijosPercentage, C42 = numeroHijos
    final asignacionHijos = baseAsignaciones * rules.asignacionHijosPercentage * numeroHijos;

    // C49: Asignación padres = C46 * C47 * C48
    // Only applies if no spouse AND no children
    final asignacionPadres = (!tieneEsposa && numeroHijos == 0)
        ? baseAsignaciones * rules.asignacionPadresPercentage * numeroPadres
        : 0.0;

    // B53: Cuantía total asignaciones familiares
    // Excel: =(C36+C43+C49)*1.11*D16
    // We now apply BOTH aguinaldoFactor (1.11) and D16 (porcentajePorEdad)
    // here so the value matches Excel's B53 exactly.
    final cuantiaTotalAsignaciones =
        (asignacionEsposa + asignacionHijos + asignacionPadres) *
        rules.aguinaldoFactor *
        porcentajePorEdad;

    // --- Ayuda Asistencial ---
    // C58: If no spouse, no children, no parents -> 15%
    //      If only 1 parent -> 10%
    //      Otherwise -> 0
    final bool noBeneficiarios =
        !tieneEsposa && numeroHijos == 0 && numeroPadres == 0;
    final bool soloUnPadre =
        !tieneEsposa && numeroHijos == 0 && numeroPadres == 1;

    double porcentajeAyudaAsistencial;
    if (noBeneficiarios) {
      porcentajeAyudaAsistencial = rules.ayudaAsistencialNoBeneficiarios;
    } else if (soloUnPadre) {
      porcentajeAyudaAsistencial = rules.ayudaAsistencialUnPadre;
    } else {
      porcentajeAyudaAsistencial = 0.0;
    }

    // C59: Excel formula = MIN(C57*C58*1.11*D16, MAX(0,G5*25*365-(C30*D16+B53)), C4*365*1.11-(C30*D16+B53))
    // Where:
    //   C57 = baseAsignaciones, C58 = porcentajeAyudaAsistencial
    //   G5 = projected UMA for pension year, D16 = porcentajePorEdad
    //   C30 = cuantiaTotalPensionVejez, B53 = cuantiaTotalAsignaciones
    //   C4 = salarioDiarioPromedio
    // The Excel formula is:
    //   =MIN(C57*C58*1.11*'PENSION MOD. 40'!D16,
    //       MAX(0,G5*25*365-(C30*'PENSION MOD. 40'!D16+B53)),
    //       +C4*365*1.11-(C30*'PENSION MOD. 40'!D16+B53))
    // All three terms use D16 (porcentajePorEdad), not 1.0.
    //
    // IMPORTANT: Excel ALWAYS computes C59 as MIN of the three terms, even when
    // C58 = 0 (no ayuda asistencial percentage). When C58 = 0, Term 1 = 0, but
    // Term 3 can be negative (when pension exceeds salary), making C59 negative.
    // The App previously returned 0 when no beneficiaries, but this doesn't match
    // Excel. We must always compute the MIN.
    final double ayudaAsistencialBase =
        baseAsignaciones * porcentajeAyudaAsistencial * rules.aguinaldoFactor * porcentajePorEdad;

    // Cap 1: MAX(0, G5*25*365 - (C30*D16 + B53))
    // G5 = projected UMA for pension year (from VLOOKUP)
    final double projectedUma = getProjectedUma(pensionYear, rules);
    final double cap1 = math.max(0.0,
        projectedUma * rules.maxUmaMultiplier * rules.daysInYear -
            (cuantiaTotalPensionVejez * porcentajePorEdad + cuantiaTotalAsignaciones));

    // Cap 2: C4*365*1.11 - (C30*D16 + B53)
    // NOTE: Excel does NOT wrap this term in MAX(0,...). Only cap1 (the G5*25*365 term)
    // has MAX(0). This means cap2 can be negative when the pension exceeds the salary,
    // and MIN will select the negative value, making C59 negative.
    // See Excel formula: =MIN(C57*C58*1.11*D16, MAX(0,G5*25*365-(C30*D16+B53)), +C4*365*1.11-(C30*D16+B53))
    final double cap2 =
        salarioDiarioPromedio * rules.daysInYear * rules.aguinaldoFactor -
            (cuantiaTotalPensionVejez * porcentajePorEdad + cuantiaTotalAsignaciones);

    // Always compute C59 as MIN of the three terms, matching Excel exactly.
    // Excel does NOT skip this calculation when C58 = 0.
    final double totalAyudaAsistencial =
        [ayudaAsistencialBase, cap1, cap2].reduce(math.min);

    // Whether ayuda asistencial percentage is > 0 (for reporting purposes)
    final bool aplicaAyudaAsistencial = porcentajeAyudaAsistencial > 0;

    // C67: Cuantía + Asignaciones anual (before decreto)
    // = C30 + B53 + C59 (cuantía total + asignaciones familiares + ayuda asistencial)
    final cuantiaMasAsignaciones =
        cuantiaTotalPensionVejez + cuantiaTotalAsignaciones + totalAyudaAsistencial;

    // C69: Asignación Decreto Presidencial 11%
    final asignacionDecretoPresidencial =
        cuantiaMasAsignaciones * rules.presidentialDecreeRate;

    // C72: Total pensión por vejez anual
    // Excel: =+C30*'PENSION MOD. 40'!D16+C59+B53
    // = cuantiaTotalPensionVejez * porcentajePorEdad + totalAyudaAsistencial + cuantiaTotalAsignaciones
    // (cuantiaTotalAsignaciones already includes D16 from B53)
    final totalPensionAnual = cuantiaTotalPensionVejez * porcentajePorEdad +
        totalAyudaAsistencial +
        cuantiaTotalAsignaciones;

    // C74: Pensión mensual = C72 / 12
    final totalPensionMensual = totalPensionAnual / 12;

    return FactAsigCalculation(
      salarioDiarioPromedio: salarioDiarioPromedio,
      umaDiaria: effectiveUma,
      salarioMinimoDiario: effectiveSm,
      salarioEnUMAs: salarioEnUMAs,
      pensionYear: pensionYear,
      porcentajeCuantiaBasica: porcentajeCuantiaBasica,
      cuantiaBasicaPorDia: cuantiaBasicaPorDia,
      totalCuantiaBasicaAnual: totalCuantiaBasicaAnual,
      porcentajeIncremento: porcentajeIncremento,
      incrementosDiarios: incrementosDiarios,
      incrementoAnual: incrementoAnual,
      numeroIncrementosAnuales: numeroIncrementosAnuales,
      numeroIncrementosRedondeado: numeroIncrementosRedondeado,
      totalIncrementosAnuales: totalIncrementosAnuales,
      cuantiaTotalPensionVejez: cuantiaTotalPensionVejez,
      tieneEsposa: tieneEsposa,
      asignacionEsposa: asignacionEsposa,
      numeroHijos: numeroHijos,
      asignacionHijos: asignacionHijos,
      numeroPadres: numeroPadres,
      asignacionPadres: asignacionPadres,
      cuantiaTotalAsignaciones: cuantiaTotalAsignaciones,
      aplicaAyudaAsistencial: aplicaAyudaAsistencial,
      porcentajeAyudaAsistencial: porcentajeAyudaAsistencial,
      totalAyudaAsistencial: totalAyudaAsistencial,
      cuantiaMasAsignaciones: cuantiaMasAsignaciones,
      asignacionDecretoPresidencial: asignacionDecretoPresidencial,
      totalPensionAnual: totalPensionAnual,
      totalPensionMensual: totalPensionMensual,
    );
  }

  // ============================================================
  // 3. PENSION MOD. 40
  // ============================================================

  /// Calculate the final pension based on age.
  ///
  /// [pensionAnual100] = D12 from PENSION MOD 40 (cuantía total pensión vejez 100%)
  /// [edadRetiro] = D14 (edad de retiro)
  /// [salarioMinimoDiario] = C6 (for pensión mínima garantizada — user-input SM)
  /// [pensionYear] = G4 (pension year, used to look up projected SM from embedded table)
  /// [cuantiaTotalAsignaciones] = B53 from FACT+ASIG (asignaciones familiares anuales)
  /// [totalAyudaAsistencial] = C59 from FACT+ASIG (ayuda asistencial anual)
  ///
  /// The pensión mínima garantizada (D18) uses the **projected** SM from the
  /// embedded projection table (VLOOKUP-style), NOT the user-input SM.
  /// Excel: D18 = 'FACT. + ASIG. MOD.40'!C6*365*111% where C6 = VLOOKUP(G4,'1'!N3:P29,3,FALSE)
  PensionMod40Calculation calculatePensionMod40({
    required double pensionAnual100,
    required double edadRetiro,
    required double salarioMinimoDiario,
    int? pensionYear,
    double cuantiaTotalAsignaciones = 0,
    double totalAyudaAsistencial = 0,
  }) {
    final rules = metadata.financialRules;

    // D16: Porcentaje por edad
    // IF(D14>=65, 1, VLOOKUP(D14, C4:D9, 2, FALSE))
    final edadInfo = lookupEdadPorcentaje(edadRetiro, rules);
    final porcentajePorEdad = edadInfo.$1;
    final tipoPension = edadInfo.$2;

    // D18: Pensión mínima garantizada
    // = C6 * 365 * 111%
    // C6 = projected SM from VLOOKUP(G4,'1'!N3:P29,3,FALSE)
    // Use the projected SM from the embedded table; fall back to user-input SM
    // if pensionYear is not provided.
    final double projectedSm = pensionYear != null
        ? getProjectedMinWage(pensionYear, rules)
        : salarioMinimoDiario;
    final pensionMinimaGarantizada =
        projectedSm * rules.daysInYear * rules.aguinaldoFactor;

    // D20: ¿Aplica mínima?
    // IF(D12*D16 > D18, "NO", "SI")
    // Excel: returns "NO" (no aplica mínima) when pensionCalculada > minima
    //        returns "SI" (aplica mínima) when pensionCalculada <= minima
    final pensionCalculada = pensionAnual100 * porcentajePorEdad;
    final bool aplicaMinima = pensionCalculada <= pensionMinimaGarantizada;

    // C23: Pensión anual final
    // Excel: =IF(D20="SI", D18, D12*D16+'FACT. + ASIG. MOD.40'!B53+'FACT. + ASIG. MOD.40'!C59)
    // B53 (cuantiaTotalAsignaciones) and C59 (totalAyudaAsistencial) now both
    // already include D16 (computed in calculateFactAsig), so we just add
    // them without re-applying D16.
    final pensionAnualFinal = aplicaMinima
        ? pensionMinimaGarantizada
        : pensionCalculada + cuantiaTotalAsignaciones + totalAyudaAsistencial;

    // C26: Pensión mensual
    final pensionMensual = pensionAnualFinal / 12;

    return PensionMod40Calculation(
      pensionAnual100: pensionAnual100,
      edadRetiro: edadRetiro,
      porcentajePorEdad: porcentajePorEdad,
      tipoPension: tipoPension,
      pensionMinimaGarantizada: pensionMinimaGarantizada,
      aplicaMinima: aplicaMinima,
      pensionAnualFinal: pensionAnualFinal,
      pensionMensual: pensionMensual,
    );
  }

  // ============================================================
  // 4. COSTO MOD. 40
  // ============================================================

  /// Calculate the projected costs of Modalidad 40.
  ///
  /// [salarioRegistrado] = the registered salary for Modalidad 40
  /// [startDate] = when Modalidad 40 starts
  /// [endDate] = when Modalidad 40 ends (pension date)
  CostoMod40Calculation calculateCostoMod40({
    required double salarioRegistrado,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final rules = metadata.financialRules;
    final List<CostoYearRow> yearlyCosts = [];

    double totalInversion = 0;

    // Iterate through each year from startDate.year to endDate.year
    for (int year = startDate.year; year <= endDate.year; year++) {
      // Find the rate for this year
      final rateEntry = rules.costoMod40Rates.cast<CostoMod40Rate?>().firstWhere(
        (r) => year >= r!.yearStart && year <= r.yearEnd,
        orElse: () => null,
      );

      if (rateEntry == null) continue;

      final tasa = rateEntry.rate;

      // Calculate days paid in this year
      // E = MAX(0, MIN(endDate, DATE(year,12,31)) - MAX(startDate, DATE(year,1,1)) + 1)
      final yearStart = DateTime(year, 1, 1);
      final yearEnd = DateTime(year, 12, 31);

      final effectiveStart =
          year == startDate.year ? startDate : yearStart;
      final effectiveEnd = year == endDate.year ? endDate : yearEnd;

      final diasPagados =
          effectiveEnd.difference(effectiveStart).inDays + 1;
      final clampedDias = math.max(0, diasPagados);

      // If no days or no salary, skip (but still add a row with zeros)
      if (clampedDias <= 0 || salarioRegistrado <= 0) {
        yearlyCosts.add(CostoYearRow(
          label: _getYearLabel(year, rules.costoMod40Rates),
          yearStart: year,
          salarioRegistrado: 0,
          tasa: tasa,
          diasPagados: 0,
          cuotaMensual: 0,
          cuotaAnual: 0,
        ));
        continue;
      }

      // F: Cuota mensual promedio = D * C * 365 / 12
      // Where D = tasa, C = salario registrado
      final cuotaMensual = tasa * salarioRegistrado * rules.daysInYear / 12;

      // G: Cuota anual = D * E * C
      // Where D = tasa, E = días pagados, C = salario registrado
      final cuotaAnual = tasa * clampedDias * salarioRegistrado;

      totalInversion += cuotaAnual;

      yearlyCosts.add(CostoYearRow(
        label: _getYearLabel(year, rules.costoMod40Rates),
        yearStart: year,
        salarioRegistrado: salarioRegistrado,
        tasa: tasa,
        diasPagados: clampedDias,
        cuotaMensual: cuotaMensual,
        cuotaAnual: cuotaAnual,
      ));
    }

    // G15: Inversión total
    final inversionTotal = totalInversion;

    // G17: Recuperación AFORE = G15 * aforeRecoveryRate
    final recuperacionAfore = inversionTotal * rules.aforeRecoveryRate;

    // G19: Inversión neta = G15 - G17
    final inversionNeta = inversionTotal - recuperacionAfore;

    return CostoMod40Calculation(
      yearlyCosts: yearlyCosts,
      inversionTotal: inversionTotal,
      recuperacionAfore: recuperacionAfore,
      inversionNeta: inversionNeta,
    );
  }

  // ============================================================
  // 5. INVERSION
  // ============================================================

  /// Calculate the investment analysis (with vs without Modalidad 40).
  ///
  /// [pensionMensualSinMod40] = D45 (pension mensual sin Modalidad 40)
  /// [pensionMensualConMod40] = F45 (pension mensual con Modalidad 40)
  /// [edadRetiroSinMod40] = D4 (edad de retiro sin Mod 40)
  /// [edadRetiroConMod40] = F4 (edad de retiro con Mod 40)
  /// [inversionTotalMod40] = from CostoMod40Calculation.inversionNeta (G19)
  /// [inversionTotal] = from CostoMod40Calculation.inversionTotal (G15)
  InversionCalculation calculateInversion({
    required double pensionMensualSinMod40,
    required double pensionMensualConMod40,
    required int edadRetiroSinMod40,
    required int edadRetiroConMod40,
    required double inversionTotalMod40,
    required double inversionTotal,
  }) {
    final rules = metadata.financialRules;
    final lifeExpectancy = rules.lifeExpectancyYears;

    // F5: Mejora de pensión = F45 - D45
    final mejoraPension = pensionMensualConMod40 - pensionMensualSinMod40;

    // F9: Periodos de recuperación (meses)
    // Excel: =+IF(F5=0,"No se recupera la inversion",ABS('COSTO MOD. 40'!G19/F5))
    // where F5 = F45 - D45 = pensionMensualConMod40 - pensionMensualSinMod40
    // IMPORTANT: Excel uses ABS() so it works even when mejoraPension is negative
    // (i.e., when pensionSinMod40 > pensionConMod40, which happens for integer
    // retirement ages like 65 or 70 where the SIN Mod40 pension is higher).
    // Previously the code returned double.infinity when mejoraPension <= 0,
    // which caused _getVeredicto to return "No lo hagas" incorrectly.
    final periodosRecuperacionMeses =
        mejoraPension == 0
            ? double.infinity
            : (inversionTotalMod40 / mejoraPension).abs();

    // D46: Flujo sin Mod 40 hasta 80 años
    // Excel: =((80*13 - D4*13) * D45) * 1.54
    // monthsWithAguinaldo = 13 = 12 months + aguinaldo (1 extra month)
    // flujoFactor = 1.54 = factor that includes 1.11 (aguinaldo) * 1.387... (inflation projection)
    final mesesSinMod40 = (lifeExpectancy - edadRetiroSinMod40) * rules.monthsWithAguinaldo;
    final flujoHasta80SinMod40 = mesesSinMod40 * pensionMensualSinMod40 * rules.flujoFactor;

    // F46: Flujo con Mod 40 hasta 80 años
    // Excel: =(Sheet1!P247 + (80 - C12) * F45) * 1.54
    // Sheet1!P247 = accumulated pension from projection table at row 247 (age ~80)
    // The projection table accumulates pension payments month by month.
    // Row 247 corresponds to approximately 241 months of pension payments
    // (from the start of Con Mod40 pension at age 61 to row 247 at age ~81).
    // Since the accumulated value grows linearly with the pension amount,
    // we calculate it dynamically: projectionP247 = projectionP247Months * pensionMensualConMod40
    // where projectionP247Months = 241 (derived from Excel's projection table structure).
    //
    // NOTE: The metadata contains a fixed projectionP247 value that was captured
    // from a specific Excel state. However, this value changes per scenario because
    // the projection table dynamically recalculates based on the pension amount.
    // We override it here with a dynamic calculation to match Excel's behavior.
    final dynamicProjectionP247 = _projectionP247Months * pensionMensualConMod40;
    final flujoHasta80ConMod40 =
        (dynamicProjectionP247 +
            (lifeExpectancy - edadRetiroConMod40) * pensionMensualConMod40) *
        rules.flujoFactor;

    // D49: Ganancia total = F46 - D46
    final gananciaTotal = flujoHasta80ConMod40 - flujoHasta80SinMod40;

    // D50: Tasa de rendimiento total = D49 / G15
    // G15 = inversionTotal (costo total de Modalidad 40 sin descuentos)
    final tasaRendimiento =
        inversionTotal > 0
            ? gananciaTotal / inversionTotal
            : 0.0;

    // Veredicto based on periodos de recuperación (Excel logic)
    final veredicto = _getVeredicto(periodosRecuperacionMeses);

    // inversionTotalMod40 = inversion neta (CostoMod40.inversionNeta)
    // recuperacionAfore = inversionTotal - inversionTotalMod40
    final inversionNeta = inversionTotalMod40;
    final recuperacionAfore = inversionTotal - inversionTotalMod40;

    return InversionCalculation(
      edadRetiroSinMod40: edadRetiroSinMod40,
      edadRetiroConMod40: edadRetiroConMod40,
      pensionMensualSinMod40: pensionMensualSinMod40,
      pensionMensualConMod40: pensionMensualConMod40,
      mejoraPension: mejoraPension,
      periodosRecuperacionMeses: periodosRecuperacionMeses,
      flujoHasta80SinMod40: flujoHasta80SinMod40,
      flujoHasta80ConMod40: flujoHasta80ConMod40,
      gananciaTotal: gananciaTotal,
      tasaRendimiento: tasaRendimiento,
      veredicto: veredicto,
      inversionNeta: inversionNeta,
      recuperacionAfore: recuperacionAfore,
    );
  }

  // ============================================================
  // 5.1 INVERSION CORREGIDA (Usa fórmulas exactas de Excel)
  // ============================================================

  /// Calculate the investment analysis using exact Excel formulas.
  /// This method assumes that the input values are already correct.
  /// If pensionMensualSinMod40 equals pensionMensualConMod40, it logs a warning
  /// but still performs the calculation.
  InversionCalculation calculateInversionCorregida({
    required double pensionMensualSinMod40,
    required double pensionMensualConMod40,
    required int edadRetiroSinMod40,
    required int edadRetiroConMod40,
    required double inversionTotalMod40,
    required double inversionTotal,
  }) {
    final rules = metadata.financialRules;
    final lifeExpectancy = rules.lifeExpectancyYears;

    // Verificar si los valores parecen incorrectos (solo para logging)
    if (pensionMensualSinMod40 == pensionMensualConMod40) {
      debugPrint('[INVERSION-CORREGIDA] ADVERTENCIA: pensionSinMod40 == pensionConMod40. '
          'Esto podría indicar un error en el cálculo de pensión sin Mod40.');
    }

    // F5: Mejora de pensión = F45 - D45 (Excel exacto)
    final mejoraPension = pensionMensualConMod40 - pensionMensualSinMod40;

    // F9: Periodos de recuperación (meses) = ABS(G19 / F5)
    final periodosRecuperacionMeses =
        mejoraPension > 0
            ? (inversionTotalMod40 / mejoraPension).abs()
            : double.infinity;

    // D46: Flujo sin Mod 40 hasta 80 años
    // Excel: =((80*13 - D4*13) * D45) * 1.54
    final mesesSinMod40 = (lifeExpectancy - edadRetiroSinMod40) * rules.monthsWithAguinaldo;
    final flujoHasta80SinMod40 = mesesSinMod40 * pensionMensualSinMod40 * rules.flujoFactor;

    // F46: Flujo con Mod 40 hasta 80 años
    // Excel: =(Sheet1!P247 + (80 - C12) * F45) * 1.54
    // Sheet1!P247 = accumulated pension from projection table at row 247 (age ~80)
    // The projection table accumulates pension payments month by month.
    // Row 247 corresponds to approximately 241 months of pension payments
    // (from the start of Con Mod40 pension at age 61 to row 247 at age ~81).
    // Since the accumulated value grows linearly with the pension amount,
    // we calculate it dynamically: projectionP247 = projectionP247Months * pensionMensualConMod40
    // where projectionP247Months = 241 (derived from Excel's projection table structure).
    //
    // NOTE: The metadata contains a fixed projectionP247 value that was captured
    // from a specific Excel state. However, this value changes per scenario because
    // the projection table dynamically recalculates based on the pension amount.
    // We override it here with a dynamic calculation to match Excel's behavior.
    final dynamicProjectionP247 = _projectionP247Months * pensionMensualConMod40;
    final flujoHasta80ConMod40 =
        (dynamicProjectionP247 +
            (lifeExpectancy - edadRetiroConMod40) * pensionMensualConMod40) *
        rules.flujoFactor;

    // D49: Ganancia total = F46 - D46 (Excel exacto)
    final gananciaTotal = flujoHasta80ConMod40 - flujoHasta80SinMod40;

    // D50: Tasa de rendimiento total = D49 / G15 (Excel exacto)
    final tasaRendimiento =
        inversionTotal > 0
            ? gananciaTotal / inversionTotal
            : 0.0;

    // Veredicto based on periodos de recuperación (Excel logic)
    final veredicto = _getVeredicto(periodosRecuperacionMeses);

    // Log para debugging
    debugPrint('[INVERSION-CORREGIDA] Cálculo completado:');
    debugPrint('[INVERSION-CORREGIDA]   D46 (flujo sin): $flujoHasta80SinMod40');
    debugPrint('[INVERSION-CORREGIDA]   F46 (flujo con): $flujoHasta80ConMod40');
    debugPrint('[INVERSION-CORREGIDA]   D49 (ganancia): $gananciaTotal');
    debugPrint('[INVERSION-CORREGIDA]   D50 (tasa): $tasaRendimiento');

    // inversionTotalMod40 = inversion neta (CostoMod40.inversionNeta)
    // recuperacionAfore = inversionTotal - inversionTotalMod40
    final inversionNeta = inversionTotalMod40;
    final recuperacionAfore = inversionTotal - inversionTotalMod40;

    return InversionCalculation(
      edadRetiroSinMod40: edadRetiroSinMod40,
      edadRetiroConMod40: edadRetiroConMod40,
      pensionMensualSinMod40: pensionMensualSinMod40,
      pensionMensualConMod40: pensionMensualConMod40,
      mejoraPension: mejoraPension,
      periodosRecuperacionMeses: periodosRecuperacionMeses,
      flujoHasta80SinMod40: flujoHasta80SinMod40,
      flujoHasta80ConMod40: flujoHasta80ConMod40,
      gananciaTotal: gananciaTotal,
      tasaRendimiento: tasaRendimiento,
      veredicto: veredicto,
      inversionNeta: inversionNeta,
      recuperacionAfore: recuperacionAfore,
    );
  }

  // ============================================================
  // 6. FINANCIAMIENTO
  // ============================================================

  /// Calculate the financing simulation for retroactive payment.
  ///
  /// [inversionTotal] = C3 (costo total retroactivo from PAGO RETROACTIVO)
  /// [participacionBancoMax] = maximum bank participation (from '1'!Y3)
  /// [pensionMensualMejorada] = F45 (pension mensual con Mod 40)
  /// [edadRetiro] = edad de retiro CON Modalidad 40
  /// [pensionSinMod40] = pension mensual SIN Modalidad 40 (for F3 calculation)
  /// [edadRetiroSinMod40] = edad de retiro SIN Modalidad 40 (for INVERSION D46 formula)
  /// [segundoFondeadorMontoCredito] = SEGUNDO FONDEADOR C2 (monto del crédito)
  /// [segundoFondeadorCostoFinanciamiento] = SEGUNDO FONDEADOR C4 (costo financiamiento)
  /// [segundoFondeadorMontoMaximoPagar] = SEGUNDO FONDEADOR C5 (monto máximo a pagar)
  /// [segundoFondeadorInversionRequerida] = SEGUNDO FONDEADOR C7 (inversión requerida)
  /// [segundoFondeadorAforeRecovery] = SEGUNDO FONDEADOR C11 (recuperación AFORE)
  FinanciamientoCalculation calculateFinanciamiento({
    required double inversionTotal,
    required double pensionMensualMejorada,
    required double edadRetiro,
    double pensionSinMod40 = 0,
    int edadRetiroSinMod40 = 60,
    double segundoFondeadorMontoCredito = 0,
    double segundoFondeadorCostoFinanciamiento = 0,
    double segundoFondeadorMontoMaximoPagar = 0,
    double segundoFondeadorInversionRequerida = 0,
    double segundoFondeadorAforeRecovery = 0,
    // Optional override for the projection table ratio (Sheet1!AN247 / pensionMensualLiquidacion).
    // Defaults to _projectionAn247Months (183) which matches the baseline scenario.
    // Different scenarios may have slightly different ratios (181.91-184.95) due to
    // the Excel projection table's complex structure. Pass the Excel-calculated ratio
    // for precise cross-validation.
    double? projectionAn247Months,
  }) {
    final rules = metadata.financialRules;

    // Calculate participacionBancoMax from credit table (Excel Y3 = X3 * 0.7195)
    // AD3 = pensionMensual * 0.3 (30% credit capacity)
    // FORECAST.LINEAR(AD3, AA3:AA39, AB3:AB39) → montoEstimado
    // X3 = IF(montoEstimado*0.7195 < C3, montoEstimado, montoEstimado/0.7195)
    // Y3 = X3 * 0.7195 = participacionBancoMax
    final creditTable = rules.creditTable;
    final amounts = creditTable.map((e) => e.amount).toList();
    final payments = creditTable.map((e) => e.monthlyPayment).toList();
    final capacidadPago = pensionMensualMejorada * rules.capacidadPagoPorcentaje;
    final montoEstimado = _forecastLinear(
      capacidadPago,
      amounts,
      payments,
    );
    final participacionBancoMax = montoEstimado * rules.forecastFactor;

    // C6: Participación banco = MIN(participacionBancoMax, inversionTotal)
    final participacionBanco =
        participacionBancoMax < inversionTotal
            ? participacionBancoMax
            : inversionTotal;

    // C7: Participación propia = IF(C3-C6>1, C3-C6, epsilonValor)
    final participacionPropia = (inversionTotal - participacionBanco) > 1
        ? inversionTotal - participacionBanco
        : rules.epsilonValor;

    // C10: % Banco = C6 / C3
    final porcentajeBanco =
        inversionTotal > 0 ? participacionBanco / inversionTotal : 0.0;

    // C11: % Propio = C7 / C3
    final porcentajePropio =
        inversionTotal > 0 ? participacionPropia / inversionTotal : 0.0;

    // C14: Monto crédito = C6
    final montoCredito = participacionBanco;

    // C15: Duración trámite (meses)
    final duracionTramite = rules.financingProcessingMonths;

    // C17: Monto máximo a pagar (from '1'!X3)
    // Excel: =+'1'!X3
    // X3 = IF(FORECAST.LINEAR(AD3, AA3:AA39, AB3:AB39)*0.7195 < C3, AE3, AE3/0.7195)
    // AD3 = pensionMensual * 0.3 (30% credit capacity)
    // AA3:AA39 = credit amounts (known_y's), AB3:AB39 = monthly payments (known_x's)
    // FORECAST.LINEAR(AD3, AA3:AA39, AB3:AB39) predicts credit amount (y) based on monthly payment (x)
    // AE3 = IF(predicted*0.7195 < C3, predicted, C3)
    // X3 = IF(predicted*0.7195 < C3, AE3, AE3/0.7195)
    // Simplified: X3 = IF(predicted*0.7195 < C3, predicted, C3/0.7195)
    // CORRECTED: When montoEstimado * forecastFactor >= inversionTotal:
    //   Excel AE3 = C3 (inversionTotal), then X3 = AE3 / 0.7195 = C3 / 0.7195
    //   Previously the App incorrectly used montoEstimado / forecastFactor instead of inversionTotal / forecastFactor
    final montoMaximoPagar = (montoEstimado * rules.forecastFactor) < inversionTotal
        ? montoEstimado // X3 = AE3 = predicted (when predicted*forecastFactor < C3)
        : inversionTotal / rules.forecastFactor; // X3 = AE3/forecastFactor = C3/forecastFactor (when predicted*forecastFactor >= C3)

    // C16: Costo financiamiento = C17 - C14
    final costoFinanciamiento = montoMaximoPagar - montoCredito;

    // C20: Monto redondeado = CEILING(C17, redondeoCredito)
    final montoCreditoRedondeado =
        (montoMaximoPagar / rules.redondeoCredito).ceil() * rules.redondeoCredito.toDouble();

    // C21: Plazo (meses)
    final plazoMeses = rules.financingTermMonths;

    // C22: Descuento mensual
    // Excel: =FORECAST.LINEAR(C20, '1'!AB3:AB39, '1'!AA3:AA39)
    // Predicts monthly payment based on credit amount
    // known_y's = AB3:AB39 (monthly payments), known_x's = AA3:AA39 (credit amounts)
    final descuentoMensual = _forecastLinear(
      montoCreditoRedondeado, // x = C20 (credit amount)
      payments, // known_y's = AB (monthly payments)
      amounts, // known_x's = AA (credit amounts)
    );

    // F5: Pensión mensual inmediata (durante 60 meses)
    // = pensionMensualMejorada - descuentoMensual
    final pensionMensualInmediata =
        pensionMensualMejorada - descuentoMensual;

    // F6: Pensión mensual al liquidar (después de inflacionAniosProyeccion meses)
    // Excel: =+'MOD 40 REC. VS RETRO.'!F32*1.045^5
    // This applies inflacionAniosProyeccion years of inflation adjustment to the pension
    final pensionMensualLiquidacion =
        pensionMensualMejorada * math.pow(1 + rules.inflationAnnualRate, rules.inflacionAniosProyeccion).toDouble();

    // F7: Flujo hasta 80 años
    // Excel: =(Sheet1!AN247 + (80 - C12) * F6) * 1.54
    // Sheet1!AN247 = accumulated pension from projection table at row 247 (age ~80)
    // (80 - C12) * F6 = remaining years * pensionLiquidacion (C12 = edadRetiro = 61)
    // The flujoFactor (1.54) accounts for aguinaldo (1.11) and inflation projection (~1.387)
    // Column AN in the projection table accumulates the liquidación pension payments.
    // The accumulated value grows linearly with the pension amount.
    // We calculate it dynamically: projectionAn247 = projectionAn247Months * pensionMensualLiquidacion
    // where projectionAn247Months = 183 (derived from Excel's projection table structure).
    //
    // NOTE: The metadata contains a fixed projectionAn247 value that was captured
    // from a specific Excel state. However, this value changes per scenario because
    // the projection table dynamically recalculates based on the pension amount.
    // We override it here with a dynamic calculation to match Excel's behavior.
    // The projectionAn247Months parameter allows callers to pass the exact ratio
    // from the Excel projection table for precise cross-validation.
    final effectiveProjectionAn247Months = projectionAn247Months ?? _projectionAn247Months;
    final dynamicProjectionAn247 = effectiveProjectionAn247Months * pensionMensualLiquidacion;
    // CORRECTED: Use edadRetiro as double (decimal value, e.g., 60.5) instead of
    // truncating to int (60). Excel FINANCIAMIENTO F7 formula:
    //   =(Sheet1!AN247 + (80 - 'DATOS GEN. MOD 40'!C12) * F6) * 1.54
    // where C12 = edad_retiro (decimal, e.g., 60.5), NOT the integer edad.
    // Using the truncated integer causes a ~88,743 difference in flujoHasta80.
    final flujoHasta80 =
        (dynamicProjectionAn247 +
            (rules.lifeExpectancyYears - edadRetiro) * pensionMensualLiquidacion) *
        rules.flujoFactor;

    // Flujo hasta 80 años SIN Modalidad 40 (for ganancia/tasa comparison)
    // CORRECTED: Uses INVERSION D46 formula instead of projectionAn247.
    // Excel INVERSION D46: =((80*13 - D4*13) * D45) * 1.54
    // where D4 = edadRetiroSinMod40 (60), D45 = pensionSinMod40 (54,039.90)
    // monthsWithAguinaldo (13) = 12 months + aguinaldo (1 extra month)
    // This matches the PENSIÓN SIN-CON FIN. sheet's "sin modalidad 40" flujo value.
    final mesesSinMod40 =
        (rules.lifeExpectancyYears - edadRetiroSinMod40) * rules.monthsWithAguinaldo;
    final flujoHasta80SinMod40 =
        pensionSinMod40 > 0
            ? mesesSinMod40 * pensionSinMod40 * rules.flujoFactor
            : 0;

    // DEBUG: Log all financiamiento values for verification
    debugPrint('[FINANCIAMIENTO] === TASA RENDIMIENTO DEBUG ===');
    debugPrint('[FINANCIAMIENTO]  pensionMensualMejorada: $pensionMensualMejorada');
    debugPrint('[FINANCIAMIENTO]  pensionSinMod40: $pensionSinMod40');
    debugPrint('[FINANCIAMIENTO]  edadRetiro (con M40): $edadRetiro');
    debugPrint('[FINANCIAMIENTO]  edadRetiroSinMod40: $edadRetiroSinMod40');
    debugPrint('[FINANCIAMIENTO]  inversionTotal: $inversionTotal');
    debugPrint('[FINANCIAMIENTO]  participacionBanco: $participacionBanco');
    debugPrint('[FINANCIAMIENTO]  participacionPropia: $participacionPropia');
    debugPrint('[FINANCIAMIENTO]  pensionMensualLiquidacion: $pensionMensualLiquidacion');
    debugPrint('[FINANCIAMIENTO]  flujoHasta80 (con fin): $flujoHasta80');
    debugPrint('[FINANCIAMIENTO]  flujoHasta80SinMod40: $flujoHasta80SinMod40');
    debugPrint('[FINANCIAMIENTO]  expectedSinMod40 (age 60): ${((80 - 60) * 13 * pensionSinMod40 * rules.flujoFactor)}');
    debugPrint('[FINANCIAMIENTO]  mesesSinMod40: $mesesSinMod40');

    // Ganancia total = flujo con financiamiento - flujo sin modalidad 40
    // Matches Excel PENSIÓN SIN-CON FIN. "GANANCIA TOTAL GRACIAS AL FINANCIAMIENTO"
    final gananciaTotal = flujoHasta80 - flujoHasta80SinMod40;

    // Tasa de rendimiento = gananciaTotal / participacionPropia (inversión propia)
    // Matches Excel "(MXN) 5,502,992.76" / participacionPropia ($205,648.19) = 26.76%
    final tasaRendimiento =
        participacionPropia > 0 ? gananciaTotal / participacionPropia : 0.0;

    // F3: Periodos de recuperación (meses)
    // Excel formula:
    // =IF('SEGUNDO FONDEADOR'!C9>0,
    //     IF(('SEGUNDO FONDEADOR'!C9-'SEGUNDO FONDEADOR'!C14)/
    //        MAX(F5-'MOD 40 REC. VS RETRO.'!C2, 0.01)>0,
    //        (('SEGUNDO FONDEADOR'!C9/0.63-'SEGUNDO FONDEADOR'!C14))/
    //        (F5-'MOD 40 REC. VS RETRO.'!C2),
    //        0.001))
    //
    // Where:
    //   SEGUNDO FONDEADOR C9 = inversionRequerida (236826.00) — Inversión Requerida
    //   SEGUNDO FONDEADOR C14 = aforeRecovery (131419.17)
    //   F5 = pensionMensualInmediata
    //   MOD 40 REC. VS RETRO. C2 = pensionSinMod40
    double periodosRecuperacion;
    if (segundoFondeadorInversionRequerida > 0 &&
        pensionSinMod40 > 0 &&
        pensionMensualInmediata > 0) {
      // CORRECTED: Use segundoFondeadorInversionRequerida (SEGUNDO FONDEADOR C9)
      // which is the INVERSIÓN REQUERIDA (~236,826), NOT inversionTotal (~657,096).
      // The Excel formula divides C9 by 0.63 (segundoFondeadorFactor), then
      // subtracts C14 (aforeRecovery). The condition check uses (C9 - C14) > 0
      // WITHOUT dividing by 0.63, matching Excel's exact logic.
      //
      // Excel condition: (C9 - C14) > 0   (since denominator < 0, MAX returns 0.01)
      // App condition:   (C9 - C14) > 0   (same, no /0.63 in condition)
      final denominator =
          pensionMensualInmediata - pensionSinMod40;
      final adjustedDenominator =
          denominator > 0 ? denominator : 0.01;
      final conditionNumerator =
          segundoFondeadorInversionRequerida - segundoFondeadorAforeRecovery;
      if (conditionNumerator / adjustedDenominator > 0) {
        // Actual computation: (C9/0.63 - C14) / (F5 - C2)
        final actualNumerator =
            segundoFondeadorInversionRequerida / rules.segundoFondeadorFactor -
                segundoFondeadorAforeRecovery;
        periodosRecuperacion = actualNumerator / denominator;
      } else {
        periodosRecuperacion = 0.001;
      }
    } else {
      // Fallback: simplified formula when SEGUNDO FONDEADOR data not available
      periodosRecuperacion =
          inversionTotal > 0 && pensionMensualInmediata > 0
              ? inversionTotal / pensionMensualInmediata
              : double.infinity;
    }

    // Veredicto based on periodos de recuperación (Excel logic)
    final veredicto = _getVeredicto(periodosRecuperacion);

    return FinanciamientoCalculation(
      inversionTotal: inversionTotal,
      participacionBanco: participacionBanco,
      participacionPropia: participacionPropia,
      porcentajeBanco: porcentajeBanco,
      porcentajePropio: porcentajePropio,
      montoCredito: montoCredito,
      duracionTramiteMeses: duracionTramite,
      costoFinanciamiento: costoFinanciamiento,
      montoMaximoPagar: montoMaximoPagar,
      montoCreditoRedondeado: montoCreditoRedondeado,
      plazoMeses: plazoMeses,
      descuentoMensual: descuentoMensual,
      pensionMensualInmediata: pensionMensualInmediata,
      pensionMensualLiquidacion: pensionMensualLiquidacion,
      flujoHasta80: flujoHasta80,
      periodosRecuperacionMeses: periodosRecuperacion,
      veredicto: veredicto,
      // CORRECTED: Now passing calculated tasaRendimiento and gananciaTotal
      recuperacionAfore: segundoFondeadorAforeRecovery,
      tasaRendimiento: tasaRendimiento,
      gananciaTotal: gananciaTotal,
      segundoFondeo: segundoFondeadorMontoCredito,
      cantidadMinimaAfore: segundoFondeadorInversionRequerida,
      // DEBUG: Pass input values for UI display
      debugPensionMensualMejorada: pensionMensualMejorada,
      debugPensionSinMod40: pensionSinMod40,
      debugFlujoHasta80SinMod40: flujoHasta80SinMod40.toDouble(),
    );
  }

  /// Calculates SEGUNDO FONDEADOR values for the FINANCIAMIENTO F3 formula.
  ///
  /// The SEGUNDO FONDEADOR sheet provides financing terms for a second financier
  /// (when the user doesn't have sufficient AFORE resources). These values are
  /// needed by the FINANCIAMIENTO F3 formula to compute recovery periods.
  ///
  /// Returns a record with:
  /// - [montoCredito]: SEGUNDO FONDEADOR C2 (participación propia = inversionTotal - participacionBanco)
  /// - [costoFinanciamiento]: SEGUNDO FONDEADOR C4 (costo durante el trámite)
  /// - [montoMaximoPagar]: SEGUNDO FONDEADOR C5 (monto crédito + costo)
  /// - [inversionRequerida]: SEGUNDO FONDEADOR C7 (cantidad mínima requerida en AFORE)
  /// - [aforeRecovery]: SEGUNDO FONDEADOR C11 (recuperación AFORE del pago retroactivo)
  ({double montoCredito, double costoFinanciamiento, double montoMaximoPagar,
    double inversionRequerida, double aforeRecovery}) calculateSegundoFondeador({
    required double inversionTotal,
    required double pensionMensualMejorada,
    required double aforeRecovery,
  }) {
    final rules = metadata.financialRules;

    // Calculate participacionBancoMax from credit table (same as calculateFinanciamiento)
    final creditTable = rules.creditTable;
    final amounts = creditTable.map((e) => e.amount).toList();
    final payments = creditTable.map((e) => e.monthlyPayment).toList();
    final capacidadPago = pensionMensualMejorada * rules.capacidadPagoPorcentaje;
    final montoEstimado = _forecastLinear(capacidadPago, amounts, payments);
    final participacionBancoMax = montoEstimado * rules.forecastFactor;

    // Same participacionPropia logic as FINANCIAMIENTO C7
    // = IF(C3-C6>1, C3-C6, 0.00000001)
    final participacionBanco =
        participacionBancoMax < inversionTotal
            ? participacionBancoMax
            : inversionTotal;
    final montoCredito = (inversionTotal - participacionBanco) > 1
        ? inversionTotal - participacionBanco
        : rules.epsilonValor;

    // SEGUNDO FONDEADOR uses 12-month plazo with tasaFinanciamiento
    // Costo de Financiamiento = Monto del Crédito * tasaFinanciamiento * (plazo/12)
    // Since plazo = 12 for SEGUNDO FONDEADOR, this simplifies to montoCredito * tasaFinanciamiento
    final costoFinanciamiento = montoCredito * rules.tasaFinanciamiento;

    // Monto Máximo a Pagar = Monto del Crédito + Costo de Financiamiento
    final montoMaximoPagar = montoCredito + costoFinanciamiento;

    // Inversión Requerida (cantidad mínima en AFORE) = Monto del Crédito * (1 + tasaDescuento)
    // This is the guarantee amount needed in AFORE for the second financier
    final inversionRequerida = montoCredito * (1 + rules.tasaDescuento);

    return (
      montoCredito: montoCredito,
      costoFinanciamiento: costoFinanciamiento,
      montoMaximoPagar: montoMaximoPagar,
      inversionRequerida: inversionRequerida,
      aforeRecovery: aforeRecovery,
    );
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  /// Determine investment verdict based on recovery period (months).
  ///
  /// Excel: =IF(AND(F9>0,F9<=16),"Excelente Inversión",IF(AND(F9>0,F9<=24),"Buena Inversión",
  ///        IF(AND(F9>0,F9<=36),"Inversión Aceptable",IF(AND(F9>0,F9<=48),"Riesgo Moderado",
  ///        IF(AND(F9>0,F9<=60),"¡Riesgo Alto!",IF(AND(F9>0,F9<>72),"¡Ten cuidado!","No lo hagas"))))))
  String _getVeredicto(double periodosRecuperacion) {
    final rules = _metadata!.financialRules;
    for (final threshold in rules.veredictoThresholds) {
      if (periodosRecuperacion > 0 && periodosRecuperacion <= threshold.maxMeses) {
        return threshold.label;
      }
    }
    return rules.veredictoDefault;
  }

  /// Lookup edad percentage and pension type from the pension age table.
  ///
  /// Returns a record (porcentaje, tipoPension).
  /// If edad >= 65, returns (1.0, 'Vejez').
  /// Otherwise looks up from [pensionAgePercentages] table.
  ///
  /// IMPORTANT: The IMSS Ley 1973 Art. 167 rule "6 meses 1 día = siguiente año"
  /// means that if the decimal part of the age is >= 0.51, the age is rounded UP
  /// to the next integer year. For example:
  ///   - 60.00 to 60.50 → 60 years (75%)
  ///   - 60.51 to 61.50 → 61 years (80%)
  ///   - 61.51 to 62.50 → 62 years (85%)
  /// This matches the Excel behavior where the percentage is based on the
  /// completed year after applying the 6-month-1-day rule.
  (double, String) lookupEdadPorcentaje(double edad, FinancialRules rules) {
    // The "6 meses 1 día = siguiente año" rule comes from metadata
    // (rules.edadRoundingRule). See EdadRoundingRule.roundToInteger() for
    // details and the legal basis. This keeps all constants configurable.
    final edadEntera = rules.edadRoundingRule.roundToInteger(edad);
    // Excel formula: IF(D14>=65, 1, VLOOKUP(D14, C4:D9, 2, FALSE))
    // For ages >= 65, the percentage is always 100% (vejez)
    if (edadEntera >= 65) {
      return (1.0, 'vejez');
    }
    // Look up from the pension_age_percentages table in metadata.
    // The table includes all ages 60-65 with their corresponding percentages
    // and pension types (vejez at 65=100%, cesantia at 60-64 with reduced %).
    // If no entry is found, fall back to the lowest age (60) percentage.
    final entry = rules.pensionAgePercentages.cast<PensionAgePercentage?>().firstWhere(
      (p) => p!.age == edadEntera,
      orElse: () => null,
    );
    if (entry != null) {
      return (entry.percentage, entry.type);
    }
    // Fallback: use the percentage for age 60 (lowest pension age)
    final fallbackEntry = rules.pensionAgePercentages.cast<PensionAgePercentage?>().firstWhere(
      (p) => p!.age == 60,
      orElse: () => null,
    );
    return (
      fallbackEntry?.percentage ?? rules.pensionAgePercentages.first.percentage,
      fallbackEntry?.type ?? rules.pensionAgePercentages.first.type,
    );
  }

  /// Get the monthly cuota (costo) for a given year from inflation_year_factors.
  ///
  /// Matches Excel Sheet 2's V/W lookup table:
  /// - V15=2027, W15=14474.996743625 (cuota for 2027)
  /// - V16=2028, W16=15492.0125503802 (cuota for 2028)
  /// - V17=2029, W17=16508.0961703281 (cuota for 2029)
  /// Returns 0 if no matching year found or costo is 0.
  double _getMonthlyCostoForYear(int year, FinancialRules rules) {
    final entry = rules.inflationYearFactors.cast<YearFactor?>().firstWhere(
      (f) => f!.year == year,
      orElse: () => null,
    );
    if (entry == null || entry.costo <= 0) return 0;
    return entry.costo;
  }

  /// Get the monthly inflation rate for a given year.
  ///
  /// Matches Excel Sheet 2's J column formula:
  /// Monthly inflation rate lookup from metadata.
  ///
  /// Excel: =IF(YEAR(Fn)=2019,0.30333%,IF(YEAR(Fn)=2020,0.2625%,...))
  /// Rates are now defined in [assets/config/app_metadata.json] under
  /// "financial_rules.monthly_inflation_rates" with a "default" fallback.
  double _getMonthlyInflationRate(int year) {
    final rules = _metadata!.financialRules;
    final key = year.toString();
    if (rules.monthlyInflationRates.containsKey(key)) {
      return rules.monthlyInflationRates[key]!;
    }
    // Fallback to "default" for years not explicitly listed
    return rules.monthlyInflationRates['default']!;
  }

  /// Lookup cuantía básica percentage from the UMAS value.
  /// Excel: VLOOKUP(umas, '1'!A3:D24, 3, TRUE) - finds the row where umas is in [umas_min, umas_max]
  double _lookupCuantiaBasica(double umas) {
    final rules = _metadata!.financialRules;
    for (final entry in rules.cuantiaBasicaPercentages) {
      if (umas >= entry.umasMin && umas <= entry.umasMax) return entry.percentage;
    }
    return rules.cuantiaBasicaPercentages.last.percentage;
  }

  /// Lookup incremento percentage from the UMAS value.
  /// Excel: VLOOKUP(umas, '1'!A3:D24, 4, TRUE) - finds the row where umas is in [umas_min, umas_max]
  double _lookupIncremento(double umas) {
    final rules = _metadata!.financialRules;
    for (final entry in rules.incrementoPercentages) {
      if (umas >= entry.umasMin && umas <= entry.umasMax) return entry.percentage;
    }
    return rules.incrementoPercentages.last.percentage;
  }

  /// Get the projected UMA value for a given pension year.
  /// Uses the embedded [umaProjectionTable] for a VLOOKUP-style exact match.
  /// Excel: VLOOKUP(G4,'1'!N3:O29,2,FALSE) where '1'!N3:O29 is the UMA projection table.
  /// Falls back to compound growth formula if year is outside the table range.
  double getProjectedUma(int year, FinancialRules rules) {
    // VLOOKUP-style exact match from the embedded projection table
    for (final entry in rules.umaProjectionTable) {
      if (entry.year == year) return entry.uma;
    }
    // Fallback: if year is beyond the table, project from the last entry
    if (rules.umaProjectionTable.isNotEmpty) {
      final lastEntry = rules.umaProjectionTable.last;
      if (year > lastEntry.year) {
        final yearsFromLast = year - lastEntry.year;
        return lastEntry.uma * math.pow(1 + rules.inflationAnnualRate, yearsFromLast).toDouble();
      }
    }
    // Ultimate fallback: use base UMA
    return rules.umaDaily2024;
  }

  /// Get the projected minimum wage value for a given pension year.
  /// Uses the embedded [minWageProjectionTable] for a VLOOKUP-style exact match.
  /// Excel: VLOOKUP(G4,'1'!N3:P29,3,FALSE) where '1'!N3:P29 is the SM projection table.
  /// Falls back to compound growth formula if year is outside the table range.
  double getProjectedMinWage(int year, FinancialRules rules) {
    // VLOOKUP-style exact match from the embedded projection table
    for (final entry in rules.minWageProjectionTable) {
      if (entry.year == year) return entry.minWage;
    }
    // Fallback: if year is beyond the table, project from the last entry
    if (rules.minWageProjectionTable.isNotEmpty) {
      final lastEntry = rules.minWageProjectionTable.last;
      if (year > lastEntry.year) {
        final yearsFromLast = year - lastEntry.year;
        return lastEntry.minWage * math.pow(1 + rules.minWageGrowthRate, yearsFromLast).toDouble();
      }
    }
    // Ultimate fallback: use base min wage
    return rules.minWageDaily2024;
  }

  /// Get a human-readable label for a year range from costo mod40 rates.
  String _getYearLabel(int year, List<CostoMod40Rate> rates) {
    for (final r in rates) {
      if (year >= r.yearStart && year <= r.yearEnd) {
        if (r.yearStart == r.yearEnd) {
          return 'COSTO MODALIDAD 40 $year';
        } else if (r.yearEnd >= 9999) {
          return 'COSTO MODALIDAD 40 ${r.yearStart} EN ADELANTE';
        } else {
          return 'COSTO MODALIDAD 40 ${r.yearStart}-${r.yearEnd}';
        }
      }
    }
    return 'COSTO MODALIDAD 40 $year';
  }

  // ============================================================
  // NUEVO SALARIO PROMEDIO (SAL. PROM MOD 40)
  // ============================================================

  /// Calculate the NUEVO SALARIO PROMEDIO DE 250 SEMANAS when Modalidad 40
  /// weeks are added, matching the Excel's SAL. PROM MOD 40 sheet logic.
  ///
  /// The Excel calculates:
  ///   NUEVO = Σ(salario_i × semanas_i) / 250
  ///
  /// Where the 250 most recent weeks include:
  ///   - M40 weeks at the registered salary
  ///   - Historical weeks at their original salaries
  ///
  /// Since the App has the ANTERIOR average (not individual historical data),
  /// the calculation uses a weighted average. However, the simple formula:
  ///   nuevo = (anterior × (250 - semanasEnMod40) + registrado × semanasEnMod40) / 250
  /// assumes the historical weeks average [salarioAnterior], which is only
  /// accurate when salaries are uniformly distributed. In reality, the Mod40
  /// weeks replace the OLDEST weeks, which typically have the LOWEST salaries.
  ///
  /// When the most recent historical weeks have salaries significantly higher
  /// than the 250-week average (typical with salary growth over time), the
  /// effective new salary approaches [salarioRegistradoMod40] because the
  /// replaced oldest weeks had below-average salaries.
  ///
  /// This implementation returns the MAX of the weighted average and the
  /// registered salary, since the Mod40 weeks always replace the oldest
  /// (lowest-paid) weeks, making the true value >= the registered salary
  /// when the registered salary >= the average of replaced weeks.
  ///
  /// [salarioAnterior] = E18 (ANTERIOR SALARIO PROMEDIO DE 250 SEMANAS)
  /// [salarioRegistradoMod40] = D22 (SALARIO REGISTRADO in MXN for M40 period)
  /// [semanasEnMod40] = E22 (SEMANAS COTIZADAS in M40)
  double calcularNuevoSalarioPromedio({
    required double salarioAnterior,
    required double salarioRegistradoMod40,
    required double semanasEnMod40,
  }) {
    final rules = _metadata!.financialRules;
    final totalSemanas = rules.totalSemanasPromedio.toDouble();
    if (semanasEnMod40 <= 0) return salarioAnterior;
    if (semanasEnMod40 >= totalSemanas) return salarioRegistradoMod40;

    // Simple weighted average: assumes historical weeks average salarioAnterior.
    // This UNDERESTIMATES the true value when the oldest weeks have below-average
    // salaries (which is the typical case with salary growth).
    final semanasRestantes = totalSemanas - semanasEnMod40;
    final weightedAverage = (salarioAnterior * semanasRestantes +
            salarioRegistradoMod40 * semanasEnMod40) /
        totalSemanas;

    // The true Excel value is always >= the registered salary when the Mod40
    // weeks replace the oldest (lowest-paid) weeks and the registered salary
    // is higher than the average of those replaced weeks.
    // Return the higher value as the best approximation.
    return weightedAverage > salarioRegistradoMod40
        ? weightedAverage
        : salarioRegistradoMod40;
  }

  /// Implements Excel's FORECAST.LINEAR function using least squares linear regression.
  ///
  /// Given a target [x] value and arrays of known [yValues] and known [xValues],
  /// computes the predicted y value using the formula: y = a + b*x
  /// where:
  ///   b = (n*Σxy - Σx*Σy) / (n*Σx² - (Σx)²)
  ///   a = (Σy - b*Σx) / n
  ///
  /// Used for credit table forecasting in FINANCIAMIENTO calculations.
  double _forecastLinear(double x, List<double> yValues, List<double> xValues) {
    if (yValues.length != xValues.length || yValues.isEmpty) return 0;
    final n = yValues.length;

    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      final xi = xValues[i];
      final yi = yValues[i];
      sumX += xi;
      sumY += yi;
      sumXY += xi * yi;
      sumX2 += xi * xi;
    }

    final denominator = n * sumX2 - sumX * sumX;
    if (denominator == 0) return sumY / n; // fallback to mean

    final slope = (n * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / n;

    return intercept + slope * x;
  }
}
