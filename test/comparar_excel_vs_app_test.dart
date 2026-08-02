import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

/// COMPARACIÓN DIRECTA: Motor de la App vs Excel
///
/// Toma el escenario del Excel (FACT. + ASIG. MOD.40 sheet)
/// y ejecuta el mismo cálculo en el motor de la app,
/// comparando CADA CAMPO individualmente.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('COMPARAR App vs Excel - FACT + ASIG MOD.40', () {
    final rules = evaluator.metadata.financialRules;

    // INPUTS - Mismos que el Excel
    const salarioDiarioPromedio = 2840.6157121429;  // C4
    const umaDiaria = 122.58895;                     // C5
    const salarioMinimoDiario = 372.0408780827;      // C6
    const pensionYear = 2029;                        // G4
    const semanasCotizadas = 2095;                   // DATOS GEN C16
    const tieneEsposa = false;                       // C8 = "NO"
    const numeroHijos = 1;                           // C9
    const numeroPadres = 0;                          // C10
    const edadRetiro = 61.0;                           // D14 (PENSION MOD.40)

    print('\n══════════════════════════════════════════════════════════════════════════════');
    print('COMPARACIÓN: Motor App vs Excel');
    print('Escenario: FACT. + ASIG. MOD.40 (Excel sheet)');
    print('══════════════════════════════════════════════════════════════════════════════');

    print('\n📥 INPUTS:');
    print('  salarioDiarioPromedio: $salarioDiarioPromedio');
    print('  umaDiaria: $umaDiaria');
    print('  salarioMinimoDiario: $salarioMinimoDiario');
    print('  pensionYear: $pensionYear');
    print('  semanasCotizadas: $semanasCotizadas');
    print('  tieneEsposa: $tieneEsposa');
    print('  numeroHijos: $numeroHijos');
    print('  numeroPadres: $numeroPadres');
    print('  edadRetiro: $edadRetiro');

    // EJECUTAR el motor de la app
    print('\n⚙️  EJECUTANDO MOTOR APP...');
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

    // VALORES DEL EXCEL
    print('\n📊 COMPARACIÓN CAMPO POR CAMPO:');
    print('  ───────────────────────────────────────────────────────────────────────────────');
    print('  ${"Campo".padRight(35)} ${"App".padRight(18)} ${"Excel".padRight(18)} ${"Estado"}');
    print('  ───────────────────────────────────────────────────────────────────────────────');

    final comparisons = <_Comparison>[
      _Comparison('salarioEnUMAs', result.salarioEnUMAs, 23.17),
      _Comparison('porcentajeCuantiaBasica', result.porcentajeCuantiaBasica, 0.13),
      _Comparison('cuantiaBasicaPorDia', result.cuantiaBasicaPorDia, 369.28),
      _Comparison('totalCuantiaBasicaAnual', result.totalCuantiaBasicaAnual, 149613.81),
      _Comparison('porcentajeIncremento', result.porcentajeIncremento, 0.0245),
      _Comparison('incrementoAnual', result.incrementoAnual, 25402.21),
      _Comparison('numeroIncrementosAnuales', result.numeroIncrementosAnuales, 30.6675),
      _Comparison('numeroIncrementosRedondeado', result.numeroIncrementosRedondeado, 31.0),
      _Comparison('totalIncrementosAnuales', result.totalIncrementosAnuales, 874089.91),
      _Comparison('cuantiaTotalPensionVejez', result.cuantiaTotalPensionVejez, 1023703.72),
      _Comparison('asignacionEsposa', result.asignacionEsposa, 0.0),
      _Comparison('asignacionHijos', result.asignacionHijos, 92225.56),
      _Comparison('asignacionPadres', result.asignacionPadres, 0.0),
      _Comparison('cuantiaTotalAsignaciones', result.cuantiaTotalAsignaciones, 81896.30),
      _Comparison('totalAyudaAsistencial', result.totalAyudaAsistencial, 0.0),
      _Comparison('totalPensionAnual', result.totalPensionAnual, 900859.27),
      _Comparison('totalPensionMensual', result.totalPensionMensual, 75071.61),
    ];

    int okCount = 0;
    int failCount = 0;

    for (final c in comparisons) {
      final diff = (c.appValue - c.excelValue).abs();
      final isOk = diff < 0.1;
      if (isOk) {
        okCount++;
      } else {
        failCount++;
      }

      print('  ${c.name.padRight(35)} '
          '${c.appValue.toStringAsFixed(4).padLeft(14)} '
          '${c.excelValue.toStringAsFixed(4).padLeft(14)} '
          '${isOk ? "✅" : "❌"} (diff: ${diff.toStringAsFixed(4)})');
    }

    // PENSIÓN MOD.40
    print('\n📊 PENSIÓN MOD.40:');
    final pension = evaluator.calculatePensionMod40(
      pensionAnual100: result.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      cuantiaTotalAsignaciones: result.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: result.totalAyudaAsistencial,
    );

    final pensComparisons = [
      _Comparison('porcentajePorEdad', pension.porcentajePorEdad, 0.80),
      _Comparison('pensionAnual100', pension.pensionAnual100, 1023703.72),
      _Comparison('pensionMinimaGarantizada', pension.pensionMinimaGarantizada, 150732.36),
      _Comparison('aplicaMinima', pension.aplicaMinima ? 1.0 : 0.0, 0.0),
      _Comparison('pensionAnualFinal', pension.pensionAnualFinal, 900859.27),
      _Comparison('pensionMensual', pension.pensionMensual, 75071.61),
    ];

    for (final c in pensComparisons) {
      final diff = (c.appValue - c.excelValue).abs();
      final isOk = diff < 0.1;
      if (isOk) {
        okCount++;
      } else {
        failCount++;
      }
      print('  ${c.name.padRight(35)} '
          '${c.appValue.toStringAsFixed(4).padLeft(14)} '
          '${c.excelValue.toStringAsFixed(4).padLeft(14)} '
          '${isOk ? "✅" : "❌"} (diff: ${diff.toStringAsFixed(4)})');
    }

    // RESUMEN
    print('\n' + '═' * 80);
    print('RESUMEN: ${okCount + failCount} campos comparados');
    print('  ✅ OK:   $okCount');
    if (failCount > 0) {
      print('  ❌ FAIL: $failCount');
    } else {
      print('  🎉 TODOS LOS CAMPOS COINCIDEN CON EL EXCEL');
    }
    print('═' * 80);

    // ASSERTIONS - los campos clave deben coincidir
    expect((result.totalPensionMensual - 75071.61).abs(), lessThan(0.1));
    expect((pension.pensionMensual - 75071.61).abs(), lessThan(0.1));
    expect(pension.porcentajePorEdad, 0.80);
  });
}

class _Comparison {
  final String name;
  final double appValue;
  final double excelValue;
  _Comparison(this.name, this.appValue, this.excelValue);
}
