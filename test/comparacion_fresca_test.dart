// COMPARACIÓN FRESCA: App engine vs Excel actual
// Escenario REAL del Excel: 1960 sem, esposa=SI, 1 hijo, 78.14 sem M40, 2038.14 total
// Salario=2677.31, UMA=128.11, Edad=60
//
// Datos extraídos del Excel el 2026-07-12

import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/pension_calculation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  test('COMPARACIÓN FRESCA: App engine vs Excel actual (esposa=SI, 78 sem M40)', () {
    // ===== PARÁMETROS (del Excel actual) =====
    const double salarioDiario = 2677.3057522035715;
    const double umaDiaria = 128.10545275;
    const double salarioMinimo = 372.0408780827;
    const int semanasCotizadas = 2038;
    const bool tieneEsposa = true;
    const int numeroHijos = 1;
    const int numeroPadres = 0;
    const double edadRetiro = 60;
    const int pensionYear = 2029;

    // ===== VALORES DEL EXCEL (recién extraídos) =====
    final excel = <String, double>{
      'C7_salarioUMAs': 20.9,
      'C12': 0.13,
      'C13': 348.0497477865,
      'C15': 141012.355315686,
      'C20': 0.0245,
      'C21': 65.593990929,
      'C23': 23941.8066890804,
      'C24': 29.5796703297,
      'C25': 30,
      'C26': 797262.1627463788,
      'C30': 938274.5180620649,
      'C34': 845292.3586144728,
      'C36': 126793.8537921709,
      'C43': 84529.2358614473,
      'C49': 0,
      'B53': 175926.4721366372,
      'C59': 0,
      'C67': 1114200.990198702,
      'C69': 122562.1089218572,
      'C72': 879632.3606831859,
      'C74': 73302.6967235988,
    };

    // ===== CALCULAR CON APP ENGINE =====
    final factAsig = evaluator.calculateFactAsig(
      salarioDiarioPromedio: salarioDiario,
      umaDiaria: umaDiaria,
      salarioMinimoDiario: salarioMinimo,
      pensionYear: pensionYear,
      semanasCotizadas: semanasCotizadas,
      tieneEsposa: tieneEsposa,
      numeroHijos: numeroHijos,
      numeroPadres: numeroPadres,
      edadRetiro: edadRetiro,
    );

    // Mapear campos de la App a nombres de Excel
    final app = <String, double>{
      'C7_salarioUMAs': (salarioDiario / umaDiaria * 100).roundToDouble() / 100,
      'C12': factAsig.porcentajeCuantiaBasica,
      'C13': factAsig.cuantiaBasicaPorDia,
      'C15': factAsig.totalCuantiaBasicaAnual,
      'C20': factAsig.porcentajeIncremento,
      'C21': factAsig.incrementosDiarios,
      'C23': factAsig.incrementoAnual,
      'C24': factAsig.numeroIncrementosAnuales,
      'C25': factAsig.numeroIncrementosRedondeado,
      'C26': factAsig.totalIncrementosAnuales,
      'C30': factAsig.cuantiaTotalPensionVejez,
      'C34': factAsig.cuantiaTotalPensionVejez / 1.11,
      'C36': factAsig.asignacionEsposa,
      'C43': factAsig.asignacionHijos,
      'C49': factAsig.asignacionPadres,
      'B53': factAsig.cuantiaTotalAsignaciones,
      'C59': factAsig.totalAyudaAsistencial,
      'C67': factAsig.cuantiaMasAsignaciones,
      'C69': factAsig.asignacionDecretoPresidencial,
      'C72': factAsig.totalPensionAnual,
      'C74': factAsig.totalPensionMensual,
    };

    // ===== COMPARACIÓN =====
    print('\n=== COMPARACIÓN APP vs EXCEL (DATOS FRESCOS) ===\n');
    
    final camposAComparar = [
      'C7_salarioUMAs', 'C12', 'C13', 'C15', 'C20', 'C21', 'C23',
      'C24', 'C25', 'C26', 'C30',
      'C34', 'C36', 'C43', 'C49',
      'B53', 'C59', 'C67', 'C69', 'C72',
      'C74', // *** PENSION MENSUAL ***
    ];

    int pasaron = 0;
    int fallaron = 0;

    for (final campo in camposAComparar) {
      final appVal = app[campo]!;
      final excelVal = excel[campo]!;

      double tolerancia;
      if (campo == 'C7_salarioUMAs') tolerancia = 0.01;
      else if (campo == 'C12' || campo == 'C20') tolerancia = 0.001;
      else if (campo == 'C24') tolerancia = 0.01;
      else if (campo == 'C25') tolerancia = 0.1;
      else if (campo == 'C74') tolerancia = 1.0;
      else tolerancia = 1.0;

      final diff = (appVal - excelVal).abs();
      final ok = diff <= tolerancia;

      if (ok) {
        pasaron++;
      } else {
        fallaron++;
      }

      print('  ${ok ? "PASS" : "FAIL"} $campo: '
          'app=${appVal.toStringAsFixed(4)}, '
          'excel=${excelVal.toStringAsFixed(4)}, '
          'diff=${diff.toStringAsFixed(4)}'
          '${ok ? "" : " <<< DIFERENCIA"}');
    }

    print('\n=== RESULTADO: $pasaron pasaron, $fallaron fallaron ===\n');

    if (fallaron > 0) {
      print('=== ANÁLISIS DE DIFERENCIAS ===');
      
      // Verificar C24
      final c24manual = (semanasCotizadas - 500) / 52.0;
      print('C24 manual: ($semanasCotizadas - 500) / 52 = $c24manual');
      
      // Verificar C25 redondeo
      final intPart = c24manual.floor();
      final fracPart = c24manual - intPart;
      print('C25 intPart: $intPart, fracPart: $fracPart');
      print('  13/52 = ${13/52}, 27/52 = ${27/52}');
      
      double c25Esperado;
      if (fracPart >= 27/52) {
        c25Esperado = (intPart + 1).toDouble();
      } else if (fracPart >= 13/52) {
        c25Esperado = intPart + 0.5;
      } else {
        c25Esperado = intPart.toDouble();
      }
      print('C25 según Art 167: $c25Esperado');
      print('C25 app: ${app["C25"]}');
      print('C25 excel: ${excel["C25"]}');
      
      // Verificar C74
      print('\nC74 (pensión mensual):');
      print('  App: ${app["C74"]}');
      print('  Excel: ${excel["C74"]}');
      print('  Diferencia: ${(app["C74"]! - excel["C74"]!).abs()}');
    }

    // La pensión mensual debe coincidir dentro de $1
    expect(app['C74']!, closeTo(excel['C74']!, 1.0));
  });
}
