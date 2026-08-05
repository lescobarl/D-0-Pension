import '../../core/engine/formula_evaluator.dart';
import '../../core/models/pension_calculation.dart';
import '../../core/models/retroactive_calculation.dart';
import '../../core/utils/error_handler.dart';
import 'retroactive_inputs.dart';

/// Ejecuta la cadena de recálculo del pipeline de Pensión CON Modalidad 40
/// (Ley 73).
///
/// Responsabilidad única: **calcular los resultados derivados** a partir del
/// estado de entrada ([RetroactiveInputs]) usando el motor
/// ([FormulaEvaluator]). No conoce persistencia, UI ni notificaciones.
///
/// Orden de la cadena:
///   1. [recalcularFactAsig]        → factAsigCalculation (base de pensión)
///   2. [recalcularFactAsigSinMod40] → factAsigSinMod40Calculation
///   3. [recalcularPensionMod40]     → pensionMod40Calculation (fuerza factAsig)
///   4. [recalcularCostoMod40]       → costoMod40Calculation (costo M40)
///   5. [recalcularRetroactivo]      → retroactiveCalculation (retroactivo)
///   6. [recalcularInversion]        → inversionCalculation (M40 vs no-M40)
///   7. [recalcularFinanciamiento]   → financiamientoCalculation (financiamiento)
class RetroactiveCalculator {
  final FormulaEvaluator evaluator;
  final RetroactiveInputs inputs;

  // --- RESULTADOS DERIVADOS ---
  FactAsigCalculation? factAsigCalculation;
  FactAsigCalculation? factAsigSinMod40Calculation;
  PensionMod40Calculation? pensionMod40Calculation;
  CostoMod40Calculation? costoMod40Calculation;
  RetroactiveCalculation? retroactiveCalculation;
  InversionCalculation? inversionCalculation;
  FinanciamientoCalculation? financiamientoCalculation;

  RetroactiveCalculator({
    required this.evaluator,
    required this.inputs,
  });

  /// FACT. + ASIG. (con Mod40).
  ///
  /// Usa el salario diario promedio capturado por el usuario directamente.
  /// El usuario captura el "NUEVO SALARIO PROMEDIO DE 250 SEMANAS" (calculado
  /// externamente, p. ej. desde la hoja Excel SAL. PROM MOD 40), que es el
  /// promedio ponderado de las últimas 250 semanas incluyendo Mod40.
  void recalcularFactAsig() {
    if (!evaluator.isInitialized) return;
    try {
      factAsigCalculation = evaluator.calculateFactAsig(
        salarioDiarioPromedio: inputs.salarioDiarioPromedio,
        umaDiaria: inputs.umaDiaria,
        salarioMinimoDiario: inputs.salarioMinimoDiario,
        pensionYear: inputs.pensionYear,
        // Total CON Modalidad 40 = semanas antes M40 + semanas en M40.
        // semanasCotizadas es int y semanasEnMod40 es double → se redondea a int.
        semanasCotizadas: (inputs.semanasCotizadas + inputs.semanasEnMod40).round(),
        tieneEsposa: inputs.tieneEsposa,
        numeroHijos: inputs.numeroHijos,
        numeroPadres: inputs.numeroPadres,
        edadRetiro: inputs.edadRetiro,
      );
    } catch (e) {
      factAsigCalculation = null;
    }
  }

  /// FACT. + ASIG. SIN Mod40 (usado para comparación).
  ///
  /// Redondea la edad usando la regla de metadata
  /// (`edad_rounding_rule.roundToInteger`) que implementa el Art. 167 LSS 1973
  /// ("6 meses y un día o más = siguiente año").
  void recalcularFactAsigSinMod40() {
    if (!evaluator.isInitialized) return;
    try {
      final rules = evaluator.metadata.financialRules;
      // roundToInteger(60.51) = 61 → porcentaje 0.80 (igual que Excel).
      final edadEntera = rules.edadRoundingRule.roundToInteger(inputs.edadRetiro);

      factAsigSinMod40Calculation = evaluator.calculateFactAsig(
        salarioDiarioPromedio: inputs.salarioPromedio250Semanas,
        umaDiaria: inputs.umaDiaria,
        salarioMinimoDiario: inputs.salarioMinimoDiario,
        pensionYear: inputs.pensionYear,
        semanasCotizadas: inputs.totalSemanasSinMod40,
        tieneEsposa: inputs.tieneEsposa,
        numeroHijos: inputs.numeroHijos,
        numeroPadres: inputs.numeroPadres,
        edadRetiro: edadEntera.toDouble(),
      );
    } catch (e) {
      factAsigSinMod40Calculation = null;
    }
  }

  /// PENSION MOD. 40.
  ///
  /// Fuerza el recálculo de factAsig con el nuevo salario promedio antes de
  /// calcular la pensión.
  void recalcularPensionMod40() {
    if (!evaluator.isInitialized) return;
    try {
      // Forzar recálculo de factAsig con nuevo salario promedio
      recalcularFactAsig();

      pensionMod40Calculation = evaluator.calculatePensionMod40(
        pensionAnual100: factAsigCalculation?.cuantiaTotalPensionVejez ?? 0,
        edadRetiro: inputs.edadRetiro,
        salarioMinimoDiario: inputs.salarioMinimoDiario,
        pensionYear: inputs.pensionYear,
        cuantiaTotalAsignaciones:
            factAsigCalculation?.cuantiaTotalAsignaciones ?? 0,
        totalAyudaAsistencial:
            factAsigCalculation?.totalAyudaAsistencial ?? 0,
      );

      // Debug: registrar valores clave
      ErrorHandler.logDebug(
        'SalarioPromedio: ${inputs.salarioDiarioPromedio}, '
        'PensiónAnual100: ${pensionMod40Calculation?.pensionAnual100}, '
        'PorcentajeEdad: ${pensionMod40Calculation?.porcentajePorEdad}');
    } catch (e) {
      pensionMod40Calculation = null;
    }
  }

