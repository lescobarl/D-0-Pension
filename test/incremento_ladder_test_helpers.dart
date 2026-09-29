import 'package:d_0_pension/core/models/pension_calculation.dart';

/// Fábricas compartidas para las pruebas del "Escalón de tus Incrementos".
///
/// Los valores por defecto son coherentes con el escenario real de referencia
/// (salario promedio con M40 ≈ $2,677.31, salario registrado M40 $3,202.64,
/// tasa M40 2029 = 0.17709, año de pensión 2029). Los tests solo sobrescriben
/// los campos que ejercitan la lógica del escalón (incremento anual,
/// incrementos redondeados, porcentaje por edad, semanas Mod40, etc.).
FactAsigCalculation buildFactAsig({
  double incrementoAnual = 25908.81,
  double numeroIncrementosRedondeado = 31.0,
  int pensionYear = 2029,
  double? totalPensionMensual,
}) {
  return FactAsigCalculation(
    salarioDiarioPromedio: 2677.31,
    umaDiaria: 128.11,
    salarioMinimoDiario: 372.04,
    salarioEnUMAs: 20.90,
    pensionYear: pensionYear,
    porcentajeCuantiaBasica: 0.19,
    cuantiaBasicaPorDia: 608.34,
    totalCuantiaBasicaAnual: 222044.10,
    porcentajeIncremento: 0.015,
    incrementosDiarios: incrementoAnual / 365,
    incrementoAnual: incrementoAnual,
    numeroIncrementosAnuales: numeroIncrementosRedondeado,
    numeroIncrementosRedondeado: numeroIncrementosRedondeado,
    totalIncrementosAnuales:
        incrementoAnual * 1.11 * numeroIncrementosRedondeado,
    cuantiaTotalPensionVejez: 0,
    tieneEsposa: false,
    asignacionEsposa: 0,
    numeroHijos: 0,
    asignacionHijos: 0,
    numeroPadres: 0,
    asignacionPadres: 0,
    cuantiaTotalAsignaciones: 0,
    aplicaAyudaAsistencial: false,
    porcentajeAyudaAsistencial: 0,
    totalAyudaAsistencial: 0,
    cuantiaMasAsignaciones: 0,
    asignacionDecretoPresidencial: 0,
    totalPensionAnual: 0,
    totalPensionMensual:
        totalPensionMensual ??
        (incrementoAnual * 1.11 * numeroIncrementosRedondeado / 12),
  );
}

/// Resultado PENSION MOD 40 con los valores por defecto del escenario real.
PensionMod40Calculation buildPensionMod40({
  double porcentajePorEdad = 0.8,
  double? pensionMensual,
}) {
  return PensionMod40Calculation(
    pensionAnual100: 1200000,
    edadRetiro: 60.5,
    porcentajePorEdad: porcentajePorEdad,
    tipoPension: 'Vejez',
    pensionMinimaGarantizada: 0,
    aplicaMinima: false,
    pensionAnualFinal: 960000,
    pensionMensual: pensionMensual ?? 80000,
  );
}

/// Resultado COSTO MOD 40 con una sola fila anual (la del año de pensión).
CostoMod40Calculation buildCostoMod40({
  double salarioRegistrado = 3202.64,
  double tasa = 0.17709,
  int yearStart = 2029,
  int? yearEnd,
  int diasPagados = 365,
}) {
  final cuotaAnual = tasa * diasPagados * salarioRegistrado;
  final fila = CostoYearRow(
    label: '$yearStart',
    yearStart: yearStart,
    yearEnd: yearEnd,
    salarioRegistrado: salarioRegistrado,
    tasa: tasa,
    diasPagados: diasPagados,
    cuotaMensual: cuotaAnual / 12,
    cuotaAnual: cuotaAnual,
  );
  return CostoMod40Calculation(
    yearlyCosts: [fila],
    inversionTotal: cuotaAnual,
    recuperacionAfore: cuotaAnual * 0.1,
    inversionNeta: cuotaAnual * 0.9,
  );
}
