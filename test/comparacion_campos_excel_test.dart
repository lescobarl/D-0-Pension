// TEST: Comparar App vs Excel campo por campo para el escenario actual del Excel
//
// INPUTS (idénticos App y Excel):
// - salario_diario_promedio = 2897.1698986857136
// - uma_diaria = 128.10545274999998
// - salario_minimo = 393.2472081334349
// - edad_retiro = 61.5
// - semanas_cotizadas = 2090 (2090.29 truncado)
//
// VALORES ESPERADOS DEL EXCEL:
// C7 (salarioUMAs) = 22.62
// C13 (cuantiaBasicaDiaria) = 376.6320868291428
// C15 (cuantiaBasicaAnual) = 152592.48997882722
// C20 (tasaIncremento) = 0.0245
// C21 (incrementoDiario) = 70.98066251779998
// C23 (incrementoAnual) = 25907.941818996995
// C24 (numIncrementosTeorico) = 30.58241758241758
// C25 (numIncrementosRedondeado) = 31
// C26 (totalIncrementosAnual) = 891492.2779916866
// C30 (cuantiaTotalPensionVejez) = 1044084.7679705138
// C36 (asignacionEsposa) = 141092.5362122316
// C43 (asignacionHijos) = 94061.6908081544
// B53 (totalAsignaciones) = 208816.95359410276
// B63 (cuantiaMasAsignaciones) = 1252901.7215646165
// C69 (asignacionDecreto) = 137819.18937210782
// C72 (totalPensionAnual) = 1044084.7679705138
// C74 (totalPensionMensual) = 87007.06399754282

import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('COMPARACIÓN CAMPO POR CAMPO: Escenario actual del Excel', () {
    // Inputs EXACTOS del Excel
    final result = evaluator.calculateFactAsig(
      salarioDiarioPromedio: 2897.1698986857136,
      umaDiaria: 128.10545274999998,
      salarioMinimoDiario: 393.2472081334349,
      pensionYear: 2030,
      semanasCotizadas: 2090,
      tieneEsposa: true,
      numeroHijos: 1,
      numeroPadres: 0,
      edadRetiro: 61.5,
    );

    print('\n╔═══════════════════════════════════════════════════════════════╗');
    print('║ COMPARACIÓN CAMPO POR CAMPO: App vs Excel                   ║');
    print('╠═══════════════════════════════════════════════════════════════╣');

    // Comparación campo por campo
    void check(String name, double app, double excel) {
      final diff = (app - excel).abs();
      final status = diff < 0.01 ? '✅' : '❌';
      print('║ $status $name:');
      print('║     App   = ${app.toStringAsFixed(4).padLeft(15)}');
      print('║     Excel = ${excel.toStringAsFixed(4).padLeft(15)}');
      print('║     Diff  = ${diff.toStringAsFixed(4).padLeft(15)}');
    }

    check('C7  salarioEnUMAs', result.salarioEnUMAs, 22.62);
    check('C13 cuantiaBasicaPorDia', result.cuantiaBasicaPorDia, 376.6320868291428);
    check('C15 totalCuantiaBasicaAnual', result.totalCuantiaBasicaAnual, 152592.48997882722);
    check('C21 incrementoDiario', result.incrementosDiarios, 70.98066251779998);
    check('C23 incrementoAnual', result.incrementoAnual, 25907.941818996995);
    check('C24 numIncrementosTeorico', result.numeroIncrementosAnuales, 30.58241758241758);
    check('C25 numIncrementosRedond', result.numeroIncrementosRedondeado, 31.0);
    check('C26 totalIncrementosAnual', result.totalIncrementosAnuales, 891492.2779916866);
    check('C30 cuantiaTotalPensionVejez', result.cuantiaTotalPensionVejez, 1044084.7679705138);
    check('C36 asignacionEsposa', result.asignacionEsposa, 141092.5362122316);
    check('C43 asignacionHijos', result.asignacionHijos, 94061.6908081544);
    check('B53 cuantiaTotalAsignaciones', result.cuantiaTotalAsignaciones, 208816.95359410276);
    check('B63 cuantiaMasAsignaciones', result.cuantiaMasAsignaciones, 1252901.7215646165);
    check('C69 asignacionDecreto', result.asignacionDecretoPresidencial, 137819.18937210782);
    check('C72 totalPensionAnual', result.totalPensionAnual, 1044084.7679705138);
    check('C74 totalPensionMensual', result.totalPensionMensual, 87007.06399754282);

    print('╚═══════════════════════════════════════════════════════════════╝');

    // ASSERTIONS
    expect(result.salarioEnUMAs, closeTo(22.62, 0.01));
    expect(result.cuantiaBasicaPorDia, closeTo(376.6321, 0.01));
    expect(result.totalCuantiaBasicaAnual, closeTo(152592.49, 0.1));
    expect(result.totalIncrementosAnuales, closeTo(891492.28, 0.1));
    expect(result.cuantiaTotalPensionVejez, closeTo(1044084.77, 0.1));
    expect(result.asignacionEsposa, closeTo(141092.54, 0.1));
    expect(result.asignacionHijos, closeTo(94061.69, 0.1));
    expect(result.cuantiaTotalAsignaciones, closeTo(208816.95, 0.1));
    expect(result.cuantiaMasAsignaciones, closeTo(1252901.72, 0.1));
    expect(result.asignacionDecretoPresidencial, closeTo(137819.19, 0.1));
    expect(result.totalPensionAnual, closeTo(1044084.77, 0.1));
    expect(result.totalPensionMensual, closeTo(87007.06, 0.1));
  });
}
