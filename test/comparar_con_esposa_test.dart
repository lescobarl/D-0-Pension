import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/pension_calculation.dart';

/// COMPARACIÓN: App vs Excel — Escenario ORIGINAL con ESPOSA = SÍ
///
/// Toma el mismo escenario base del Excel (Luis Adan Escobar Lopez)
/// pero cambiando tieneEsposa de false → true, y compara:
///   - App (motor) vs Excel (cálculo manual de las fórmulas)
///   - Pensión con M40 con esposa vs sin esposa
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  // ================================================================
  // ESCENARIO ORIGINAL (Luis Adan Escobar Lopez)
  // Mismos inputs que el Excel, SOLO cambia tieneEsposa: false → true
  // ================================================================
  const salarioDiarioPromedio = 2840.6157121429;
  const umaDiaria = 122.58895;
  const salarioMinimoDiario = 372.0408780827;
  const pensionYear = 2029;
  const semanasCotizadas = 2095;
  const numeroHijos = 1;
  const numeroPadres = 0;
  const edadRetiro = 61.0; // Excel redondea 60.5833 → 61

  test('COMPARAR App vs Excel — esposa=SÍ vs esposa=NO', () {
    print('\n' + '═' * 90);
    print('COMPARACIÓN: Escenario ORIGINAL — esposa=SÍ vs esposa=NO');
    print('═' * 90);

    print('\n📥 INPUTS (iguales en ambos casos):');
    print('  salarioDiarioPromedio: $salarioDiarioPromedio');
    print('  umaDiaria: $umaDiaria');
    print('  salarioMinimoDiario: $salarioMinimoDiario');
    print('  pensionYear: $pensionYear');
    print('  semanasCotizadas: $semanasCotizadas');
    print('  numeroHijos: $numeroHijos');
    print('  numeroPadres: $numeroPadres');
    print('  edadRetiro: $edadRetiro');

    // ─── SIN ESPOSA ───────────────────────────────────────────────
    print('\n' + '─' * 90);
    print('🔴 SIN ESPOSA (tieneEsposa = false)');
    print('─' * 90);

    final factSin = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioDiarioPromedio,
      umaDiaria: umaDiaria,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: pensionYear,
      semanasCotizadas: semanasCotizadas,
      tieneEsposa: false,
      numeroHijos: numeroHijos,
      numeroPadres: numeroPadres,
      edadRetiro: edadRetiro,
    );

    final pensionSin = evaluator.calculatePensionMod40(
      pensionAnual100: factSin.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      cuantiaTotalAsignaciones: factSin.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: factSin.totalAyudaAsistencial,
    );

    _printResult(factSin, pensionSin);

    // ─── CON ESPOSA ───────────────────────────────────────────────
    print('\n' + '─' * 90);
    print('🟢 CON ESPOSA (tieneEsposa = true)');
    print('─' * 90);

    final factCon = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioDiarioPromedio,
      umaDiaria: umaDiaria,
      salarioMinimoDiario: salarioMinimoDiario,
      pensionYear: pensionYear,
      semanasCotizadas: semanasCotizadas,
      tieneEsposa: true,
      numeroHijos: numeroHijos,
      numeroPadres: numeroPadres,
      edadRetiro: edadRetiro,
    );

    final pensionCon = evaluator.calculatePensionMod40(
      pensionAnual100: factCon.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      cuantiaTotalAsignaciones: factCon.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: factCon.totalAyudaAsistencial,
    );

    _printResult(factCon, pensionCon);

    // ─── COMPARACIÓN DIRECTA ──────────────────────────────────────
    print('\n' + '═' * 90);
    print('📊 COMPARACIÓN: CON esposa vs SIN esposa');
    print('═' * 90);

    final diffs = <_Diff>[
      _Diff('Cuantía Total Pensión Vejez',
          factCon.cuantiaTotalPensionVejez, factSin.cuantiaTotalPensionVejez),
      _Diff('Asignación Esposa (15%)',
          factCon.asignacionEsposa, factSin.asignacionEsposa),
      _Diff('Asignación Hijos (10%)',
          factCon.asignacionHijos, factSin.asignacionHijos),
      _Diff('Asignación Padres',
          factCon.asignacionPadres, factSin.asignacionPadres),
      _Diff('Cuantía Total Asignaciones',
          factCon.cuantiaTotalAsignaciones, factSin.cuantiaTotalAsignaciones),
      _Diff('Ayuda Asistencial',
          factCon.totalAyudaAsistencial, factSin.totalAyudaAsistencial),
      _Diff('Pensión Anual Final',
          pensionCon.pensionAnualFinal, pensionSin.pensionAnualFinal),
      _Diff('Pensión Mensual',
          pensionCon.pensionMensual, pensionSin.pensionMensual),
    ];

    print('  ${"Concepto".padRight(38)} ${"Con Esposa".padRight(18)} ${"Sin Esposa".padRight(18)} ${"Diferencia".padRight(18)}');
    print('  ' + '─' * 92);
    for (final d in diffs) {
      final diff = d.con - d.sin;
      final pct = d.sin != 0 ? (diff / d.sin * 100) : 0.0;
      print('  ${d.name.padRight(38)} '
          '\$${d.con.toStringAsFixed(2).padLeft(12)} '
          '\$${d.sin.toStringAsFixed(2).padLeft(12)} '
          '\$${diff.toStringAsFixed(2).padLeft(10)} '
          '(${pct.toStringAsFixed(1)}%)');
    }

    // ─── VALIDACIÓN CONTRA EXCEL ──────────────────────────────────
    print('\n' + '═' * 90);
    print('🔬 VALIDACIÓN: App vs Excel (cálculo manual de fórmulas)');
    print('═' * 90);

    // El Excel tiene esposa=NO (C8="NO"), así que calculamos MANUALMENTE
    // lo que Excel DARÍA con esposa=SÍ usando las mismas fórmulas:
    //
    // C30 (cuantiaTotalPensionVejez) = 1,023,703.72 (NO cambia con esposa)
    //
    // C34 = C30/1.11 = 1,023,703.72 / 1.11 = 922,255.60 (baseAsignaciones)
    //
    // C36 (asignación esposa) = C34 * 15% = 922,255.60 * 0.15 = 138,338.34
    //   fórmula Excel: =IF(C8="NO",0,C34*C35) donde C35=15%
    //
    // C43 (asignación hijos) = C34 * 10% * 1 hijo = 92,225.56 (sin cambios)
    //   fórmula Excel: =C40*C41*C42
    //
    // C49 (asignación padres) = 0 (sin cambios, porque tiene esposa)
    //   fórmula Excel: =IF(OR(tieneEsposa,hijos>0),0,C46*C47*C48)
    //
    // B53 (cuantia total asignaciones) = (C36 + C43 + C49) * 1.11 * D16
    //   D16 = porcentajePorEdad = lookupEdadPorcentaje(61) = 80%
    //   = (138,338.34 + 92,225.56 + 0) * 1.11 * 0.80
    //   = 230,563.90 * 1.11 * 0.80
    //   = 255,925.93 * 0.80
    //   = 204,740.74
    //
    // C23 (Pensión Anual Final) = D12*D16 + B53 + C59
    //   D12 = pensionAnual100 = 1,023,703.72
    //   = 1,023,703.72 * 0.80 + 204,740.74 + 0
    //   = 818,962.97 + 204,740.74
    //   = 1,023,703.72
    //
    // NOTA: La pensión anual final CON esposa resulta ser el mismo valor
    // que cuantiaTotalPensionVejez porque las asignaciones familiares
    // compensan exactamente el factor de edad (80%):
    //   pensionAnual100 * 80% + asignaciones = pensionAnual100
    //   (porque asignaciones = baseAsignaciones * 1.11 * 80%
    //    y baseAsignaciones = pensionAnual100 / 1.11)
    //   = pensionAnual100 * 80% + pensionAnual100/1.11 * 1.11 * 80%
    //   = pensionAnual100 * 80% + pensionAnual100 * 80%
    //   = pensionAnual100 * 160% ???
    //
    // ¡ESPERA! Eso no es correcto. Revisemos:
    //   baseAsignaciones = C30/1.11 (C34)
    //   asignacionEsposa = C34 * 15% = C30/1.11 * 0.15
    //   asignacionHijos = C34 * 10% * 1 = C30/1.11 * 0.10
    //   B53 = (C30/1.11*0.15 + C30/1.11*0.10) * 1.11 * 0.80
    //       = C30 * (0.15 + 0.10) * 0.80
    //       = C30 * 0.25 * 0.80
    //       = C30 * 0.20
    //   C23 = C30 * 0.80 + C30 * 0.20 = C30 * 1.00 = C30
    //
    // CORRECTO: Con esposa+SÍ y 1 hijo, la pensión anual final = C30
    // porque las asignaciones al 25% compensan el 80% de edad.
    // Pensión Mensual = C30 / 12 = 1,023,703.72 / 12 = 85,308.64

    final excelC30 = 1023703.7179115766;
    final excelC34 = excelC30 / 1.11; // 922,255.60
    final excelAsigEsposa = excelC34 * 0.15;     // 138,338.34
    final excelAsigHijos = excelC34 * 0.10 * 1;  // 92,225.56
    final excelAsigPadres = 0.0;
    final excelB53 = (excelAsigEsposa + excelAsigHijos + excelAsigPadres) * 1.11 * 0.80;
    final excelC23 = excelC30 * 0.80 + excelB53; // = excelC30 = 1,023,703.72
    final excelMensual = excelC23 / 12;           // 85,308.64

    final excelComparisons = <_Comparison>[
      _Comparison('C34 (base asignaciones)', factCon.cuantiaTotalPensionVejez / 1.11, excelC34),
      _Comparison('C36 (asignación esposa)', factCon.asignacionEsposa, excelAsigEsposa),
      _Comparison('C43 (asignación hijos)', factCon.asignacionHijos, excelAsigHijos),
      _Comparison('C49 (asignación padres)', factCon.asignacionPadres, excelAsigPadres),
      _Comparison('B53 (cuantía total asignaciones)', factCon.cuantiaTotalAsignaciones, excelB53),
      _Comparison('C23 (pensión anual final)', pensionCon.pensionAnualFinal, excelC23),
      _Comparison('Pensión Mensual', pensionCon.pensionMensual, excelMensual),
    ];

    print('  ${"Campo".padRight(38)} ${"App".padRight(18)} ${"Excel (fórmula)".padRight(18)} ${"Estado"}');
    print('  ' + '─' * 92);
    int okCount = 0;
    int failCount = 0;
    for (final c in excelComparisons) {
      final diff = (c.app - c.excel).abs();
      final isOk = diff < 0.1;
      if (isOk) { okCount++; } else { failCount++; }
      print('  ${c.name.padRight(38)} '
          '\$${c.app.toStringAsFixed(2).padLeft(12)} '
          '\$${c.excel.toStringAsFixed(2).padLeft(12)} '
          '${isOk ? "✅" : "❌"} (diff: \$${diff.toStringAsFixed(4)})');
    }

    print('\n' + '═' * 90);
    print('RESUMEN: ${okCount + failCount} campos comparados');
    print('  ✅ OK:   $okCount');
    if (failCount > 0) {
      print('  ❌ FAIL: $failCount');
    } else {
      print('  🎉 TODOS LOS CAMPOS COINCIDEN con el cálculo manual del Excel');
    }
    print('═' * 90);

    // ─── DIFERENCIA ECONÓMICA ─────────────────────────────────────
    print('\n' + '═' * 90);
    print('💰 IMPACTO ECONÓMICO DE TENER ESPOSA');
    print('═' * 90);
    final diffMensual = pensionCon.pensionMensual - pensionSin.pensionMensual;
    final diffAnual = pensionCon.pensionAnualFinal - pensionSin.pensionAnualFinal;
    print('  Pensión SIN esposa:  \$${pensionSin.pensionMensual.toStringAsFixed(2)}/mes');
    print('  Pensión CON esposa:  \$${pensionCon.pensionMensual.toStringAsFixed(2)}/mes');
    print('  Diferencia mensual:  \$${diffMensual.toStringAsFixed(2)}/mes');
    print('  Diferencia anual:    \$${diffAnual.toStringAsFixed(2)}/año');
    print('  Incremento %:        ${(diffMensual / pensionSin.pensionMensual * 100).toStringAsFixed(1)}%');
    print('═' * 90);

    // ASSERTIONS
    expect((factCon.asignacionEsposa - 138338.34).abs(), lessThan(0.1),
        reason: 'asignacionEsposa con esposa=SÍ debe ser ~138,338.34');
    expect(factSin.asignacionEsposa, closeTo(0.0, 0.01),
        reason: 'asignacionEsposa con esposa=NO debe ser 0');
    expect(pensionCon.pensionMensual, greaterThan(pensionSin.pensionMensual),
        reason: 'Pensión con esposa debe ser MAYOR que sin esposa');
    // Con esposa+SÍ y 1 hijo, la pensión anual final = C30 (cuantiaTotalPensionVejez)
    // porque las asignaciones al 25% compensan exactamente el 80% de edad
    expect((pensionCon.pensionAnualFinal - factCon.cuantiaTotalPensionVejez).abs(), lessThan(0.1),
        reason: 'Con esposa+SÍ y 1 hijo, pensión anual final = cuantiaTotalPensionVejez');
  });
}

