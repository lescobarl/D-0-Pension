import 'dart:math' as math;

import '../../core/models/app_metadata.dart';
import '../../core/models/pension_calculation.dart';

/// Asesoría sobre el "escalón de tus incrementos" (Art. 167 LSS).
///
/// El número de incrementos anuales de la pensión Ley 73 se redondea en
/// escalones de 0.5 (celda C25 del Excel): con 13/52 de año ganado se sube
/// medio incremento y con 27/52 un incremento completo. Una sola semana puede
/// decidir el escalón, por lo que este bloque asesora al usuario en la pestaña
/// de Pensión:
/// - Cuántas semanas Mod40 le faltan para SUBIR al siguiente escalón y si
///   conviene hacerlo (regla: solo si falta poco, ≤ ~1 mes de aportación).
/// - Cuántas puede dejar de pagar SIN perder el escalón actual (ahorro), o por
///   qué NO conviene seguir aportando cuando la inversión es muy grande.
///
/// Todos los valores se derivan de [FinancialRules] (metadata) y de los
/// resultados de cálculo ya producidos por el motor: nada está hardcodeado.
class IncrementoLadderAdvice {
  // --- Estado actual ---

  /// Número de incrementos redondeado (ej. 31.0, 30.5).
  final double incrementosActuales;

  /// Total exacto de semanas cotizadas con Mod40
  /// (`semanasAntesMod40 + semanasEnMod40`).
  final double semanasTotales;

  /// Semanas en Modalidad 40.
  final double semanasEnMod40;

  /// Semanas mínimas para estar EN el escalón actual (piso).
  final double pisoActualSemanas;

  /// Semanas Mod40 que se pueden recortar sin bajar del escalón actual.
  final double semanasRecortablesSinPerder;

  // --- Escalón siguiente (subir) ---

  /// El siguiente escalón posible (siempre +0.5).
  final double siguienteIncremento;

  /// Semanas mínimas para alcanzar [siguienteIncremento] (piso).
  final double pisoSiguienteSemanas;

  /// Semanas que faltan para el siguiente escalón.
  final double semanasParaSiguiente;

  /// Semanas mínimas del escalón anterior (contexto del rango actual).
  final double pisoAnteriorSemanas;

  // --- Valores monetarios ---

  /// Beneficio mensual de un incremento completo, de por vida.
  final double beneficioIncrementoCompletoMensual;

  /// Beneficio mensual de medio incremento, de por vida.
  final double beneficioMedioIncrementoMensual;

  /// Costo semanal estimado de la Modalidad 40 (año de pensión).
  final double costoPorSemanaM40;

  /// Ahorro estimado por recortar [semanasRecortablesSinPerder] semanas.
  final double ahorroEstimado;

  // --- Regla (fracciones del Art. 167) ---

  /// Fracción de año ganada para medio incremento (13/52).
  final double fraccionMedioIncremento;

  /// Fracción de año ganada para un incremento completo (27/52).
  final double fraccionIncrementoCompleto;

  // --- Regla de decisión (subir / dejar de aportar) ---

  /// Umbral en semanas equivalente a ~1 mes de aportación
  /// (`weeksPerYear / monthsPerYear`). Define cuándo conviene SUBIR: si falta
  /// poco (≤ 1 mes), la inversión extra es chica y el beneficio es de por vida;
  /// si falta más, la inversión es muy grande y no conviene seguir aportando.
  final double semanasPorMes;

  /// ¿Conviene SUBIR al siguiente escalón? Cierto solo cuando falta poco
  /// (`0 < semanasParaSiguiente ≤ semanasPorMes`).
  final bool recomiendaSubir;

  /// Inversión estimada en Modalidad 40 para alcanzar el siguiente escalón
  /// (`semanasParaSiguiente × costoPorSemanaM40`).
  final double costoParaSubir;

