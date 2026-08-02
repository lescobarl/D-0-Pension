import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';

/// Validacion del escenario del usuario: Esposa=SI, 1 hijo, 1960 sem antes M40, 130 sem en M40
/// Compara App (FormulaEvaluator) vs Python (que ya validamos contra Excel)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
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

  test('Escenario Usuario: Esposa=SI, 130 sem M40, edad 61', () async {
    // Mismos inputs que usamos en Python
    final salarioDiarioPromedio = 2677.3057522036;
    final umaDiaria = 128.10545275;
    final salarioMinimoDiario = 372.0408780827;
    final pensionYear = 2029;
    final semanasCotizadas = 2090; // 1960 + 130
    final tieneEsposa = true;
    final numeroHijos = 1;
    final numeroPadres = 0;
    final edadRetiro = 61.0;

    // Calcular Factores y Asignaciones
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

    print('=== FACTORES Y ASIGNACIONES (APP) ===');
    print('  salarioEnUMAs: ${factAsig.salarioEnUMAs.toStringAsFixed(4)}');
    print('  numeroIncrementosRedondeado: ${factAsig.numeroIncrementosRedondeado}');
    print('  totalCuantiaBasicaAnual: ${factAsig.totalCuantiaBasicaAnual.toStringAsFixed(4)}');
    print('  totalIncrementosAnuales: ${factAsig.totalIncrementosAnuales.toStringAsFixed(4)}');
    print('  cuantiaTotalPensionVejez: ${factAsig.cuantiaTotalPensionVejez.toStringAsFixed(4)}');
    print('  asignacionEsposa: ${factAsig.asignacionEsposa.toStringAsFixed(4)}');
    print('  asignacionHijos: ${factAsig.asignacionHijos.toStringAsFixed(4)}');
    print('  cuantiaTotalAsignaciones: ${factAsig.cuantiaTotalAsignaciones.toStringAsFixed(4)}');
    print('  totalAyudaAsistencial: ${factAsig.totalAyudaAsistencial.toStringAsFixed(4)}');
    print('  asignacionDecretoPresidencial: ${factAsig.asignacionDecretoPresidencial.toStringAsFixed(4)}');
    print('  totalPensionAnual: ${factAsig.totalPensionAnual.toStringAsFixed(4)}');
    print('  totalPensionMensual: ${factAsig.totalPensionMensual.toStringAsFixed(4)}');

    // Calcular Pension Mod40
    final pensionMod40 = evaluator.calculatePensionMod40(
      pensionAnual100: factAsig.cuantiaTotalPensionVejez,
      edadRetiro: edadRetiro,
      salarioMinimoDiario: salarioMinimoDiario,
      cuantiaTotalAsignaciones: factAsig.cuantiaTotalAsignaciones,
      totalAyudaAsistencial: factAsig.totalAyudaAsistencial,
    );

    print('');
    print('=== PENSION MOD 40 (APP) ===');
    print('  pensionAnual100: ${pensionMod40.pensionAnual100.toStringAsFixed(4)}');
    print('  porcentajePorEdad: ${pensionMod40.porcentajePorEdad}');
    print('  tipoPension: ${pensionMod40.tipoPension}');
    print('  pensionMinimaGarantizada: ${pensionMod40.pensionMinimaGarantizada.toStringAsFixed(4)}');
    print('  aplicaMinima: ${pensionMod40.aplicaMinima}');
    print('  pensionAnualFinal: ${pensionMod40.pensionAnualFinal.toStringAsFixed(4)}');
    print('  pensionMensual: ${pensionMod40.pensionMensual.toStringAsFixed(4)}');

    // Valores esperados de Python
    final pensionMensualEsperada = 80404.16;
    final pensionAnualEsperada = 964849.92;
    final cuantiaVejezEsperada = 964849.9235;
    final asignacionEsposaEsperada = 130385.1248;
    final asignacionHijosEsperada = 86923.4165;
    final totalAsignacionesEsperado = 192969.9847;

    print('');
    print('=== COMPARACION APP vs PYTHON ===');
    
    double pensionMensual = pensionMod40.pensionMensual;
    print('Pension mensual: App=${pensionMensual.toStringAsFixed(2)} vs Python=80404.16');
    expect(approxEqual(pensionMensual, pensionMensualEsperada), true,
        reason: 'Pension mensual: $pensionMensual != $pensionMensualEsperada');

    double pensionAnual = pensionMod40.pensionAnualFinal;
    print('Pension anual: App=${pensionAnual.toStringAsFixed(2)} vs Python=964849.92');
    expect(approxEqual(pensionAnual, pensionAnualEsperada), true,
        reason: 'Pension anual: $pensionAnual != $pensionAnualEsperada');

    double cuantiaVejez = factAsig.cuantiaTotalPensionVejez;
    print('Cuantia vejez: App=${cuantiaVejez.toStringAsFixed(4)} vs Python=964849.9235');
    expect(approxEqual(cuantiaVejez, cuantiaVejezEsperada), true,
        reason: 'Cuantia vejez: $cuantiaVejez != $cuantiaVejezEsperada');

    double asignacionEsposa = factAsig.asignacionEsposa;
    print('Asignacion esposa: App=${asignacionEsposa.toStringAsFixed(4)} vs Python=130385.1248');
    expect(approxEqual(asignacionEsposa, asignacionEsposaEsperada), true,
        reason: 'Asignacion esposa: $asignacionEsposa != $asignacionEsposaEsperada');

    double asignacionHijos = factAsig.asignacionHijos;
    print('Asignacion hijos: App=${asignacionHijos.toStringAsFixed(4)} vs Python=86923.4165');
    expect(approxEqual(asignacionHijos, asignacionHijosEsperada), true,
        reason: 'Asignacion hijos: $asignacionHijos != $asignacionHijosEsperada');

    double totalAsignaciones = factAsig.cuantiaTotalAsignaciones;
    print('Total asignaciones: App=${totalAsignaciones.toStringAsFixed(4)} vs Python=192969.9847');
    expect(approxEqual(totalAsignaciones, totalAsignacionesEsperado), true,
        reason: 'Total asignaciones: $totalAsignaciones != $totalAsignacionesEsperado');
  });
}