void _printResult(FactAsigCalculation fact, PensionMod40Calculation pension) {
  print('  ───────────────────────────────────────────────────────────────');
  print('  ${"Campo".padRight(38)} ${"Valor".padRight(18)}');
  print('  ───────────────────────────────────────────────────────────────');
  print('  ${"Salario en UMAs".padRight(38)} ${fact.salarioEnUMAs.toStringAsFixed(4).padLeft(14)}');
  print('  ${"% Cuantía Básica".padRight(38)} ${(fact.porcentajeCuantiaBasica * 100).toStringAsFixed(2).padLeft(12)}%');
  print('  ${"Cuantía Básica por Día".padRight(38)} \$${fact.cuantiaBasicaPorDia.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Total Cuantía Básica Anual".padRight(38)} \$${fact.totalCuantiaBasicaAnual.toStringAsFixed(2).padLeft(12)}');
  print('  ${"% Incremento".padRight(38)} ${(fact.porcentajeIncremento * 100).toStringAsFixed(2).padLeft(12)}%');
  print('  ${"Incremento Anual".padRight(38)} \$${fact.incrementoAnual.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Número Incrementos Anuales".padRight(38)} ${fact.numeroIncrementosAnuales.toStringAsFixed(4).padLeft(14)}');
  print('  ${"Incrementos Redondeado".padRight(38)} ${fact.numeroIncrementosRedondeado.toStringAsFixed(0).padLeft(14)}');
  print('  ${"Total Incrementos Anuales".padRight(38)} \$${fact.totalIncrementosAnuales.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Cuantía Total Pensión Vejez".padRight(38)} \$${fact.cuantiaTotalPensionVejez.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Asignación Esposa (15%)".padRight(38)} \$${fact.asignacionEsposa.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Asignación Hijos (10%)".padRight(38)} \$${fact.asignacionHijos.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Asignación Padres (10%)".padRight(38)} \$${fact.asignacionPadres.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Cuantía Total Asignaciones".padRight(38)} \$${fact.cuantiaTotalAsignaciones.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Ayuda Asistencial".padRight(38)} \$${fact.totalAyudaAsistencial.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Total Pensión Anual".padRight(38)} \$${fact.totalPensionAnual.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Total Pensión Mensual".padRight(38)} \$${fact.totalPensionMensual.toStringAsFixed(2).padLeft(12)}');
  print('  ───────────────────────────────────────────────────────────────');
  print('  ${"% por Edad".padRight(38)} ${(pension.porcentajePorEdad * 100).toStringAsFixed(0).padLeft(12)}%');
  print('  ${"Pensión Anual 100%".padRight(38)} \$${pension.pensionAnual100.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Pensión Mínima Garantizada".padRight(38)} \$${pension.pensionMinimaGarantizada.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Aplica Mínima".padRight(38)} ${pension.aplicaMinima ? "SÍ" : "NO".padLeft(14)}');
  print('  ${"Pensión Anual Final".padRight(38)} \$${pension.pensionAnualFinal.toStringAsFixed(2).padLeft(12)}');
  print('  ${"Pensión Mensual".padRight(38)} \$${pension.pensionMensual.toStringAsFixed(2).padLeft(12)}');
}

class _Comparison {
  final String name;
  final double app;
  final double excel;
  _Comparison(this.name, this.app, this.excel);
}

class _Diff {
  final String name;
  final double con;
  final double sin;
  _Diff(this.name, this.con, this.sin);
}