  /// Meses de aportación estimados para alcanzar el siguiente escalón.
  double get mesesParaSubir => semanasParaSiguiente / semanasPorMes;

  const IncrementoLadderAdvice({
    required this.incrementosActuales,
    required this.semanasTotales,
    required this.semanasEnMod40,
    required this.pisoActualSemanas,
    required this.semanasRecortablesSinPerder,
    required this.siguienteIncremento,
    required this.pisoSiguienteSemanas,
    required this.semanasParaSiguiente,
    required this.pisoAnteriorSemanas,
    required this.beneficioIncrementoCompletoMensual,
    required this.beneficioMedioIncrementoMensual,
    required this.costoPorSemanaM40,
    required this.ahorroEstimado,
    required this.fraccionMedioIncremento,
    required this.fraccionIncrementoCompleto,
    required this.semanasPorMes,
    required this.recomiendaSubir,
    required this.costoParaSubir,
  });

  /// Incremento del escalón inmediato anterior (actual − 0.5).
  double get incrementosAnteriores => incrementosActuales - 0.5;
}

/// Motor de cálculo puro de la asesoría "Escalón de tus Incrementos".
///
/// No depende de widgets ni del provider: recibe las reglas (metadata) y los
/// resultados de cálculo ya producidos, y devuelve un [IncrementoLadderAdvice]
/// listo para renderizar.
class IncrementoLadder {
  IncrementoLadder._();

  /// Días por semana (constante de calendario universal). Coincide con la
  /// definición de semana del motor: `semanasEnMod40 * 7` días (ver
  /// `RetroactiveProvider._syncFechasMod40`).
  static const int daysPerWeek = 7;

  /// Meses por año (constante de calendario universal).
  static const int monthsPerYear = 12;

  /// Calcula la asesoría completa del escalón de incrementos.
  ///
  /// [semanasTotales] debe ser el total EXACTO (`semanasAntesMod40 +
  /// semanasEnMod40`), no el redondeado a entero que usa el motor internamente;
  /// así el piso y las semanas recortables son precisas. [factAsig] aporta
  /// [FactAsigCalculation.incrementoAnual] y
  /// [FactAsigCalculation.numeroIncrementosRedondeado] (escalón actual);
  /// [pensionMod40] aporta [PensionMod40Calculation.porcentajePorEdad]; y
  /// [costoMod40] (si existe) aporta la tasa/salario del año de pensión para
  /// estimar el costo semanal de la Modalidad 40.
  static IncrementoLadderAdvice compute({
    required FinancialRules rules,
    required double semanasTotales,
    required double semanasEnMod40,
    required FactAsigCalculation factAsig,
    required PensionMod40Calculation pensionMod40,
    required CostoMod40Calculation? costoMod40,
    required int pensionYear,
  }) {
    final incrementosActuales = factAsig.numeroIncrementosRedondeado;
    final siguienteIncremento = incrementosActuales + 0.5;

    // Umbral de decisión: ~1 mes de aportación (52 semanas / 12 meses).
    final semanasPorMes = rules.weeksPerYear / monthsPerYear;

    final pisoActual = _pisoDe(incrementosActuales, rules);
    final pisoSiguiente = _pisoDe(siguienteIncremento, rules);
    final pisoAnterior = _pisoDe(incrementosActuales - 0.5, rules);

    // Semanas Mod40 recortables sin caer por debajo del piso actual (nunca más
    // de las semanas que realmente se pagan en Mod40).
    final semanasRecortables = math.max(
      0.0,
      math.min(semanasTotales - pisoActual, semanasEnMod40),
    );

    // Semanas necesarias para alcanzar el siguiente escalón.
    final semanasParaSiguiente = math.max(0.0, pisoSiguiente - semanasTotales);

    // Valor monetario de un incremento (celdas C23→C26 / C72):
    // incrementoAnual × aguinaldoFactor × porcentajePorEdad / 12.
    final beneficioCompleto =
        factAsig.incrementoAnual *
        rules.aguinaldoFactor *
        pensionMod40.porcentajePorEdad /
        monthsPerYear;
    final beneficioMedio = beneficioCompleto / 2;

    final costoPorSemana = _costoSemanal(costoMod40, pensionYear);
    final ahorroEstimado = semanasRecortables * costoPorSemana;

    // Decisión de subir / dejar de aportar: conviene SUBIR solo si falta poco
    // (≤ ~1 mes); si falta más, la inversión es muy grande y cada semana que se
    // paga sin llegar al siguiente piso no aumenta la pensión.
    final costoParaSubir = semanasParaSiguiente * costoPorSemana;
    final recomiendaSubir =
        semanasParaSiguiente > 0 && semanasParaSiguiente <= semanasPorMes;

    return IncrementoLadderAdvice(
      incrementosActuales: incrementosActuales,
      semanasTotales: semanasTotales,
      semanasEnMod40: semanasEnMod40,
      pisoActualSemanas: pisoActual,
      pisoSiguienteSemanas: pisoSiguiente,
      pisoAnteriorSemanas: pisoAnterior,
      semanasRecortablesSinPerder: semanasRecortables,
      siguienteIncremento: siguienteIncremento,
      semanasParaSiguiente: semanasParaSiguiente,
      beneficioIncrementoCompletoMensual: beneficioCompleto,
      beneficioMedioIncrementoMensual: beneficioMedio,
      costoPorSemanaM40: costoPorSemana,
      ahorroEstimado: ahorroEstimado,
      fraccionMedioIncremento: rules.edadRoundingRule.incrementQuarterThreshold,
      fraccionIncrementoCompleto: rules.edadRoundingRule.incrementHalfThreshold,
      semanasPorMes: semanasPorMes,
      recomiendaSubir: recomiendaSubir,
      costoParaSubir: costoParaSubir,
    );
  }