  /// COSTO MOD. 40.
  void recalcularCostoMod40() {
    if (!evaluator.isInitialized) return;
    try {
      costoMod40Calculation = evaluator.calculateCostoMod40(
        salarioRegistrado: inputs.salarioRegistrado,
        startDate: inputs.startDate,
        endDate: inputs.endDate,
      );
    } catch (e) {
      costoMod40Calculation = null;
    }
  }

  /// PAGO RETROACTIVO.
  void recalcularRetroactivo() {
    if (!evaluator.isInitialized) return;
    try {
      retroactiveCalculation = evaluator.calculateRetroactivo(
        costoModalidad40: costoMod40Calculation?.inversionTotal ?? 0,
        retroactiveYears: inputs.retroactiveYears,
        startDate: inputs.startDate,
        endDate: inputs.endDate,
      );
    } catch (e) {
      retroactiveCalculation = null;
    }
  }

  /// INVERSION (M40 vs no-M40).
  ///
  /// Sin Mod40 la persona se habría retirado 1 año antes:
  /// - Excel INVERSION: D4 (sin Mod40) = 60, F4 (con Mod40) = 61 = D4+1
  /// - F4 = roundToInteger(edadRetiro) = 61 (misma regla que PENSIÓN ACTUAL)
  /// - D4 = F4 - 1 = 60 (usar floor() daba 60/59, desfasado 1 año vs Excel)
  void recalcularInversion() {
    if (!evaluator.isInitialized) return;
    try {
      final rules = evaluator.metadata.financialRules;
      final edadConMod40 = rules.edadRoundingRule.roundToInteger(inputs.edadRetiro);
      final edadSinMod40 = (edadConMod40 - 1).clamp(55, 65);

      inversionCalculation = evaluator.calculateInversion(
        pensionMensualSinMod40: factAsigSinMod40Calculation?.totalPensionMensual ?? 0,
        pensionMensualConMod40: pensionMod40Calculation?.pensionMensual ?? 0,
        edadRetiroSinMod40: edadSinMod40,
        edadRetiroConMod40: edadConMod40,
        inversionTotalMod40: costoMod40Calculation?.inversionNeta ?? 0,
        inversionTotal: costoMod40Calculation?.inversionTotal ?? 0,
      );
    } catch (e) {
      inversionCalculation = null;
    }
  }

  /// FINANCIAMIENTO.
  ///
  /// Calcula los valores del SEGUNDO FONDEADOR internamente (igual que el
  /// test) y la edad de retiro SIN Mod40 (regla D4 = roundToInteger(edad)-1).
  void recalcularFinanciamiento() {
    if (!evaluator.isInitialized) return;
    try {
      final inversionTotal = retroactiveCalculation?.costoTotal ?? 0;
      final aforeRecovery = retroactiveCalculation?.recuperacionAfore ?? 0;
      final pensionMensualMejorada = pensionMod40Calculation?.pensionMensual ?? 0;
      final sf = evaluator.calculateSegundoFondeador(
        inversionTotal: inversionTotal,
        pensionMensualMejorada: pensionMensualMejorada,
        aforeRecovery: aforeRecovery,
      );

      // edadRetiroSinMod40: edad de retiro SIN Modalidad 40 (INVERSION D46).
      // Excel FINANCIAMIENTO F7 usa la edad decimal (p. ej. 60.5) en (80-C12).
      final rules = evaluator.metadata.financialRules;
      final edadSinMod40 =
          (rules.edadRoundingRule.roundToInteger(inputs.edadRetiro) - 1).clamp(55, 65);

      financiamientoCalculation = evaluator.calculateFinanciamiento(
        inversionTotal: inversionTotal,
        pensionMensualMejorada: pensionMensualMejorada,
        edadRetiro: inputs.edadRetiro,
        pensionSinMod40: factAsigSinMod40Calculation?.totalPensionMensual ?? 0,
        edadRetiroSinMod40: edadSinMod40,
        segundoFondeadorMontoCredito: sf.montoCredito,
        segundoFondeadorCostoFinanciamiento: sf.costoFinanciamiento,
        segundoFondeadorMontoMaximoPagar: sf.montoMaximoPagar,
        segundoFondeadorInversionRequerida: sf.inversionRequerida,
        segundoFondeadorAforeRecovery: sf.aforeRecovery,
      );
    } catch (e) {
      financiamientoCalculation = null;
    }
  }

  /// Recalcula TODA la cadena en el orden de dependencia correcto.
  ///
  /// 1. factAsig → pensionMod40
  /// 2. factAsigSinMod40 (inputs independientes sin Mod40)
  /// 3. costoMod40 → retroactivo (encadena inversionTotal automáticamente)
  /// 4. inversion (usa redondeo threshold 0.501 para edadRetiroSinMod40)
  /// 5. financiamiento (calcula SegundoFondeador internamente)
  void recalcularTodo() {
    recalcularFactAsig();
    recalcularFactAsigSinMod40();
    recalcularPensionMod40();
    recalcularCostoMod40();
    recalcularRetroactivo();
    recalcularInversion();
    recalcularFinanciamiento();
  }
}
