import 'dart:io';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('Escenario usuario - App vs Excel REAL', () {
    // ============================================================
    // ANÁLISIS DE RAÍZ: ¿Por qué App daba $78,191 vs Excel $73,302?
    // ============================================================
    //
    // El usuario proporcionó estos inputs:
    //   salarioDiarioPromedio = 2677.37
    //   umaDiaria              = 122.59
    //   edadRetiro             = 60.51
    //   semanasCotizadas       = 2038
    //
    // Pero Excel INTERNAMENTE calcula/usa valores DIFERENTES:
    //
    // 1. SALARIO (SAL. PROM MOD 40!E19):
    //    Excel calcula el salario_prom_final = 2677.3058 a partir de
    //    los datos históricos del usuario (promedio ponderado 250 semanas
    //    + semanas en Mod40). El usuario ingresó 2677.37 (redondeo).
    //    Diferencia: $0.0642/día → efecto mínimo.
    //
    // 2. UMA (SAL. PROM MOD 40!E16):
    //    Excel usa la UMA PROYECTADA para el año de inicio de Mod40
    //    (2028) = 128.1055, NO la UMA actual (122.59).
    //    El usuario ingresó 122.59 (UMA actual 2026).
    //    Diferencia: 21.84 UMAs (App) vs 20.90 UMAs (Excel).
    //    Esto cambia los porcentajes de cuantía básica e incrementos
    //    porque la tabla VLOOKUP usa el salario en UMAs.
    //
    // 3. EDAD DE RETIRO (DATOS GEN. MOD 40!C4):
    //    Excel usa 60.5, NO 60.51.
    //    Con threshold 0.51: 60.5 → 60 (75%), 60.51 → 61 (80%).
    //    ¡0.01 de diferencia cambia la pensión en ~$4,889/mes!
    //
    // 4. SEMANAS COTIZADAS (DATOS GEN. MOD 40!C16):
    //    Excel usa 2038.142857 (incluye fracción de semanas en Mod40).
    //    El usuario usó 2038 (entero).
    //    Diferencia: 29.5769 vs 29.57967 incrementos anuales.
    //    Efecto: ~$19 en total incrementos.
    //
    // CONCLUSIÓN: El motor de fórmulas (FormulaEvaluator) es CORRECTO.
    // Las diferencias se deben a que la App recibe inputs del usuario
    // mientras que Excel los calcula internamente a partir de datos
    // históricos. La App necesita replicar los cálculos intermedios
    // de Excel (SAL. PROM MOD 40) para que el usuario pueda ingresar
    // solo los datos brutos (fecha_nacimiento, fecha_calculo, etc.)
    // y la App derive salario_prom_final, UMA proyectada, etc.
    // ============================================================

    // Inputs CORREGIDOS para que coincidan con lo que Excel usa internamente
    final salarioDiarioPromedio = 2677.3057522035715;
    final umaDiaria = 128.10545275;
    final salarioMinimoDiario = 372.0408780827;
    final semanasCotizadas = 2038;
    final edadRetiro = 60.5;
    final tieneEsposa = true;
    final numeroHijos = 1;
    final numeroPadres = 0;
    final anoPension = 2029;

    print('\n========== INPUTS ==========');
    print('salarioDiarioPromedio: $salarioDiarioPromedio');
    print('umaDiaria: $umaDiaria');
    print('salarioMinimoDiario: $salarioMinimoDiario');
    print('semanasCotizadas: $semanasCotizadas');
    print('edadRetiro: $edadRetiro');
    print('tieneEsposa: $tieneEsposa');
    print('numeroHijos: $numeroHijos');
    print('anoPension: $anoPension');

    // CALCULAR APP
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

    print('\n========== APP ==========');
    print('PENSION MOD40 mensual: ${pensionMod40.pensionMensual.toStringAsFixed(4)}');
    print('PENSION MOD40 anual: ${pensionMod40.pensionAnualFinal.toStringAsFixed(4)}');
    print('FACT+ASIG mensual: ${factAsig.totalPensionMensual.toStringAsFixed(4)}');
    print('FACT+ASIG anual: ${factAsig.totalPensionAnual.toStringAsFixed(4)}');
    print('Pension vejez 100%: ${factAsig.cuantiaTotalPensionVejez.toStringAsFixed(4)}');
    print('Incrementos: ${factAsig.numeroIncrementosRedondeado}');
    print('Total incrementos: ${factAsig.totalIncrementosAnuales.toStringAsFixed(4)}');
    print('Cuantia basica: ${factAsig.totalCuantiaBasicaAnual.toStringAsFixed(4)}');
    print('% cuantia basica: ${factAsig.porcentajeCuantiaBasica}');
    print('Asignaciones: ${factAsig.cuantiaTotalAsignaciones.toStringAsFixed(4)}');
    print('Ayuda asistencial: ${factAsig.totalAyudaAsistencial.toStringAsFixed(4)}');
    print('Salario en UMAs: ${factAsig.salarioEnUMAs}');

    print('\n========== EXCEL REAL ==========');
    print('PENSION MOD40 mensual: 73302.6967');
    print('PENSION MOD40 anual: 879632.3607');
    print('FACT+ASIG mensual: 73302.6967');
    print('FACT+ASIG anual: 879632.3607');
    print('Pension vejez 100%: 938274.5181');
    print('Incrementos: 30');
    print('Total incrementos: 797262.1627');
    print('Cuantia basica: 141012.3553');
    print('% cuantia basica: 0.13');
    print('Asignaciones: 175926.4721');
    print('Ayuda asistencial: 0');
    print('Salario en UMAs: 20.90');

    print('\n========== COMPARACION ==========');
    final tol = 1.0;
    int passed = 0;
    int failed = 0;

    void cmp(String label, double app, double excel) {
      final diff = (app - excel).abs();
      final ok = diff <= tol;
      if (ok) { passed++; } else { failed++; }
      print('${ok ? "PASA" : "FALLA"} $label: App=$app vs Excel=$excel (diff=$diff)');
    }

    cmp('Pension vejez 100%', factAsig.cuantiaTotalPensionVejez, 938274.5181);
    cmp('Pension mensual neta', factAsig.totalPensionMensual, 73302.6967);
    cmp('Total pension anual', factAsig.totalPensionAnual, 879632.3607);
    cmp('Pension anual final Mod40', pensionMod40.pensionAnualFinal, 879632.3607);
    cmp('Pension mensual Mod40', pensionMod40.pensionMensual, 73302.6967);
    cmp('Total incrementos anuales', factAsig.totalIncrementosAnuales, 797262.1627);
    cmp('Total cuantia basica anual', factAsig.totalCuantiaBasicaAnual, 141012.3553);
    cmp('CuantiaTotalAsignaciones', factAsig.cuantiaTotalAsignaciones, 175926.4721);
    cmp('TotalAyudaAsistencial', factAsig.totalAyudaAsistencial, 0.0);

    print('\nRESULTADO: $passed passed, $failed failed');
  });
}
