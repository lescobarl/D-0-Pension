// TEST: Valida que el App produce resultados consistentes con el motor
// y que el JSON se carga correctamente.
//
// NOTA: Este test NO valida valores hardcodeados específicos del Excel
// porque los valores del JSON pueden cambiar. En su lugar, valida:
// 1. Que el JSON se carga correctamente
// 2. Que el motor produce resultados consistentes entre sí
// 3. Que los valores están en rangos esperados

import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;
  late SharedPreferences prefs;
  late PersistenceService persistence;
  late RetroactiveProvider provider;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  setUp(() async {
    prefs = await SharedPreferences.getInstance();
    persistence = PersistenceService(prefs);
    provider = RetroactiveProvider(
      evaluator: evaluator,
      persistence: persistence,
    );
    await provider.initialize();
  });

  test('CONSISTENCIA: App engine produces consistent results', () async {
    print('\n=== APP DEFAULTS - CONSISTENCY CHECK ===');

    // 1. JSON se carga correctamente
    final salarioCargado = provider.salarioDiarioPromedio;
    final edadCargada = provider.edadRetiro;
    final semanasCargadas = provider.semanasCotizadas;
    final pensionYear = provider.pensionYear;

    print('Salario diario: $salarioCargado');
    print('Edad retiro: $edadCargada');
    print('Semanas: $semanasCargadas');
    print('Pension year: $pensionYear');

    expect(salarioCargado, greaterThan(0));
    expect(edadCargada, greaterThan(0));
    expect(semanasCargadas, greaterThan(0));
    expect(pensionYear, greaterThan(2020));

    // 2. El motor produce resultados consistentes
    final fact = provider.factAsigCalculation;
    expect(fact, isNotNull, reason: 'FactAsigCalculation debe estar calculada');

    if (fact != null) {
      // C7: Salario en UMAs = C4/C5 redondeado
      final expectedUMAs =
          (salarioCargado / provider.umaDiaria * 100).roundToDouble() / 100;
      expect(fact.salarioEnUMAs, closeTo(expectedUMAs, 0.01));
      print('C7 salarioEnUMAs: ${fact.salarioEnUMAs} (expected: $expectedUMAs)');

      // C13: Cuantía básica diaria = C4 * C12
      final expectedC13 = salarioCargado * fact.porcentajeCuantiaBasica;
      expect(fact.cuantiaBasicaPorDia, closeTo(expectedC13, 0.01));
      print('C13 cuantiaBasicaPorDia: ${fact.cuantiaBasicaPorDia}');

      // C15: Total cuantía básica anual = C13 * 365 * 1.11
      final expectedC15 = fact.cuantiaBasicaPorDia * 365 * 1.11;
      expect(fact.totalCuantiaBasicaAnual, closeTo(expectedC15, 0.01));
      print('C15 totalCuantiaBasicaAnual: ${fact.totalCuantiaBasicaAnual}');

      // C23: Incremento anual = C21 * 365
      final expectedC23 = fact.incrementosDiarios * 365;
      expect(fact.incrementoAnual, closeTo(expectedC23, 0.01));
      print('C23 incrementoAnual: ${fact.incrementoAnual}');

      // C26: Total incrementos anual = C23 * C25 * 1.11
      final expectedC26 = fact.incrementoAnual *
          fact.numeroIncrementosRedondeado *
          1.11;
      expect(fact.totalIncrementosAnuales, closeTo(expectedC26, 0.01));
      print('C26 totalIncrementosAnuales: ${fact.totalIncrementosAnuales}');

      // C30: Cuantía total pensión vejez = C15 + C26
      final expectedC30 = fact.totalCuantiaBasicaAnual +
          fact.totalIncrementosAnuales;
      expect(fact.cuantiaTotalPensionVejez, closeTo(expectedC30, 0.01));
      print('C30 cuantiaTotalPensionVejez: ${fact.cuantiaTotalPensionVejez}');

      // Rangos esperados (valores razonables)
      expect(fact.cuantiaTotalPensionVejez, greaterThan(500000));
      expect(fact.cuantiaTotalPensionVejez, lessThan(5000000));
      expect(fact.cuantiaTotalAsignaciones, greaterThan(0));
      expect(fact.totalPensionMensual, greaterThan(30000));
      expect(fact.totalPensionMensual, lessThan(200000));
    }

    // 3. PENSION MOD 40 es consistente
    final pension = provider.pensionMod40Calculation;
    expect(pension, isNotNull);

    if (pension != null && fact != null) {
      // D12 = C30
      expect(pension.pensionAnual100, closeTo(fact.cuantiaTotalPensionVejez, 0.01));
      print('D12 pensionAnual100: ${pension.pensionAnual100}');

      // C23 = C72
      expect(pension.pensionAnualFinal, closeTo(fact.totalPensionAnual, 0.01));
      print('C23 pensionAnualFinal: ${pension.pensionAnualFinal}');

      // C26 = C74
      expect(pension.pensionMensual, closeTo(fact.totalPensionMensual, 0.01));
      print('C26 pensionMensual: ${pension.pensionMensual}');

      // Porcentaje por edad debe ser razonable
      expect(pension.porcentajePorEdad, greaterThanOrEqualTo(0.5));
      expect(pension.porcentajePorEdad, lessThanOrEqualTo(1.0));
    }

    // 4. COSTO MOD 40 produce valores razonables
    final costo = provider.costoMod40Calculation;
    expect(costo, isNotNull);
    if (costo != null) {
      expect(costo.inversionTotal, greaterThan(0));
      expect(costo.recuperacionAfore, greaterThan(0));
      expect(costo.inversionNeta, greaterThan(0));
    }

    // 5. INVERSION produce valores razonables
    final inv = provider.inversionCalculation;
    expect(inv, isNotNull);
    if (inv != null) {
      expect(inv.pensionMensualSinMod40, greaterThan(0));
      expect(inv.pensionMensualConMod40, greaterThan(0));
      expect(inv.gananciaTotal, greaterThan(0));
    }

    print('=== ALL CONSISTENCY CHECKS PASSED ===');
  });
}
