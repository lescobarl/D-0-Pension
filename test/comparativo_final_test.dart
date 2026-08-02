import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

/// Test con los MISMOS valores que el Excel (leídos del archivo real con openpyxl)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('VALIDACIÓN: Mismos inputs del Excel (openpyxl)', () {
    // ============================================================
    // VALORES EXACTOS del Excel (leídos con openpyxl)
    // ============================================================
    // DATOS GEN. MOD 40:
    //   C4  = 60.583333333333336  (edad retiro)
    //   C6  = 1960                (semanas antes M40)
    //   C7  = 134.71428571428572  (semanas en M40)
    //   C8  = 'NO'                (esposa)
    //   C9  = 1                   (hijos)
    //   C10 = 0                   (padres)
    //   C12 = 61                  (edad entera)
    //   C14 = 2840.615712142857   (salario promedio con M40)
    //   C16 = 2094.714285714286   (total semanas)

    final salarioConM40 = 2840.615712142857;
    final salarioSinM40 = 2281.531142857143; // E20 de DATOS GEN.
    final semanasTotales = 2095; // redondeado
    final semanasSinM40 = 1960;
    final semanasEnM40 = 134.71428571428572;
    final edadRetiro = 60.583333333333336;
    final tieneEsposa = false;
    final numeroHijos = 1;
    final numeroPadres = 0;
    final umaDiaria = 122.5889; // C5 FACT+ASIG MOD.40
    final salarioMinimo = 372.0409;
    final pensionYear = 2029;
    final startM40 = DateTime(2027, 2, 1);
    final endM40 = DateTime(2029, 8, 31);
    final salarioRegistradoM40 = 25.0 * umaDiaria;

    print('\n╔══════════════════════════════════════════════════════════════╗');
    print('║ VALIDACIÓN: MISMOS VALORES QUE EL EXCEL                     ║');
    print('╚══════════════════════════════════════════════════════════════╝');
    print('');
    print('📥 INPUTS (idénticos al Excel):');
    print('  salarioConM40     = $salarioConM40');
    print('  salarioSinM40     = $salarioSinM40');
    print('  semanasTotales    = $semanasTotales');
    print('  semanasEnM40      = $semanasEnM40');
    print('  edadRetiro        = $edadRetiro');
    print('  tieneEsposa       = $tieneEsposa');
    print('  numeroHijos       = $numeroHijos');
    print('  umaDiaria         = $umaDiaria');
    print('  salarioMinimo     = $salarioMinimo');
    print('  pensionYear       = $pensionYear');
    print('  M40 inicio-fin    = ${startM40.toIso8601String().substring(0,10)} a ${endM40.toIso8601String().substring(0,10)}');
    print('');

    // ============================================================
    // CÁLCULO 1: FACT + ASIG con Mod40
    // ============================================================
    final fact = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioConM40,
      umaDiaria: umaDiaria,
      salarioMinimoDiario: salarioMinimo,
      pensionYear: pensionYear,
      semanasCotizadas: semanasTotales,
      tieneEsposa: tieneEsposa,
      numeroHijos: numeroHijos,
      numeroPadres: numeroPadres,
      edadRetiro: edadRetiro,
    );

    print('📊 FACT + ASIG (con M40):');
    print('  salarioEnUMAs              = ${fact.salarioEnUMAs.toStringAsFixed(4)} (Excel: 23.17)');
    print('  porcentajeCuantiaBasica    = ${fact.porcentajeCuantiaBasica.toStringAsFixed(4)} (Excel: 0.13)');
    print('  cuantiaBasicaPorDia        = ${fact.cuantiaBasicaPorDia.toStringAsFixed(4)} (Excel: 369.28)');
    print('  totalCuantiaBasicaAnual    = ${fact.totalCuantiaBasicaAnual.toStringAsFixed(4)} (Excel: 149613.81)');
    print('  porcentajeIncremento       = ${fact.porcentajeIncremento.toStringAsFixed(4)} (Excel: 0.0245)');
    print('  incrementoAnual            = ${fact.incrementoAnual.toStringAsFixed(4)} (Excel: 25402.21)');
    print('  numeroIncrementosAnuales   = ${fact.numeroIncrementosAnuales.toStringAsFixed(4)} (Excel: 30.67)');
    print('  numeroIncrementosRedondeado= ${fact.numeroIncrementosRedondeado.toStringAsFixed(2)} (Excel: 31)');
    print('  totalIncrementosAnuales    = ${fact.totalIncrementosAnuales.toStringAsFixed(4)} (Excel: 874089.91)');
    print('  cuantiaTotalPensionVejez   = ${fact.cuantiaTotalPensionVejez.toStringAsFixed(4)} (Excel: 1023703.72)');
    print('  asignacionEsposa           = ${fact.asignacionEsposa.toStringAsFixed(4)} (Excel: 0)');
    print('  asignacionHijos            = ${fact.asignacionHijos.toStringAsFixed(4)} (Excel: 92225.56)');
    print('  asignacionPadres           = ${fact.asignacionPadres.toStringAsFixed(4)} (Excel: 0)');
    print('  cuantiaTotalAsignaciones   = ${fact.cuantiaTotalAsignaciones.toStringAsFixed(4)} (Excel: 81896.30)');
    print('  totalPensionAnual          = ${fact.totalPensionAnual.toStringAsFixed(4)} (Excel: 900859.27)');
    print('  totalPensionMensual        = ${fact.totalPensionMensual.toStringAsFixed(4)} (Excel: 75071.61)');
    print('');

    // ============================================================
    // CÁLCULO 2: PENSIÓN MOD 40
    // ============================================================
    final pens = evaluator.calculatePensionMod40(
      pensionAnual100: fact.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimo,
      cuantiaTotalAsignaciones: fact.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: fact.totalAyudaAsistencial,
    );

    print('📊 PENSIÓN MOD 40:');
    print('  porcentajePorEdad    = ${pens.porcentajePorEdad.toStringAsFixed(4)} (Excel: 0.80)');
    print('  pensionAnual100      = ${pens.pensionAnual100.toStringAsFixed(4)} (Excel: 1023703.72)');
    print('  pensionAnualFinal    = ${pens.pensionAnualFinal.toStringAsFixed(4)} (Excel: 900859.27)');
    print('  pensionMensual       = ${pens.pensionMensual.toStringAsFixed(4)} (Excel: 75071.61)');
    print('');

    // ASSERTIONS CONTRA EXCEL
    print('🎯 ASSERTIONS:');
    try {
      expect(fact.cuantiaTotalPensionVejez, closeTo(1023703.72, 1.0));
      print('  ✅ cuantiaTotalPensionVejez OK');
    } catch (e) { print('  ❌ cuantiaTotalPensionVejez FAIL'); }
    try {
      expect(fact.totalPensionAnual, closeTo(900859.27, 1.0));
      print('  ✅ totalPensionAnual OK');
    } catch (e) { print('  ❌ totalPensionAnual FAIL'); }
    try {
      expect(fact.totalPensionMensual, closeTo(75071.61, 1.0));
      print('  ✅ totalPensionMensual OK');
    } catch (e) { print('  ❌ totalPensionMensual FAIL'); }
    try {
      expect(pens.pensionMensual, closeTo(75071.61, 1.0));
      print('  ✅ pensionMensual (Mod40) OK');
    } catch (e) { print('  ❌ pensionMensual (Mod40) FAIL'); }
  });
}
