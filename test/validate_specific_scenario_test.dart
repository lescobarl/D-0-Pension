import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('Escenario específico: App vs Excel', () {
    // === INPUTS que coinciden con los que USA Excel realmente ===
    // Del JSON: salario_prom_250 = 2677.3058, edad_retiro = 60.5
    // semanas_cot_m40 = 2038.14 (con Mod40) para cálculo de incrementos
    final salarioDiarioPromedio = 2677.3058;
    final umaDiaria = 122.59;
    final salarioMinimoDiario = 372.04;
    final semanasCotizadas = 2038; // Excel usa semanas totales CON Mod40
    final edadRetiro = 60.5; // Excel redondea a 60.5
    final tieneEsposa = true;
    final numeroHijos = 1;
    final numeroPadres = 0;
    final anoPension = 2029;

    // === CALCULAR CON APP ===
    final factAsig = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioDiarioPromedio,
      umaDiaria: umaDiaria,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: anoPension,
      semanasCotizadas: semanasCotizadas,
      tieneEsposa: tieneEsposa,
      numeroHijos: numeroHijos,
      numeroPadres: numeroPadres,
      edadRetiro: edadRetiro,
    );

    final pensionMod40 = evaluator.calculatePensionMod40(
      pensionAnual100: factAsig.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: anoPension,
      cuantiaTotalAsignaciones: factAsig.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: factAsig.totalAyudaAsistencial,
    );

    // Pensión SIN Mod40 (con edad de retiro sin mod40 = 61)
    final pensionSin = evaluator.calculatePensionMod40(
      pensionAnual100: factAsig.cuantiaTotalPensionVejez,
      edadRetiro: 61.0, // edad_sin_mod40 del Excel INVERSION
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: anoPension,
      cuantiaTotalAsignaciones: factAsig.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: factAsig.totalAyudaAsistencial,
    );

    // === RESULTADOS APP ===
    print('\n========== APP RESULTS ==========');
    print('\n--- FACT. + ASIG. MOD.40 ---');
    print('  pension_vejez_100:        ${factAsig.cuantiaTotalPensionVejez.toStringAsFixed(4)}');
    print('  total_pension_anual:      ${factAsig.totalPensionAnual.toStringAsFixed(4)}');
    print('  pension_mensual_neta:     ${factAsig.totalPensionMensual.toStringAsFixed(4)}');
    print('  numero_incrementos_rounded: ${factAsig.numeroIncrementosRedondeado}');
    print('  total_incrementos_anuales: ${factAsig.totalIncrementosAnuales.toStringAsFixed(4)}');
    print('  total_cuantia_basica:     ${factAsig.totalCuantiaBasicaAnual.toStringAsFixed(4)}');
    print('  porcentaje_cuantia_basica: ${factAsig.porcentajeCuantiaBasica}');
    print('  cuantiaTotalAsignaciones: ${factAsig.cuantiaTotalAsignaciones.toStringAsFixed(4)}');
    print('  totalAyudaAsistencial:    ${factAsig.totalAyudaAsistencial.toStringAsFixed(4)}');
    print('  salarioEnUMAs:            ${factAsig.salarioEnUMAs}');

    print('\n--- PENSION MOD. 40 ---');
    print('  pension_anual_final:      ${pensionMod40.pensionAnualFinal.toStringAsFixed(4)}');
    print('  pension_mensual:          ${pensionMod40.pensionMensual.toStringAsFixed(4)}');
    print('  porcentaje_edad:          ${pensionMod40.porcentajePorEdad}');
    print('  pension_minima:           ${pensionMod40.pensionMinimaGarantizada.toStringAsFixed(4)}');

    print('\n--- PENSIÓN SIN Mod40 (edad=61) ---');
    print('  pension_anual_sin_m40:    ${pensionSin.pensionAnualFinal.toStringAsFixed(4)}');
    print('  pension_mensual_sin_m40:  ${pensionSin.pensionMensual.toStringAsFixed(4)}');

    print('\n--- MEJORA ---');
    final mejora = pensionMod40.pensionMensual - pensionSin.pensionMensual;
    final double mejoraPorc = pensionSin.pensionMensual > 0 ? (mejora / pensionSin.pensionMensual) * 100 : 0.0;
    print('  mejora_mensual:           ${mejora.toStringAsFixed(2)}');
    print('  mejora_%:                 ${mejoraPorc.toStringAsFixed(2)}%');

    // === EXCEL RESULTS ===
    print('\n========== EXCEL RESULTS (base_user) ==========');
    print('\n--- FACT. + ASIG. MOD.40 ---');
    print('  pension_vejez_100:        938274.5181');
    print('  pension_mensual_neta:     73302.6967');
    print('  numero_incrementos_rounded: 30');
    print('  total_incrementos_anuales: 797262.1627');
    print('  total_cuantia_basica:     141012.3553');
    print('  porcentaje_cuantia_basica: 0.13');

    print('\n--- PENSION MOD. 40 ---');
    print('  pension_anual_final:      879632.3607');
    print('  pension_mensual:          73302.6967');
    print('  porcentaje_edad:          0.75');

    print('\n--- INVERSION ---');
    print('  pension_mensual_sin:      62856.6393');
    print('  pension_mensual_con:      73302.6967');

    print('\n--- MEJORA ---');
    final mejoraExcel = 73302.6967 - 62856.6393;
    final mejoraPorcExcel = (mejoraExcel / 62856.6393) * 100;
    print('  mejora_mensual:           ${mejoraExcel.toStringAsFixed(2)}');
    print('  mejora_%:                 ${mejoraPorcExcel.toStringAsFixed(2)}%');

    // === COMPARACIÓN ===
    print('\n========== COMPARACIÓN ==========');
    final tol = 1.0;
    int passed = 0;
    int failed = 0;
    
    void compare(String label, double app, double excel) {
      final diff = (app - excel).abs();
      final ok = diff <= tol;
      if (ok) { passed++; } else { failed++; }
      print('  ${ok ? "✅" : "❌"} $label: App=${app.toStringAsFixed(4)} vs Excel=${excel} (diff=${diff.toStringAsFixed(4)})');
    }

    compare('Pensión vejez 100%', factAsig.cuantiaTotalPensionVejez, 938274.5181);
    compare('Pensión mensual neta', factAsig.totalPensionMensual, 73302.6967);
    compare('Pensión anual final Mod40', pensionMod40.pensionAnualFinal, 879632.3607);
    compare('Pensión mensual Mod40', pensionMod40.pensionMensual, 73302.6967);
    compare('Total incrementos anuales', factAsig.totalIncrementosAnuales, 797262.1627);
    compare('Total cuantía básica anual', factAsig.totalCuantiaBasicaAnual, 141012.3553);
    compare('Pensión mensual sin Mod40', pensionSin.pensionMensual, 62856.6393);
    compare('Mejora mensual', mejora, mejoraExcel);
    compare('Mejora %', mejoraPorc, mejoraPorcExcel);

    print('\n========== RESULTADO: $passed passed, $failed failed ==========');
  });
}
