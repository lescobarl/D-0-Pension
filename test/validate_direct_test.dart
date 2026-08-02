// Flutter test that reads Excel validation data from a JSON file
// and compares App calculation results against Excel values.
//
// Usage:
//   python validate_app_vs_excel_v2.py
//   flutter test test/validate_direct_test.dart
//
// The JSON file contains scenario data with:
//   [{"name": "...", "inputs": {...}, "excel": {...}}, ...]
//
// IMPORTANT: The 'inputs' contain USER-PROVIDED values (salario_diario_promedio,
// uma_diaria, salario_minimo_diario) that the user would enter in the captura
// screen. The 'excel' contains the OUTPUT values from Excel's calculation.
// The App uses the same user-provided inputs and should produce the same outputs.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/engine/formula_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('Excel validation data file exists', () {
    final file = File('excel_validation_data.json');
    expect(file.existsSync(), isTrue,
        reason: 'Run "python validate_app_vs_excel_v2.py" first to generate the data');
  });

  test('All scenarios match Excel', () async {
    final file = File('excel_validation_data.json');
    final contents = await file.readAsString();
    final List<dynamic> scenarios = jsonDecode(contents) as List<dynamic>;

    expect(scenarios.isNotEmpty, isTrue, reason: 'No scenarios found in data file');

    int totalPassed = 0;
    int totalFailed = 0;
    int totalComparisons = 0;

    for (int i = 0; i < scenarios.length; i++) {
      final scenario = scenarios[i] as Map<String, dynamic>;
      final name = scenario['name'] as String? ?? 'Scenario ${i + 1}';
      final inputs = scenario['inputs'] as Map<String, dynamic>? ?? {};
      final excel = scenario['excel'] as Map<String, dynamic>? ?? {};

      print('\n========== $name ==========');

      // Extract USER-PROVIDED inputs (same values the user enters in captura)
      final salarioDiarioPromedio = (inputs['salario_diario_promedio'] as num?)?.toDouble() ?? 0;
      final umaDiaria = (inputs['uma_diaria'] as num?)?.toDouble() ?? 0;
      final salarioMinimoDiario = (inputs['salario_minimo_diario'] as num?)?.toDouble() ?? 0;
      final pensionYear = inputs['pension_year'] as int? ?? 2029;
      final semanasCotizadas = (inputs['semanas_cotizadas'] as num?)?.toInt() ?? 0;
      final tieneEsposa = inputs['tiene_esposa'] as bool? ?? false;
      final numeroHijos = inputs['numero_hijos'] as int? ?? 0;
      final numeroPadres = inputs['numero_padres'] as int? ?? 0;
      final edadRetiro = (inputs['edad_retiro'] as num?)?.toDouble() ?? 65;

      // Run App calculation with USER-PROVIDED inputs (not Excel's internal values)
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

      final pensionMod40 = evaluator.calculatePensionMod40(
        pensionAnual100: factAsig.cuantiaTotalPensionVejez,
        edadRetiro: edadRetiro,
        salarioMinimoDiario: salarioMinimoDiario,
        pensionYear: pensionYear,
        cuantiaTotalAsignaciones: factAsig.cuantiaTotalAsignaciones,
        totalAyudaAsistencial: factAsig.totalAyudaAsistencial,
      );

      // Build App results map — include ALL keys that Excel provides
      final app = <String, double>{
        'salario_diario_promedio': factAsig.salarioDiarioPromedio,
        'uma_diaria': factAsig.umaDiaria,
        'salario_minimo_diario': factAsig.salarioMinimoDiario,
        'salario_en_umas': factAsig.salarioEnUMAs,
        'porcentaje_cuantia_basica': factAsig.porcentajeCuantiaBasica,
        'total_cuantia_basica': factAsig.totalCuantiaBasicaAnual,
        'numero_incrementos': factAsig.numeroIncrementosRedondeado,
        'total_incrementos': factAsig.totalIncrementosAnuales,
        'pension_vejez_100': factAsig.cuantiaTotalPensionVejez,
        'asignacion_esposa': factAsig.asignacionEsposa,
        'asignacion_hijos': factAsig.asignacionHijos,
        'asignacion_padres': factAsig.asignacionPadres,
        'total_asignaciones': factAsig.cuantiaTotalAsignaciones,
        'total_ayuda_asistencial': factAsig.totalAyudaAsistencial,
        'pension_anual_neta': factAsig.totalPensionAnual,
        'pension_mensual_neta': factAsig.totalPensionMensual,
        // edad_entera = floor of edadRetiro (Excel's D14 in PENSION MOD. 40)
        'edad_entera': edadRetiro.floorToDouble(),
        'porcentaje_edad': pensionMod40.porcentajePorEdad,
        'pension_mod40_anual': pensionMod40.pensionAnualFinal,
        'pension_mod40_mensual': pensionMod40.pensionMensual,
      };

      // Compare with Excel
      const tol = 1.0;
      int passed = 0;
      int failed = 0;

      for (final entry in excel.entries) {
        final key = entry.key;
        final excelVal = (entry.value as num).toDouble();
        final appVal = app[key];
        if (appVal == null) {
          print('  ⚠️  App key "$key" not found');
          failed++;
          continue;
        }
        final diff = (appVal - excelVal).abs();
        final ok = diff <= tol;
        if (ok) {
          passed++;
        } else {
          failed++;
        }
        print('  ${ok ? "✅" : "❌"} $key: App=${appVal.toStringAsFixed(4)} vs Excel=${excelVal.toStringAsFixed(4)} (diff=${diff.toStringAsFixed(4)})');
        totalComparisons++;
      }

      print('  → $passed passed, $failed failed');
      totalPassed += passed;
      totalFailed += failed;
    }

    print('\n========== FINAL ==========');
    print('Total: $totalComparisons comparisons across ${scenarios.length} scenarios');
    print('Passed: $totalPassed');
    print('Failed: $totalFailed');

    expect(totalFailed, equals(0),
        reason: '$totalFailed comparisons failed out of $totalComparisons');
  });
}
