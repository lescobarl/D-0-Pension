import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';
import 'package:d_0_pension/services/persistence_service.dart';

/// COMPREHENSIVE VALIDATION: App vs Excel (via Python reference)
///
/// This test validates that the App produces IDENTICAL results to the
/// Excel for BOTH pension sin M40 AND pension con M40 across 10 diverse
/// scenarios.
///
/// The Python reference (cross_validate_scenarios.py) replicates ALL Excel
/// formulas EXACTLY, including VLOOKUPs, FORECAST.LINEAR, and all Ley 73 tables.
///
/// This test uses the RetroactiveProvider (FULL UI pipeline) to ensure the
/// entire app stack produces correct results.
///
/// Run with: flutter test test/validate_10_scenarios_vs_excel_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;
  late List<dynamic> pythonScenarios;

  setUpAll(() async {
    // Load Python-generated reference output
    final file = File('cross_validate_scenarios_output.json');
    final jsonStr = await file.readAsString();
    final sanitized = jsonStr.replaceAll('Infinity', '1e308');
    pythonScenarios = json.decode(sanitized) as List<dynamic>;
    expect(pythonScenarios.length, 11, reason: 'Expected 11 scenarios');

    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  /// Helper: approxEqual with tolerance 0.02 absolute OR 0.1% relative
  bool approxEqual(double a, double b, {double absTol = 0.02, double relTol = 0.001}) {
    if (a == b) return true;
    final diff = (a - b).abs();
    if (diff <= absTol) return true;
    if (a.abs() > relTol && b.abs() > relTol) {
      return diff / math.max(a.abs(), b.abs()) <= relTol;
    }
    return false;
  }

  /// Helper: compare two numeric values, handling special cases
  bool _compareValues(dynamic appVal, dynamic pyVal, String field) {
    if (appVal == null && pyVal == null) return true;
    if (appVal == null || pyVal == null) return false;
    if (appVal is bool && pyVal is bool) return appVal == pyVal;
    if (appVal is String && pyVal is String) return appVal == pyVal;
    if (appVal is int && pyVal is int) return appVal == pyVal;
    if (appVal is num && pyVal is num) {
      final a = appVal.toDouble();
      final b = pyVal.toDouble();
      const infinitySentinel = 1e308;
      if (a.isInfinite || a >= infinitySentinel) {
        if (b.isInfinite || b >= infinitySentinel) return true;
      }
      if (a.isNaN && b.isNaN) return true;
      if (a.abs() < 0.001 && b.abs() < 0.001) return (a - b).abs() < 0.001;
      return approxEqual(a, b);
    }
    return false;
  }

  /// Helper: recursively compare two maps and report differences
  List<String> _compareResults(Map<String, dynamic> app, Map<String, dynamic> py, String prefix) {
    final diffs = <String>[];
    for (final key in app.keys) {
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      final appVal = app[key];
      final pyVal = py[key];

      if (appVal is Map<String, dynamic> && pyVal is Map<String, dynamic>) {
        diffs.addAll(_compareResults(appVal, pyVal, fullKey));
      } else if (!_compareValues(appVal, pyVal, fullKey)) {
        diffs.add('$fullKey: App=$appVal vs Python=$pyVal');
      }
    }
    return diffs;
  }

  /// Create a RetroactiveProvider with mocked SharedPreferences.
  Future<RetroactiveProvider> _createProvider() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final persistence = PersistenceService(prefs);
    final provider = RetroactiveProvider(
      evaluator: evaluator,
      persistence: persistence,
    );
    await provider.initialize();
    return provider;
  }

  /// Run a scenario through the RetroactiveProvider (full UI pipeline).
  ///
  /// Returns a map with:
  ///   - 'pension_sin_m40': pension mensual WITHOUT Modalidad 40
  ///   - 'pension_con_m40': pension mensual WITH Modalidad 40
  ///   - All other calculation results (fact_asig, pension_mod40, etc.)
  Map<String, dynamic> _runThroughProvider(
    RetroactiveProvider provider,
    Map<String, dynamic> inputs,
  ) {
    // Extract inputs
    final salarioDiarioPromedio = (inputs['salario_diario_promedio'] as num).toDouble();
    final umaDiaria = (inputs['uma_diaria'] as num).toDouble();
    final salarioMinimoDiario = (inputs['salario_minimo_diario'] as num).toDouble();
    final pensionYear = (inputs['pension_year'] as num).toInt();
    final semanasCotizadas = (inputs['semanas_cotizadas'] as num).toInt();
    final tieneEsposa = inputs['tiene_esposa'] as bool;
    final numeroHijos = (inputs['numero_hijos'] as num).toInt();
    final numeroPadres = (inputs['numero_padres'] as num).toInt();
    final edadRetiro = (inputs['edad_retiro'] as num).toDouble();
    final salarioRegistrado = (inputs['salario_registrado'] as num).toDouble();
    final startDateStr = inputs['start_date'] as String;
    final endDateStr = inputs['end_date'] as String;
    final retroactiveYears = (inputs['retroactive_years'] as num).toDouble();

    // Check for separate sin Mod40 inputs
    final hasSeparateSinMod40 = inputs.containsKey('salario_promedio_250_semanas');
    final salarioPromedio250Semanas = hasSeparateSinMod40
        ? (inputs['salario_promedio_250_semanas'] as num).toDouble()
        : salarioDiarioPromedio;
    final semanasSinMod40 = hasSeparateSinMod40 && inputs.containsKey('semanas_sin_mod40')
        ? (inputs['semanas_sin_mod40'] as num).toInt()
        : semanasCotizadas;

    final startDate = DateTime.parse(startDateStr);
    final endDate = DateTime.parse(endDateStr);

    // ── Step 1: Set all input values on the provider ──
    // IMPORTANT ORDERING RULES:
    // 1. setEdadRetiro must come BEFORE setPensionYear, setUmaDiaria, and
    //    setSalarioMinimoDiario because setEdadRetiro recalculates _pensionYear
    //    from _fechaNacimiento + edadRetiro.floor() and then calls
    //    _projectUmaSm(force:true) which OVERWRITES UMA/SM with projected values
    //    for the NEW pension year. Setting UMA/SM after ensures the user's
    //    manual values are preserved.
    // 2. setPensionYear must come BEFORE setUmaDiaria and setSalarioMinimoDiario
    //    because setPensionYear also calls _projectUmaSm(force:true).
    provider.setEdadRetiro(edadRetiro);
    provider.setPensionYear(pensionYear);
    provider.setSalarioDiarioPromedio(salarioDiarioPromedio);
    provider.setUmaDiaria(umaDiaria);
    provider.setSalarioMinimoDiario(salarioMinimoDiario);
    provider.setSemanasCotizadas(semanasCotizadas);
    provider.setTieneEsposa(tieneEsposa);
    provider.setNumeroHijos(numeroHijos);
    provider.setNumeroPadres(numeroPadres);
    provider.setSalarioRegistrado(salarioRegistrado);
    provider.setStartDate(startDate);
    provider.setEndDate(endDate);
    provider.setRetroactiveYears(retroactiveYears);

    // Set sin Mod40 inputs
    provider.setSalarioPromedio250Semanas(salarioPromedio250Semanas);
    provider.setTotalSemanasSinMod40(semanasSinMod40);

    // ── Step 2: Recalculate all in correct dependency order ──
    provider.recalculateAll();

    // ── Step 3: Read results from the provider ──
    final factAsig = provider.factAsigCalculation;
    final pensionMod40 = provider.pensionMod40Calculation;
    final factAsigSinMod40 = provider.factAsigSinMod40Calculation;
    final costoMod40 = provider.costoMod40Calculation;
    final retroactivo = provider.retroactiveCalculation;
    final inversion = provider.inversionCalculation;
    final financiamiento = provider.financiamientoCalculation;

    return {
      'pension_sin_m40': factAsigSinMod40?.totalPensionMensual ?? 0,
      'pension_con_m40': pensionMod40?.pensionMensual ?? 0,
      'fact_asig': {
        'pension_mensual': factAsig?.totalPensionMensual ?? 0,
        'total_pension_anual': factAsig?.totalPensionAnual ?? 0,
        'cuantia_total_pension_vejez': factAsig?.cuantiaTotalPensionVejez ?? 0,
        'salario_en_umas': factAsig?.salarioEnUMAs ?? 0,
        'numero_incrementos_redondeado': factAsig?.numeroIncrementosRedondeado ?? 0,
        'total_incrementos_anuales': factAsig?.totalIncrementosAnuales ?? 0,
        'total_cuantia_basica_anual': factAsig?.totalCuantiaBasicaAnual ?? 0,
        'asignacion_esposa': factAsig?.asignacionEsposa ?? 0,
        'asignacion_hijos': factAsig?.asignacionHijos ?? 0,
        'asignacion_padres': factAsig?.asignacionPadres ?? 0,
        'total_asignaciones': factAsig?.cuantiaTotalAsignaciones ?? 0,
        'total_ayuda_asistencial': factAsig?.totalAyudaAsistencial ?? 0,
        'decreto_presidencial': factAsig?.asignacionDecretoPresidencial ?? 0,
        'porcentaje_por_edad': pensionMod40?.porcentajePorEdad ?? 0,
        'tipo_pension': pensionMod40?.tipoPension ?? '',
      },
      'pension_mod40': {
        'pension_mensual': pensionMod40?.pensionMensual ?? 0,
        'pension_anual_final': pensionMod40?.pensionAnualFinal ?? 0,
        'porcentaje_por_edad': pensionMod40?.porcentajePorEdad ?? 0,
        'tipo_pension': pensionMod40?.tipoPension ?? '',
        'aplica_minima': pensionMod40?.aplicaMinima ?? false,
        'pension_minima_garantizada': pensionMod40?.pensionMinimaGarantizada ?? 0,
      },
      'costo_mod40': {
        'inversion_total': costoMod40?.inversionTotal ?? 0,
        'recuperacion_afore': costoMod40?.recuperacionAfore ?? 0,
        'inversion_neta': costoMod40?.inversionNeta ?? 0,
      },
      'retroactivo': {
        'costo_total': retroactivo?.costoTotal ?? 0,
        'actualizaciones': retroactivo?.actualizaciones ?? 0,
        'recargos': retroactivo?.recargos ?? 0,
        'costo_m40': retroactivo?.costoModalidad40 ?? 0,
        'porcentaje_incremento': retroactivo?.incrementoPorcentaje ?? 0,
        'afore_recovery': retroactivo?.recuperacionAfore ?? 0,
        'retroactivo_neta': retroactivo?.inversionTotal ?? 0,
        'meses_retroactivos': retroactivo?.mesesRetroactivos ?? 0,
      },
      'inversion': {
        'mejora_pension': inversion?.mejoraPension ?? 0,
        'periodos_recuperacion': inversion?.periodosRecuperacionMeses ?? 0,
        'flujo_sin_mod40': inversion?.flujoHasta80SinMod40 ?? 0,
        'flujo_con_mod40': inversion?.flujoHasta80ConMod40 ?? 0,
        'ganancia_total': inversion?.gananciaTotal ?? 0,
        'tasa_rendimiento': inversion?.tasaRendimiento ?? 0,
        'veredicto': inversion?.veredicto ?? '',
      },
      'financiamiento': {
        'participacion_banco': financiamiento?.participacionBanco ?? 0,
        'participacion_propia': financiamiento?.participacionPropia ?? 0,
        'monto_credito': financiamiento?.montoCredito ?? 0,
        'costo_financiamiento': financiamiento?.costoFinanciamiento ?? 0,
        'monto_maximo_pagar': financiamiento?.montoMaximoPagar ?? 0,
        'monto_redondeado': financiamiento?.montoCreditoRedondeado ?? 0,
        'descuento_mensual': financiamiento?.descuentoMensual ?? 0,
        'pension_inmediata': financiamiento?.pensionMensualInmediata ?? 0,
        'pension_liquidacion': financiamiento?.pensionMensualLiquidacion ?? 0,
        'flujo_hasta_80': financiamiento?.flujoHasta80 ?? 0,
        'periodos_recuperacion_fin': financiamiento?.periodosRecuperacionMeses ?? 0,
        'veredicto_fin': financiamiento?.veredicto ?? '',
      },
    };
  }

  /// Extract the sin M40 pension from Python reference results.
  ///
  /// The Python reference now stores pension_sin_mod40 directly in the JSON
  /// output (added to cross_validate_scenarios.py).
  double _extractPensionSinMod40(Map<String, dynamic> pyResults) {
    final pensionSinMod40 = pyResults['pension_sin_mod40'] as Map<String, dynamic>;
    return (pensionSinMod40['pension_mensual'] as num).toDouble();
  }

  /// Extract the con M40 pension from Python reference results.
  double _extractPensionConMod40(Map<String, dynamic> pyResults) {
    final pensionMod40 = pyResults['pension_mod40'] as Map<String, dynamic>;
    return (pensionMod40['pension_mensual'] as num).toDouble();
  }

  // ================================================================
  // TEST GROUP 1: PENSION SIN M40 vs PENSION CON M40 (explicit)
  // ================================================================
  group('Pension Sin M40 vs Con M40 - Explicit Validation', () {
    for (int i = 0; i < 11; i++) {
      final scenarioNum = i + 1;
      test('Scenario $scenarioNum: Sin M40 and Con M40 pensions match Excel', () async {
        final pyScenario = pythonScenarios[i] as Map<String, dynamic>;
        final pyInputs = pyScenario['inputs'] as Map<String, dynamic>;
        final pyResults = pyScenario['results'] as Map<String, dynamic>;
        final scenarioName = pyScenario['scenario'] as String;

        // Extract expected pension values from Python reference
        final expectedPensionSinM40 = _extractPensionSinMod40(pyResults);
        final expectedPensionConM40 = _extractPensionConMod40(pyResults);

        // Create a fresh provider and run the scenario
        final provider = await _createProvider();
        final appResults = _runThroughProvider(provider, pyInputs);

        final appPensionSinM40 = appResults['pension_sin_m40'] as double;
        final appPensionConM40 = appResults['pension_con_m40'] as double;

        // Build detailed report
        final buffer = StringBuffer();
        buffer.writeln('╔═══════════════════════════════════════════════════════════');
        buffer.writeln('║ Scenario $scenarioNum: $scenarioName');
        buffer.writeln('║ ${pyScenario['desc']}');
        buffer.writeln('╠═══════════════════════════════════════════════════════════');
        buffer.writeln('║ PENSION SIN MOD40 (mensual):');
        buffer.writeln('║   App:   \$${appPensionSinM40.toStringAsFixed(2)}');
        buffer.writeln('║   Excel: \$${expectedPensionSinM40.toStringAsFixed(2)}');
        buffer.writeln('║   Diff:  \$${(appPensionSinM40 - expectedPensionSinM40).toStringAsFixed(2)}');
        buffer.writeln('║   Match: ${approxEqual(appPensionSinM40, expectedPensionSinM40) ? '✅ YES' : '❌ NO'}');
        buffer.writeln('║');
        buffer.writeln('║ PENSION CON MOD40 (mensual):');
        buffer.writeln('║   App:   \$${appPensionConM40.toStringAsFixed(2)}');
        buffer.writeln('║   Excel: \$${expectedPensionConM40.toStringAsFixed(2)}');
        buffer.writeln('║   Diff:  \$${(appPensionConM40 - expectedPensionConM40).toStringAsFixed(2)}');
        buffer.writeln('║   Match: ${approxEqual(appPensionConM40, expectedPensionConM40) ? '✅ YES' : '❌ NO'}');
        buffer.writeln('╚═══════════════════════════════════════════════════════════');

        // Print the report
        print(buffer.toString());

        // Assert both pensions match
        expect(
          approxEqual(appPensionSinM40, expectedPensionSinM40),
          true,
          reason: 'Scenario $scenarioNum: Pension SIN M40 mismatch.\n'
              'App: \$${appPensionSinM40.toStringAsFixed(2)}\n'
              'Excel: \$${expectedPensionSinM40.toStringAsFixed(2)}\n'
              'Diff: \$${(appPensionSinM40 - expectedPensionSinM40).toStringAsFixed(2)}',
        );
        expect(
          approxEqual(appPensionConM40, expectedPensionConM40),
          true,
          reason: 'Scenario $scenarioNum: Pension CON M40 mismatch.\n'
              'App: \$${appPensionConM40.toStringAsFixed(2)}\n'
              'Excel: \$${expectedPensionConM40.toStringAsFixed(2)}\n'
              'Diff: \$${(appPensionConM40 - expectedPensionConM40).toStringAsFixed(2)}',
        );
      });
    }
  });

  // ================================================================
  // TEST GROUP 2: Full calculation pipeline (all fields)
  // ================================================================
  group('Full Pipeline Validation - All Fields vs Excel', () {
    for (int i = 0; i < 11; i++) {
      final scenarioNum = i + 1;
      test('Scenario $scenarioNum: All calculation fields match Excel', () async {
        final pyScenario = pythonScenarios[i] as Map<String, dynamic>;
        final pyInputs = pyScenario['inputs'] as Map<String, dynamic>;
        final pyResults = pyScenario['results'] as Map<String, dynamic>;

        // Create a fresh provider for each scenario
        final provider = await _createProvider();
        final appResults = _runThroughProvider(provider, pyInputs);

        // Remove the pension_sin/con_m40 keys (not in Python reference)
        final appResultsClean = Map<String, dynamic>.from(appResults);
        appResultsClean.remove('pension_sin_m40');
        appResultsClean.remove('pension_con_m40');

        final diffs = _compareResults(appResultsClean, pyResults, '');
        if (diffs.isNotEmpty) {
          fail('Scenario $scenarioNum differences found:\n${diffs.join('\n')}');
        }
      });
    }
  });
}
