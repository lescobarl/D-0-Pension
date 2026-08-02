// TEST: Comparar App vs Excel con los valores EXACTOS del escenario actual.
//
// Escenario (del Excel):
// - Esposa: SI
// - Hijos: 1
// - Total semanas: 2090.2857
// - Salario diario promedio (NUEVO): 2897.1699
// - Edad retiro: 61.5
// - Edad entera: 61
// - UMA diaria: 128.1055
// - Salario minimo: 393.2472
// - Salario en UMAs: 22.62
// - Porcentaje por edad: 0.80 (61 anios)

import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('ESCENARIO EXCEL ACTUAL: esposa=SI, 2090 sem, salario=2897.17', () {
    // Inputs EXACTOS del Excel actual
    final semanasCotizadas = 2090; // 2090.29 truncado
    final salarioDiarioPromedio = 2897.1698986857136;
    final umaDiaria = 128.10545274999998;
    final salarioMinimoDiario = 393.2472081334349;
    final pensionYear = 2029;
    final tieneEsposa = true;
    final numeroHijos = 1;
    final numeroPadres = 0;
    final edadRetiro = 61.5;

    final result = evaluator.calculateFactAsig(
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

    print('\n=== ESCENARIO EXCEL ACTUAL ===');
    print('  salarioEnUMAs:            \$${result.salarioEnUMAs.toStringAsFixed(2)} (Excel: 22.62)');
    print('  cuantiaBasicaPorDia:      \$${result.cuantiaBasicaPorDia.toStringAsFixed(4)} (Excel: 376.63)');
    print('  totalCuantiaBasicaAnual:  \$${result.totalCuantiaBasicaAnual.toStringAsFixed(2)} (Excel: 152,592.49)');
    print('  incrementoAnual:          \$${result.incrementoAnual.toStringAsFixed(2)} (Excel: 25,907.94)');
    print('  numeroIncrementosAnuales:  ${result.numeroIncrementosAnuales.toStringAsFixed(4)} (Excel: 30.58)');
    print('  numeroIncrementosRedond:  ${result.numeroIncrementosRedondeado.toStringAsFixed(2)} (Excel: 31)');
    print('  totalIncrementosAnuales:  \$${result.totalIncrementosAnuales.toStringAsFixed(2)} (Excel: 891,492.28)');
    print('  cuantiaTotalPensionVejez: \$${result.cuantiaTotalPensionVejez.toStringAsFixed(2)} (Excel: 1,044,084.77)');
    print('  asignacionEsposa:         \$${result.asignacionEsposa.toStringAsFixed(2)} (Excel: 141,092.54)');
    print('  asignacionHijos:          \$${result.asignacionHijos.toStringAsFixed(2)} (Excel: 94,061.69)');
    print('  cuantiaTotalAsignaciones: \$${result.cuantiaTotalAsignaciones.toStringAsFixed(2)} (Excel: 208,816.95)');
    print('  totalAyudaAsistencial:    \$${result.totalAyudaAsistencial.toStringAsFixed(2)} (Excel: 0.00)');
    print('  cuantiaMasAsignaciones:   \$${result.cuantiaMasAsignaciones.toStringAsFixed(2)} (Excel: 1,252,901.72)');
    print('  asignacionDecreto:        \$${result.asignacionDecretoPresidencial.toStringAsFixed(2)} (Excel: 137,819.19)');
    print('  totalPensionAnual:        \$${result.totalPensionAnual.toStringAsFixed(2)} (Excel: 1,044,084.77)');
    print('  totalPensionMensual:      \$${result.totalPensionMensual.toStringAsFixed(2)} (Excel: 87,007.06)');
    print('=================================');

    // ASSERTIONS contra Excel
    expect(result.cuantiaTotalPensionVejez, closeTo(1044084.77, 1.0));
    expect(result.cuantiaTotalAsignaciones, closeTo(208816.95, 1.0));
    expect(result.totalPensionAnual, closeTo(1044084.77, 1.0));
    expect(result.totalPensionMensual, closeTo(87007.06, 0.1));
  });
}
