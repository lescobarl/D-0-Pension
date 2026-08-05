import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

/// ESCENARIO DEL USUARIO:
/// Fecha Cálculo: 21/07/2026
/// Fecha Nacimiento: 30/01/1969
/// Salario Promedio 250 sem (anterior): $2,281.53
/// Nuevo Salario Promedio (con M40): $2,677.31
/// Semanas antes Mod40: 1960
/// Edad Retiro: 60.51 años
/// Esposa: SÍ, Hijos: 1, Padres: 0
/// Inicio Mod40: 21/07/2026, Fin: 21/07/2027
/// Semanas en Mod40: 78
/// Salario Registrado Mod40: $3,202.64
/// UMA Diaria: $128.11
/// Salario Mínimo Diario: $372.04
/// Año de Pensión: 2029
///
/// Outputs esperados:
/// Pensión sin Mod40: Anual $754,279.67, Mensual $62,856.64
/// Pensión con Mod40: Anual $938,276.01, Mensual $78,189.67
/// Incremento: $15,333.03/mes, 24.39%
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('ESCENARIO USUARIO - Pensión con M40', () {
    // ===== INPUTS =====
    const salarioDiarioPromedio = 2677.31; // Nuevo Salario Promedio (con M40)
    const salarioPromedio250 = 2281.53; // Salario promedio 250 sem (sin M40)
    const umaDiaria = 128.11;
    const salarioMinimoDiario = 372.04;
    const pensionYear = 2029;
    const semanasCotizadas = 2038; // 1960 + 78
    const totalSemanasSinMod40 = 1960;
    const tieneEsposa = true;
    const numeroHijos = 1;
    const numeroPadres = 0;
    const edadRetiro = 60.51;

    print('╔══════════════════════════════════════════════════════════════════╗');
    print('║     VERIFICACIÓN ESCENARIO USUARIO - PENSIÓN CON M40           ║');
    print('╚══════════════════════════════════════════════════════════════════╝');
    print('');

    // ===== FACT + ASIG (CON MOD40) =====
    print('─────────── FACT + ASIG (CON MOD40) ───────────');
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

    print('  salarioEnUMAs:           ${fact.salarioEnUMAs}');
    print('  cuantiaBasicaPorDia:     \$${fact.cuantiaBasicaPorDia.toStringAsFixed(4)}');
    print('  totalCuantiaBasicaAnual: \$${fact.totalCuantiaBasicaAnual.toStringAsFixed(2)}');
    print('  porcentajeIncremento:    ${fact.porcentajeIncremento}');
    print('  incrementosDiarios:      \$${fact.incrementosDiarios.toStringAsFixed(4)}');
    print('  incrementoAnual:         \$${fact.incrementoAnual.toStringAsFixed(2)}');
    print('  numeroIncrementos:       ${fact.numeroIncrementosAnuales} (redondeado: ${fact.numeroIncrementosRedondeado})');
    print('  totalIncrementosAnuales: \$${fact.totalIncrementosAnuales.toStringAsFixed(2)}');
    print('  cuantiaTotalPensionVejez:\$${fact.cuantiaTotalPensionVejez.toStringAsFixed(2)}');
    print('  asignacionEsposa:        \$${fact.asignacionEsposa.toStringAsFixed(2)}');
    print('  asignacionHijos:         \$${fact.asignacionHijos.toStringAsFixed(2)}');
    print('  cuantiaTotalAsignaciones:\$${fact.cuantiaTotalAsignaciones.toStringAsFixed(2)}');
    print('  ayudaAsistencial:        \$${fact.totalAyudaAsistencial.toStringAsFixed(2)}');
    print('  decretoPresidencial:     \$${fact.asignacionDecretoPresidencial.toStringAsFixed(2)}');
    print('  TOTAL PENSION ANUAL:     \$${fact.totalPensionAnual.toStringAsFixed(2)}');
    print('  TOTAL PENSION MENSUAL:   \$${fact.totalPensionMensual.toStringAsFixed(2)}');
    print('');

    // ===== PENSION MOD 40 =====
    print('─────────── PENSIÓN MOD 40 ───────────');
    final pension = evaluator.calculatePensionMod40(
      pensionAnual100: fact.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: pensionYear,
      cuantiaTotalAsignaciones: fact.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: fact.totalAyudaAsistencial,
    );

    print('  pensionAnual100:         \$${pension.pensionAnual100.toStringAsFixed(2)}');
    print('  porcentajePorEdad:       ${pension.porcentajePorEdad}');
    print('  tipoPension:             ${pension.tipoPension}');
    print('  pensionMinimaGarantizada:\$${pension.pensionMinimaGarantizada.toStringAsFixed(2)}');
    print('  aplicaMinima:            ${pension.aplicaMinima}');
    print('  pensionAnualFinal:       \$${pension.pensionAnualFinal.toStringAsFixed(2)}');
    print('  pensionMensual:          \$${pension.pensionMensual.toStringAsFixed(2)}');
    print('');

    // ===== FACT + ASIG (SIN MOD40) =====
    print('─────────── FACT + ASIG (SIN MOD40) ───────────');
    // Usar edad redondeada según regla de metadata
    final rules = evaluator.metadata.financialRules;
    final edadEntera = rules.edadRoundingRule.roundToInteger(edadRetiro);
    print('  edadRetiro original:     $edadRetiro');
    print('  edadRetiro redondeada:   $edadEntera (threshold: ${rules.edadRoundingRule.sixMonthsThreshold})');

    final factSinMod40 = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioPromedio250,
      umaDiaria: umaDiaria,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: pensionYear,
      semanasCotizadas: totalSemanasSinMod40,
      tieneEsposa: tieneEsposa,
      numeroHijos: numeroHijos,
      numeroPadres: numeroPadres,
      edadRetiro: edadEntera.toDouble(),
    );

    print('  TOTAL PENSION ANUAL:     \$${factSinMod40.totalPensionAnual.toStringAsFixed(2)}');
    print('  TOTAL PENSION MENSUAL:   \$${factSinMod40.totalPensionMensual.toStringAsFixed(2)}');
    print('');

    // ===== COMPARACIÓN CON VALORES ESPERADOS =====
    print('═══════════════════════════════════════════════════════════════════');
    print('COMPARACIÓN VS VALORES ESPERADOS');
    print('═══════════════════════════════════════════════════════════════════');

    final pensionSinMod40AnualEsperada = 754279.67;
    final pensionSinMod40MensualEsperada = 62856.64;
    final pensionConMod40AnualEsperada = 938276.01;
    final pensionConMod40MensualEsperada = 78189.67;

    // Sin Mod40
    final diffSinAnual = (factSinMod40.totalPensionAnual - pensionSinMod40AnualEsperada).abs();
    final diffSinMensual = (factSinMod40.totalPensionMensual - pensionSinMod40MensualEsperada).abs();
    print('');
    print('SIN MOD40:');
    print('  Anual:   App=\$${factSinMod40.totalPensionAnual.toStringAsFixed(2)} vs Esperado=\$${pensionSinMod40AnualEsperada.toStringAsFixed(2)} → ${diffSinAnual < 1 ? '✅ OK' : '❌ DIFERENCIA: \$${diffSinAnual.toStringAsFixed(2)}'}');
    print('  Mensual: App=\$${factSinMod40.totalPensionMensual.toStringAsFixed(2)} vs Esperado=\$${pensionSinMod40MensualEsperada.toStringAsFixed(2)} → ${diffSinMensual < 1 ? '✅ OK' : '❌ DIFERENCIA: \$${diffSinMensual.toStringAsFixed(2)}'}');

    // Con Mod40
    final diffConAnual = (pension.pensionAnualFinal - pensionConMod40AnualEsperada).abs();
    final diffConMensual = (pension.pensionMensual - pensionConMod40MensualEsperada).abs();
    print('');
    print('CON MOD40:');
    print('  Anual:   App=\$${pension.pensionAnualFinal.toStringAsFixed(2)} vs Esperado=\$${pensionConMod40AnualEsperada.toStringAsFixed(2)} → ${diffConAnual < 1 ? '✅ OK' : '❌ DIFERENCIA: \$${diffConAnual.toStringAsFixed(2)}'}');
    print('  Mensual: App=\$${pension.pensionMensual.toStringAsFixed(2)} vs Esperado=\$${pensionConMod40MensualEsperada.toStringAsFixed(2)} → ${diffConMensual < 1 ? '✅ OK' : '❌ DIFERENCIA: \$${diffConMensual.toStringAsFixed(2)}'}');

    // Incremento
    final incrementoMensual = pension.pensionMensual - factSinMod40.totalPensionMensual;
    final incrementoPorcentaje = (incrementoMensual / factSinMod40.totalPensionMensual) * 100;
    print('');
    print('INCREMENTO:');
    print('  Mensual: \$${incrementoMensual.toStringAsFixed(2)} (esperado: \$15,333.03)');
    print('  %:       ${incrementoPorcentaje.toStringAsFixed(2)}% (esperado: 24.39%)');

    // Tolerancia de $1 por redondeo
    expect(diffSinAnual, lessThan(2));
    expect(diffSinMensual, lessThan(2));
    expect(diffConAnual, lessThan(2));
    expect(diffConMensual, lessThan(2));
  });
}
