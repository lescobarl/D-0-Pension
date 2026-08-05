// TEST: VALIDACIÓN DEL FIX "Pensión Actual (sin M40) usa 1960 semanas (no 1908)".
//
// Este test valida a nivel PROVIDER (RetroactiveProvider) el modelo semántico
// implementado:
//
//   - `semanasCotizadas` = historial IMSS ANTES de Modalidad 40 (= 1960),
//     alineado con `semanasAntesMod40` y `totalSemanasSinMod40`.
//   - El total CON Modalidad 40 (= antes + en) lo calcula el
//     RetroactiveCalculator en recalcularFactAsig; NO se resta semanasEnMod40.
//   - Sin M40: 1960 semanas → 28 incrementos → $62,856.64/mes (Excel).
//   - Con M40: 1960 + 78 = 2038 semanas → 30 incrementos → $78,189.67/mes.
//   - Incremento: $15,333.03/mes (24.39%).
//
// Escenario (idéntico a verificar_escenario_usuario_test.dart):
//   Fecha Nacimiento 30/01/1969, Edad Retiro 60.51 (Año 2029),
//   UMA 128.11, SM 372.04, Salario Promedio 250 sem $2,281.53,
//   Salario Promedio (con M40) $2,677.31, Semanas antes M40 1960,
//   Semanas en M40 78, Esposa SÍ, Hijos 1, Padres 0.

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
    // Reset del mock store entre tests para evitar contaminación cruzada.
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    persistence = PersistenceService(prefs);
    provider = RetroactiveProvider(
      evaluator: evaluator,
      persistence: persistence,
    );
    await provider.initialize();
  });

  // Aplica el escenario completo con el ORDEN DETERMINISTA verificado:
  // 1) fechaNacimiento (recalcula pensionYear, proyecta UMA/SM + salarioRegistrado)
  // 2) edadRetiro (snap a la rejilla, pensionYear = 1969 + 60 = 2029, proyecta UMA/SM)
  // 3) pensionYear (no-op de refuerzo)
  // 4) UMA/SM capturados (después de las proyecciones forzadas)
  // 5) salarioPromedio250Semanas (actualiza periodos no-M40)
  // 6) salarioDiarioPromedio manual → diverge → salarioPromAutoCalculado=false
  //    (preserva 2677.31)
  // 7) semanasCotizadas = 1960 (alinea los 3 campos, NO resta M40)
  // 8) semanasEnMod40 = 78 (desglose-first, preserva 1960 vía _reconcileTotalSemanas)
  // 9) esposa/hijos/padres.
  Future<void> aplicarEscenario() async {
    provider.setFechaNacimiento(DateTime(1969, 1, 30));
    await provider.setEdadRetiro(60.51);
    provider.setPensionYear(2029);
    provider.setUmaDiaria(128.11);
    provider.setSalarioMinimoDiario(372.04);
    provider.setSalarioPromedio250Semanas(2281.53);
    provider.setSalarioDiarioPromedio(2677.31);
    provider.setSemanasCotizadas(1960);
    provider.setSemanasEnMod40(78);
    provider.setTieneEsposa(true);
    provider.setNumeroHijos(1);
    provider.setNumeroPadres(0);
  }

  test('MODELO SEMÁNTICO — semanasCotizadas(1960) alinea los 3 campos y M40 NO lo incrementa', () async {
    await aplicarEscenario();

    print('\n=== MODELO SEMÁNTICO (fix 1960 semanas) ===');
    print('  semanasCotizadas:        ${provider.semanasCotizadas}');
    print('  totalSemanasSinMod40:    ${provider.totalSemanasSinMod40}');
    print('  semanasAntesMod40:       ${provider.semanasAntesMod40}');
    print('  semanasEnMod40:          ${provider.semanasEnMod40}');

    // Los 3 campos del historial ANTES de M40 están alineados en 1960.
    expect(provider.semanasCotizadas, 1960,
        reason: 'semanasCotizadas debe ser el historial ANTES de M40 (= 1960)');
    expect(provider.totalSemanasSinMod40, 1960,
        reason: 'totalSemanasSinMod40 debe alinearse con 1960');
    expect(provider.semanasAntesMod40, 1960.0,
        reason: 'semanasAntesMod40 debe alinearse con 1960.0');

    // El desglose de M40 (78 semanas) NO incrementa el historial IMSS.
    expect(provider.semanasEnMod40, 78.0,
        reason: 'semanasEnMod40 = 78 (2024-2025)');
  });

  test('CONFIG — edadRetiro(60.51) fija año 2029 y UMA/SM capturados', () async {
    await aplicarEscenario();

    print('\n=== CONFIG ===');
    print('  fechaNacimiento:  ${provider.fechaNacimiento}');
    print('  edadRetiro:       ${provider.edadRetiro}');
    print('  pensionYear:      ${provider.pensionYear}');
    print('  umaDiaria:        ${provider.umaDiaria}');
    print('  salarioMinimoDiario: ${provider.salarioMinimoDiario}');

    expect(provider.edadRetiro, 60.51);
    expect(provider.pensionYear, 2029,
        reason: '1969 + 60 (floor de 60.51) = 2029');
    expect(provider.umaDiaria, closeTo(128.11, 0.01));
    expect(provider.salarioMinimoDiario, closeTo(372.04, 0.01));
  });

  test('FIX — Sin-M40 usa 1960 semanas → 28 incrementos → \$62,856.64/mes', () async {
    await aplicarEscenario();

    final sin = provider.factAsigSinMod40Calculation;
    expect(sin, isNotNull, reason: 'factAsigSinMod40Calculation debe estar calculada');
    if (sin == null) return;

    print('\n=== FIX: PENSIÓN SIN M40 (1960 semanas) ===');
    print('  numeroIncrementos (bruto): ${sin.numeroIncrementosAnuales}');
    print('  numeroIncrementos (redondeado): ${sin.numeroIncrementosRedondeado}');
    print('  salarioEnUMAs:       ${sin.salarioEnUMAs}');
    print('  cuantiaTotalPensionVejez: \$${sin.cuantiaTotalPensionVejez.toStringAsFixed(2)}');
    print('  TOTAL PENSION ANUAL: \$${sin.totalPensionAnual.toStringAsFixed(2)}');
    print('  TOTAL PENSION MENSUAL:\$${sin.totalPensionMensual.toStringAsFixed(2)}');

    // 1960 semanas → (1960-500)/52 = 28.08 → redondeo → 28 incrementos.
    expect(sin.numeroIncrementosRedondeado, closeTo(28, 0.001),
        reason: '1960 semanas → 28 incrementos (antes: 1908 → 27)');

    // Excel: Anual $754,279.67, Mensual $62,856.64.
    expect(sin.totalPensionAnual, closeTo(754279.67, 1));
    expect(sin.totalPensionMensual, closeTo(62856.64, 1));
  });

  test('FIX — Con-M40 usa 1960+78=2038 semanas → 30 incrementos → \$78,189.67/mes', () async {
    await aplicarEscenario();

    final fact = provider.factAsigCalculation;
    final pension = provider.pensionMod40Calculation;
    final sin = provider.factAsigSinMod40Calculation;
    expect(fact, isNotNull);
    expect(pension, isNotNull);
    expect(sin, isNotNull);
    if (fact == null || pension == null || sin == null) return;

    print('\n=== FIX: PENSIÓN CON M40 (1960 + 78 = 2038 semanas) ===');
    print('  numeroIncrementos (bruto): ${fact.numeroIncrementosAnuales}');
    print('  numeroIncrementos (redondeado): ${fact.numeroIncrementosRedondeado}');
    print('  cuantiaTotalPensionVejez: \$${fact.cuantiaTotalPensionVejez.toStringAsFixed(2)}');
    print('  porcentajePorEdad: ${pension.porcentajePorEdad}');
    print('  pensionAnualFinal: \$${pension.pensionAnualFinal.toStringAsFixed(2)}');
    print('  pensionMensual:    \$${pension.pensionMensual.toStringAsFixed(2)}');
    final incremento = pension.pensionMensual - sin.totalPensionMensual;
    final pct = (incremento / sin.totalPensionMensual) * 100;
    print('  INCREMENTO:        \$${incremento.toStringAsFixed(2)}/mes (${pct.toStringAsFixed(2)}%)');

    // 2038 semanas → (2038-500)/52 = 29.577 → floor 29, frac 0.577 ≥ 27/52 → 30.
    expect(fact.numeroIncrementosRedondeado, closeTo(30, 0.001),
        reason: '2038 semanas → 30 incrementos');

    // Excel: Anual $938,276.01, Mensual $78,189.67, Incremento $15,333.03 (24.39%).
    expect(pension.pensionAnualFinal, closeTo(938276.01, 1));
    expect(pension.pensionMensual, closeTo(78189.67, 1));
    expect(incremento, closeTo(15333.03, 1));
    expect(pct, closeTo(24.39, 0.1));
  });
}
