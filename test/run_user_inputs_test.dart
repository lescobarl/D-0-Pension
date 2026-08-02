// Test to calculate pension with user's specific inputs
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/engine/formula_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Calculate pension with user inputs', () async {
    final evaluator = FormulaEvaluator();
    await evaluator.initialize();

    // User's exact inputs
    final salarioDiarioPromedio = 2677.31;
    final umaDiaria = 122.59;
    final salarioMinimoDiario = 372.04;
    final pensionYear = 2029;
    final semanasCotizadas = 2038;
    final tieneEsposa = true;
    final numeroHijos = 1;
    final numeroPadres = 0;
    final edadRetiro = 60.51;

    print('\n========== USER SCENARIO ==========');
    print('Inputs:');
    print('  salarioDiarioPromedio: $salarioDiarioPromedio');
    print('  umaDiaria: $umaDiaria');
    print('  salarioMinimoDiario: $salarioMinimoDiario');
    print('  pensionYear: $pensionYear');
    print('  semanasCotizadas: $semanasCotizadas');
    print('  tieneEsposa: $tieneEsposa');
    print('  numeroHijos: $numeroHijos');
    print('  edadRetiro: $edadRetiro');

    // Calculate Fact+Asig
    final factAsig = evaluator.calculateFactAsig(
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

    // Calculate Pension Mod 40
    final pensionMod40 = evaluator.calculatePensionMod40(
      pensionAnual100: factAsig.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: pensionYear,
      cuantiaTotalAsignaciones: factAsig.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: factAsig.totalAyudaAsistencial,
    );

    print('\n--- FACT. + ASIG. MOD.40 ---');
    print('  salarioEnUMAs: ${factAsig.salarioEnUMAs}');
    print('  porcentajeCuantiaBasica: ${factAsig.porcentajeCuantiaBasica}');
    print('  totalCuantiaBasicaAnual: ${factAsig.totalCuantiaBasicaAnual.toStringAsFixed(4)}');
    print('  numeroIncrementosRedondeado: ${factAsig.numeroIncrementosRedondeado}');
    print('  totalIncrementosAnuales: ${factAsig.totalIncrementosAnuales.toStringAsFixed(4)}');
    print('  cuantiaTotalPensionVejez: ${factAsig.cuantiaTotalPensionVejez.toStringAsFixed(4)}');
    print('  asignacionEsposa: ${factAsig.asignacionEsposa.toStringAsFixed(4)}');
    print('  asignacionHijos: ${factAsig.asignacionHijos.toStringAsFixed(4)}');
    print('  cuantiaTotalAsignaciones: ${factAsig.cuantiaTotalAsignaciones.toStringAsFixed(4)}');
    print('  totalAyudaAsistencial: ${factAsig.totalAyudaAsistencial.toStringAsFixed(4)}');
    print('  totalPensionAnual: ${factAsig.totalPensionAnual.toStringAsFixed(4)}');
    print('  totalPensionMensual: ${factAsig.totalPensionMensual.toStringAsFixed(4)}');

    print('\n--- PENSION MOD. 40 ---');
    print('  edadEntera: ${edadRetiro.floorToDouble()}');
    print('  porcentajePorEdad: ${pensionMod40.porcentajePorEdad}');
    print('  pensionAnualFinal: ${pensionMod40.pensionAnualFinal.toStringAsFixed(4)}');
    print('  pensionMensual: ${pensionMod40.pensionMensual.toStringAsFixed(4)}');

    print('\n========== RESULTADO FINAL ==========');
    print('PENSIÓN MENSUAL CON MOD40: \$${pensionMod40.pensionMensual.toStringAsFixed(2)}');
    print('PENSIÓN ANUAL CON MOD40: \$${pensionMod40.pensionAnualFinal.toStringAsFixed(2)}');
  });
}
