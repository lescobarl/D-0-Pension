import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

/// ESCENARIO: 1,960 sem + 78 M40 = 2,038 total, esposa=SI, 1 hijo, edad 60.5
/// 
/// Este test desglosa CADA componente de la pensión para que puedas
/// comparar UNO POR UNO con tu Excel y encontrar dónde está la diferencia.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('DESGLOSE COMPLETO - 1960 sem, 78 M40, esposa=SI', () {
    const salarioDiarioPromedio = 2840.6157;
    const umaDiaria = 122.5889;
    const salarioMinimoDiario = 372.0409;
    const pensionYear = 2029;
    const semanasCotizadas = 2038; // 1960 + 78
    const tieneEsposa = true;
    const numeroHijos = 1;
    const numeroPadres = 0;
    const edadRetiro = 60.5;

    final fact = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioDiarioPromedio,
      umaDiaria: umaDiaria,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: pensionYear,
      semanasCotizadas: semanasCotizadas,
      tieneEsposa: tieneEsposa,
      numeroHijos: numeroHijos,
      numeroPadres: numeroPadres,
      edadRetiro: edadRetiro,
    );

    final pension = evaluator.calculatePensionMod40(
      pensionAnual100: fact.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      cuantiaTotalAsignaciones: fact.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: fact.totalAyudaAsistencial,
    );

    print('╔══════════════════════════════════════════════════════════════════╗');
    print('║ DESGLOSE COMPLETO - ESCENARIO: 1960+78 M40, Esposa=SI         ║');
    print('╚══════════════════════════════════════════════════════════════════╝');
    print('');
    print('═══════════════════════════════════════════════════════════════════');
    print('PASO 1: SALARIO EN UMAs');
    print('═══════════════════════════════════════════════════════════════════');
    print('  salarioDiarioPromedio  = $salarioDiarioPromedio');
    print('  umaDiaria              = $umaDiaria');
    print('  salarioEnUMAs          = ROUND($salarioDiarioPromedio / $umaDiaria, 2)');
    print('  salarioEnUMAs          = ${fact.salarioEnUMAs}');
    print('');

    print('═══════════════════════════════════════════════════════════════════');
    print('PASO 2: CUANTÍA BÁSICA');
    print('═══════════════════════════════════════════════════════════════════');
    print('  porcentajeCuantiaBasica = ${fact.porcentajeCuantiaBasica} (de tabla con 23.17 UMAs)');
    print('  cuantiaBasicaPorDia     = ${fact.porcentajeCuantiaBasica} * $salarioMinimoDiario');
    print('  cuantiaBasicaPorDia     = \$${fact.cuantiaBasicaPorDia.toStringAsFixed(2)}');
    print('  totalCuantiaBasicaAnual = ${fact.cuantiaBasicaPorDia.toStringAsFixed(2)} * 365 * 1.11');
    print('  totalCuantiaBasicaAnual = \$${fact.totalCuantiaBasicaAnual.toStringAsFixed(2)}');
    print('');

    print('═══════════════════════════════════════════════════════════════════');
    print('PASO 3: INCREMENTOS ANUALES');
    print('═══════════════════════════════════════════════════════════════════');
    print('  porcentajeIncremento    = ${fact.porcentajeIncremento} (de tabla con 23.17 UMAs)');
    print('  incrementosDiarios      = ${fact.porcentajeIncremento} * $salarioMinimoDiario');
    print('  incrementosDiarios      = \$${fact.incrementosDiarios.toStringAsFixed(4)}');
    print('  incrementoAnual         = ${fact.incrementosDiarios.toStringAsFixed(4)} * 365');
    print('  incrementoAnual         = \$${fact.incrementoAnual.toStringAsFixed(2)}');
    print('  numeroIncrementosAnuales= ($semanasCotizadas - 500) / 52');
    print('  numeroIncrementosAnuales= ${fact.numeroIncrementosAnuales.toStringAsFixed(4)}');
    print('  numeroIncrementosRedondeado = ${fact.numeroIncrementosRedondeado} (redondeo art. 167)');
    print('  totalIncrementosAnuales = ${fact.incrementoAnual.toStringAsFixed(2)} * ${fact.numeroIncrementosRedondeado} * 1.11');
    print('  totalIncrementosAnuales = \$${fact.totalIncrementosAnuales.toStringAsFixed(2)}');
    print('');

    print('═══════════════════════════════════════════════════════════════════');
    print('PASO 4: CUANTÍA TOTAL PENSIÓN VEJEZ');
    print('═══════════════════════════════════════════════════════════════════');
    print('  cuantiaTotalPensionVejez = ${fact.totalCuantiaBasicaAnual.toStringAsFixed(2)} + ${fact.totalIncrementosAnuales.toStringAsFixed(2)}');
    print('  cuantiaTotalPensionVejez = \$${fact.cuantiaTotalPensionVejez.toStringAsFixed(2)}');
    print('');

    print('═══════════════════════════════════════════════════════════════════');
    print('PASO 5: ASIGNACIONES FAMILIARES');
    print('═══════════════════════════════════════════════════════════════════');
    final baseAsig = fact.cuantiaTotalPensionVejez / 1.11;
    print('  baseAsignaciones        = ${fact.cuantiaTotalPensionVejez.toStringAsFixed(2)} / 1.11');
    print('  baseAsignaciones        = \$${baseAsig.toStringAsFixed(2)}');
    print('');
    print('  --- ASIGNACIÓN ESPOSA (tieneEsposa=$tieneEsposa) ---');
    print('  asignacionEsposa        = $tieneEsposa ? $baseAsig * 0.15 : 0');
    print('  asignacionEsposa        = \$${fact.asignacionEsposa.toStringAsFixed(2)}');
    print('');
    print('  --- ASIGNACIÓN HIJOS (numeroHijos=$numeroHijos) ---');
    print('  asignacionHijos         = $baseAsig * 0.10 * $numeroHijos');
    print('  asignacionHijos         = \$${fact.asignacionHijos.toStringAsFixed(2)}');
    print('');
    print('  --- ASIGNACIÓN PADRES (numeroPadres=$numeroPadres) ---');
    print('  asignacionPadres        = \$${fact.asignacionPadres.toStringAsFixed(2)}');
    print('');
    print('  --- TOTAL ASIGNACIONES ---');
    print('  cuantiaTotalAsignaciones = (${fact.asignacionEsposa.toStringAsFixed(2)} + ${fact.asignacionHijos.toStringAsFixed(2)} + ${fact.asignacionPadres.toStringAsFixed(2)}) * 1.11 * ${pension.porcentajePorEdad}');
    print('  cuantiaTotalAsignaciones = \$${fact.cuantiaTotalAsignaciones.toStringAsFixed(2)}');
    print('');

    print('═══════════════════════════════════════════════════════════════════');
    print('PASO 6: PENSIÓN MOD 40');
    print('═══════════════════════════════════════════════════════════════════');
    print('  porcentajePorEdad       = ${pension.porcentajePorEdad} (edad $edadRetiro → ${edadRetiro.ceil()} años IMSS)');
    print('  pensionAnual100         = \$${pension.pensionAnual100.toStringAsFixed(2)}');
    print('  pensionMinimaGarantizada= \$${pension.pensionMinimaGarantizada.toStringAsFixed(2)}');
    print('  aplicaMinima            = ${pension.aplicaMinima}');
    print('');
    print('  pensionAnualFinal       = ${pension.pensionAnual100.toStringAsFixed(2)} * ${pension.porcentajePorEdad} + ${fact.cuantiaTotalAsignaciones.toStringAsFixed(2)} + ${fact.totalAyudaAsistencial.toStringAsFixed(2)}');
    print('  pensionAnualFinal       = \$${pension.pensionAnualFinal.toStringAsFixed(2)}');
    print('  PENSION MENSUAL         = ${pension.pensionAnualFinal.toStringAsFixed(2)} / 12');
    print('  PENSION MENSUAL         = \$${pension.pensionMensual.toStringAsFixed(2)}');
    print('');

    print('═══════════════════════════════════════════════════════════════════');
    print('RESUMEN - COMPARA CADA VALOR CON TU EXCEL');
    print('═══════════════════════════════════════════════════════════════════');
    print('  #  Concepto                          App          Tu Excel   Diferencia?');
    print('  ─────────────────────────────────────────────────────────────────────');
    print('  1  salarioEnUMAs                     ${fact.salarioEnUMAs}');
    print('  2  porcentajeCuantiaBasica           ${fact.porcentajeCuantiaBasica}');
    print('  3  cuantiaBasicaPorDia               \$${fact.cuantiaBasicaPorDia.toStringAsFixed(2)}');
    print('  4  totalCuantiaBasicaAnual           \$${fact.totalCuantiaBasicaAnual.toStringAsFixed(2)}');
    print('  5  porcentajeIncremento              ${fact.porcentajeIncremento}');
    print('  6  incrementoAnual                   \$${fact.incrementoAnual.toStringAsFixed(2)}');
    print('  7  numeroIncrementosAnuales          ${fact.numeroIncrementosAnuales.toStringAsFixed(4)}');
    print('  8  numeroIncrementosRedondeado       ${fact.numeroIncrementosRedondeado}');
    print('  9  totalIncrementosAnuales           \$${fact.totalIncrementosAnuales.toStringAsFixed(2)}');
    print(' 10  cuantiaTotalPensionVejez          \$${fact.cuantiaTotalPensionVejez.toStringAsFixed(2)}');
    print(' 11  asignacionEsposa                  \$${fact.asignacionEsposa.toStringAsFixed(2)}');
    print(' 12  asignacionHijos                   \$${fact.asignacionHijos.toStringAsFixed(2)}');
    print(' 13  cuantiaTotalAsignaciones          \$${fact.cuantiaTotalAsignaciones.toStringAsFixed(2)}');
    print(' 14  porcentajePorEdad                 ${pension.porcentajePorEdad}');
    print(' 15  pensionAnualFinal                 \$${pension.pensionAnualFinal.toStringAsFixed(2)}');
    print(' 16  PENSION MENSUAL                   \$${pension.pensionMensual.toStringAsFixed(2)}');
    print('');

    print('⚠️  COMPARA cada número de arriba con tu Excel.');
    print('⚠️  El PRIMERO que sea diferente es donde está el error.');
    print('');
  });
}
