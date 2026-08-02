// Test diagnóstico: replica el escenario ACTUAL de la app
import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('DIAGNOSTICO - Pensión SIN M40 con edad 60.51', () {
    final pensionYear = 2030;
    final salarioPromedio250 = 2281.5311;

    print('\n══════ PROBANDO EDAD 60.51 PARA SIN M40 ══════');

    // Caso A: edad 60.0 (como el Excel del usuario)
    final casoA = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioPromedio250,
      umaDiaria: 128.10545275,
      salarioMinimoDiario: 393.2472081334,
      pensionYear: pensionYear,
      semanasCotizadas: 1960,
      tieneEsposa: false,
      numeroHijos: 1,
      numeroPadres: 0,
      edadRetiro: 60.0,
    );
    print('─── Caso A: edad 60.0 ───');
    print('  cuantiaTotalPensionVejez: ${casoA.cuantiaTotalPensionVejez}');
    print('  totalPensionAnual:        ${casoA.totalPensionAnual}');
    print('  totalPensionMensual:      ${casoA.totalPensionMensual}');

    // Caso B: edad 60.51
    final casoB = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioPromedio250,
      umaDiaria: 128.10545275,
      salarioMinimoDiario: 393.2472081334,
      pensionYear: pensionYear,
      semanasCotizadas: 1960,
      tieneEsposa: false,
      numeroHijos: 1,
      numeroPadres: 0,
      edadRetiro: 60.51,
    );
    print('─── Caso B: edad 60.51 ───');
    print('  cuantiaTotalPensionVejez: ${casoB.cuantiaTotalPensionVejez}');
    print('  totalPensionAnual:        ${casoB.totalPensionAnual}');
    print('  totalPensionMensual:      ${casoB.totalPensionMensual}');

    // Pensión mod40 con edad 60.51
    final mod40 = evaluator.calculatePensionMod40(
      pensionAnual100: casoB.cuantiaTotalPensionVejez,
      edadRetiro: 60.51,
      salarioMinimoDiario: 393.2472081334,
      cuantiaTotalAsignaciones: casoB.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: casoB.totalAyudaAsistencial,
    );
    print('─── PENSION MOD.40 con edad 60.51 ───');
    print('  porcentajePorEdad: ${mod40.porcentajePorEdad}');
    print('  pensionAnual100:   ${mod40.pensionAnual100}');
    print('  pensionAnualFinal: ${mod40.pensionAnualFinal}');
    print('  pensionMensual:    ${mod40.pensionMensual}');

    print('\n══════ APP MUESTRA ══════');
    print('Pensión CON M40: \$74,457.31 (mensual)');
    print('Pensión SIN M40: \$55,313.84 (mensual)');
  });
}