  /// Semanas mínimas para alcanzar un escalón redondeado [valorRedondeado].
  ///
  /// Deriva de las fórmulas de la celda C25 (Art. 167), invertidas:
  /// - Escalón entero N (ej. 31.0): `minWeeks + 52×(N−1) + 52×(27/52)`.
  ///   Se gana un incremento completo cuando la fracción de año >= 27/52.
  /// - Escalón medio N+0.5 (ej. 31.5): `minWeeks + 52×N + 52×(13/52)`.
  ///   Se gana medio incremento cuando la fracción de año >= 13/52.
  static double _pisoDe(double valorRedondeado, FinancialRules rules) {
    final umbrales = rules.edadRoundingRule;
    if (valorRedondeado == valorRedondeado.floorToDouble()) {
      return rules.minWeeksForIncrement +
          rules.weeksPerYear * (valorRedondeado - 1) +
          rules.weeksPerYear * umbrales.incrementHalfThreshold;
    }
    return rules.minWeeksForIncrement +
        rules.weeksPerYear * valorRedondeado.floorToDouble() +
        rules.weeksPerYear * umbrales.incrementQuarterThreshold;
  }

  /// Costo semanal de la Modalidad 40 en el año de pensión.
  ///
  /// Se toma la fila de [CostoMod40Calculation.yearlyCosts] que corresponde a
  /// [pensionYear] y se proyecta `tasa × salarioRegistrado × días por semana`.
  static double _costoSemanal(
    CostoMod40Calculation? costoMod40,
    int pensionYear,
  ) {
    if (costoMod40 == null || costoMod40.yearlyCosts.isEmpty) return 0;
    final fila = costoMod40.yearlyCosts.firstWhere(
      (r) =>
          r.yearStart <= pensionYear &&
          (r.yearEnd ?? pensionYear) >= pensionYear,
      orElse: () => costoMod40.yearlyCosts.last,
    );
    return fila.tasa * fila.salarioRegistrado * daysPerWeek;
  }
}
