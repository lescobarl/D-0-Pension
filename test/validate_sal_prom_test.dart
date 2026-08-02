import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/models/periodo_salarial.dart';

void main() {
  group('Validación Salario Promedio vs Excel', () {
    test('Caso 2 periodos (auto-projection) debe dar \$2,569.41', () {
      // Mismos inputs que Excel base_user scenario
      final salarioRegistrado = 3202.63631875;
      final semanasEnMod40 = 78.14285714285714;
      final salarioPromedio250Semanas = 2281.531142857143;
      final totalSemanasPromedio = 250;

      final semanasRestantes = totalSemanasPromedio - semanasEnMod40; // 171.8571

      final periodos = [
        PeriodoSalarial(
          salarioDiario: salarioRegistrado,
          semanas: semanasEnMod40,
          esMod40: true,
        ),
        PeriodoSalarial(
          salarioDiario: salarioPromedio250Semanas,
          semanas: semanasRestantes,
          esMod40: false,
        ),
      ];

      final sumaResultados =
          periodos.fold<double>(0, (sum, p) => sum + p.resultado);
      final promedio = sumaResultados / totalSemanasPromedio;

      print('=== Validación 2 periodos (auto-projection) ===');
      print('Periodo Mod40: \$${salarioRegistrado.toStringAsFixed(4)} × ${semanasEnMod40.toStringAsFixed(4)} sem = \$${periodos[0].resultado.toStringAsFixed(2)}');
      print('Periodo Rest:  \$${salarioPromedio250Semanas.toStringAsFixed(4)} × ${semanasRestantes.toStringAsFixed(4)} sem = \$${periodos[1].resultado.toStringAsFixed(2)}');
      print('Suma Resultados: \$${sumaResultados.toStringAsFixed(2)}');
      print('Promedio (÷250): \$${promedio.toStringAsFixed(4)}');
      print('');

      // Valor exacto calculado: SUMA($642,360.58) / 250 = $2,569.4423
      expect(promedio, closeTo(2569.4423, 0.0001));
    });

    test('Caso 5 periodos (Excel SAL. PROM MOD 40) debe dar \$2,840.62', () {
      // Los mismos periodos que tiene Excel en SAL. PROM MOD 40 rows 22-26
      // Row 22: Mod40 (3064.72375, 134.7142857143 sem)
      // Row 23: 2026-02-01 to 2026-02-10 (2932.75, 1.4285714286 sem)
      // Row 24: 2025-02-01 to 2026-02-01 (2714.25, 52.2857142857 sem)
      // Row 25: 2024-02-01 to 2025-02-01 (2500.00, 52.4285714286 sem)
      // Row 26: 2023-02-01 to 2024-02-01 (2200.00, 9.1428571429 sem)
      // Rows 27-29 have 0 semanas so they are excluded.
      final periodos = [
        PeriodoSalarial(salarioDiario: 3064.72375, semanas: 134.7142857143, esMod40: true),
        PeriodoSalarial(salarioDiario: 2932.75, semanas: 1.4285714286, esMod40: false),
        PeriodoSalarial(salarioDiario: 2714.25, semanas: 52.2857142857, esMod40: false),
        PeriodoSalarial(salarioDiario: 2500.00, semanas: 52.4285714286, esMod40: false),
        PeriodoSalarial(salarioDiario: 2200.00, semanas: 9.1428571429, esMod40: false),
      ];

      final totalSemanas = periodos.fold<double>(0, (sum, p) => sum + p.semanas);
      final sumaResultados =
          periodos.fold<double>(0, (sum, p) => sum + p.resultado);
      final promedio = sumaResultados / 250;

      print('=== Validación 5 periodos (Excel SAL. PROM MOD 40) ===');
      for (int i = 0; i < periodos.length; i++) {
        final p = periodos[i];
        print('Periodo ${i + 1}: \$${p.salarioDiario.toStringAsFixed(4)} × ${p.semanas.toStringAsFixed(4)} sem = \$${p.resultado.toStringAsFixed(2)}');
      }
      print('Total semanas: ${totalSemanas.toStringAsFixed(4)}');
      print('Suma Resultados: \$${sumaResultados.toStringAsFixed(2)}');
      print('Promedio (÷250): \$${promedio.toStringAsFixed(4)}');
      print('');

      // Debe coincidir con Excel E19 = 2840.6157121429
      expect(promedio, closeTo(2840.6157, 0.0001));
      expect(totalSemanas, closeTo(250, 0.01));
    });

    test('Validar que el desglose capturado manualmente da el mismo resultado que Excel', () {
      // Simula que el usuario captura los 5 periodos exactos de Excel SAL. PROM MOD 40
      final periodos = [
        PeriodoSalarial(salarioDiario: 3064.72375, semanas: 134.7142857143, esMod40: true),
        PeriodoSalarial(salarioDiario: 2932.75, semanas: 1.4285714286, esMod40: false),
        PeriodoSalarial(salarioDiario: 2714.25, semanas: 52.2857142857, esMod40: false),
        PeriodoSalarial(salarioDiario: 2500.00, semanas: 52.4285714286, esMod40: false),
        PeriodoSalarial(salarioDiario: 2200.00, semanas: 9.1428571429, esMod40: false),
      ];

      final sumaResultados =
          periodos.fold<double>(0, (sum, p) => sum + p.resultado);
      final promedio = sumaResultados / 250;

      // Excel E19 value from SAL. PROM MOD 40
      const excelE19 = 2840.6157121429;

      print('=== Validación contra Excel E19 ===');
      print('App (desglose manual): \$${promedio.toStringAsFixed(10)}');
      print('Excel E19:             \$${excelE19.toStringAsFixed(10)}');
      print('Diferencia:            \$${(promedio - excelE19).abs().toStringAsFixed(10)}');
      print('');

      // Debe coincidir exactamente con Excel
      expect(promedio, closeTo(excelE19, 0.001));
    });
  });
}
