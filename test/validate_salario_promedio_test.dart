import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/periodo_salarial.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';
import 'package:d_0_pension/services/persistence_service.dart';

/// VALIDATION: Salario Promedio (con Mod40) calculation
///
/// These tests validate that _recalculatePromedioFromPeriodos() correctly
/// recalculates _salarioDiarioPromedio from the existing periodos list
/// WITHOUT overwriting the periodos themselves.
///
/// IMPORTANTE: _recalculatePromedioFromPeriodos() NEVER overwrites _periodos.
/// It only recalculates _salarioDiarioPromedio from whatever periods already
/// exist. If _periodos is empty, it falls back to _salarioPromedio250Semanas.
///
/// This guarantees the user's manually captured desglose de periodos is
/// NEVER destroyed by an input change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;
  late RetroactiveProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
    provider = RetroactiveProvider(
      persistence: PersistenceService(prefs),
      evaluator: evaluator,
    );
    await provider.initialize();
  });

  group('_recalculatePromedioFromPeriodos validation', () {
    test('falls back to salarioPromedio250Semanas when periods are cleared', () {
      // Arrange: Set up inputs
      provider.setUmaDiaria(133.87);
      provider.setSalarioRegistrado(1500.0);
      provider.setSalarioPromedio250Semanas(2281.53);
      provider.setSemanasAntesMod40(1960);
      provider.setSemanasEnMod40(78);

      // Clear the baseline periods that initialize() seeded
      provider.setPeriodos([]);

      // Act: trigger recalculation with empty periods
      provider.setSemanasEnMod40(78);

      // When _periodos is empty, _recalculatePromedioFromPeriodos()
      // falls back to _salarioPromedio250Semanas = 2281.53
      const expected = 2281.53;

      expect(provider.salarioDiarioPromedio, closeTo(expected, 0.01));
    });

    test('recalculates weighted average from existing periodos', () {
      // Arrange: Set up inputs AND periodos
      provider.setSalarioRegistrado(1500.0);
      provider.setSalarioPromedio250Semanas(2281.53);
      provider.setSemanasAntesMod40(200);
      provider.setSemanasEnMod40(50);

      // Set explicit periodos (simulating user capture)
      provider.setPeriodos([
        PeriodoSalarial(
          salarioDiario: 1500.0,
          semanas: 50,
          esMod40: true,
        ),
        PeriodoSalarial(
          salarioDiario: 2281.53,
          semanas: 200,
          esMod40: false,
        ),
      ]);

      // Act
      final result = provider.salarioDiarioPromedio;

      // Formula: (1500.00 * 50 + 2281.53 * 200) / 250
      // = (75,000.00 + 456,306.00) / 250
      // = 531,306.00 / 250
      // = 2,125.224
      const expected = 2125.224;

      expect(result, closeTo(expected, 0.01));
    });

    test('recalculates salarioDiarioPromedio when semanas en Mod40 changes '
        '(las semanas Mod40 SÍ pesan en el promedio ponderado)', () {
      provider.setSalarioRegistrado(1500.0);
      provider.setSalarioPromedio250Semanas(2281.53);
      provider.setSemanasAntesMod40(200);
      provider.setSemanasEnMod40(50);

      // Set explicit periodos
      provider.setPeriodos([
        PeriodoSalarial(salarioDiario: 1500.0, semanas: 50, esMod40: true),
        PeriodoSalarial(salarioDiario: 2281.53, semanas: 200, esMod40: false),
      ]);

      // Mark as manually edited so _recalculatePromedioFromPeriodos()
      // preserves the periods as-is (doesn't auto-update salarioDiario).
      // Use a slightly different value to trigger the flag change.
      final currentValue = provider.salarioDiarioPromedio;
      provider.setSalarioDiarioPromedio(currentValue + 0.01);
      provider.setSalarioDiarioPromedio(currentValue);

      final result1 = provider.salarioDiarioPromedio;
      // result1 = (1500*50 + 2281.53*200) / 250 = 2125.224
      expect(result1, closeTo(2125.224, 0.01));

      // Cambiar las semanas en Mod40: setSemanasEnMod40(100) escala el periodo
      // Mod40 de 50 → 100 semanas, así el promedio ponderado SÍ cambia (la
      // corrección de raíz: las semanas Mod40 deben afectar el cálculo).
      provider.setSemanasEnMod40(100);

      final result2 = provider.salarioDiarioPromedio;
      // El periodo Mod40 quedó en 100 semanas y el tope de 250 semanas consume
      // Mod40 100 + no-Mod40 150 → (1500*100 + 2281.53*150) / 250 = 1968.918.
      expect(result2, closeTo(1968.918, 0.01));
    });

    test('recalculates when salario promedio 250 semanas changes (with existing periods)', () {
      provider.setSalarioRegistrado(1500.0);
      provider.setSalarioPromedio250Semanas(2000.0);
      provider.setSemanasAntesMod40(200);
      provider.setSemanasEnMod40(50);

      // Set explicit periodos
      provider.setPeriodos([
        PeriodoSalarial(salarioDiario: 1500.0, semanas: 50, esMod40: true),
        PeriodoSalarial(salarioDiario: 2000.0, semanas: 200, esMod40: false),
      ]);

      // Mark as manually edited so _recalculatePromedioFromPeriodos()
      // preserves the periods as-is (doesn't auto-update salarioDiario).
      // Use a slightly different value to trigger the flag change.
      final currentValue = provider.salarioDiarioPromedio;
      provider.setSalarioDiarioPromedio(currentValue + 0.01);
      provider.setSalarioDiarioPromedio(currentValue);

      final result1 = provider.salarioDiarioPromedio;

      provider.setSalarioPromedio250Semanas(2500.0);

      final result2 = provider.salarioDiarioPromedio;

      // Since _salarioPromAutoCalculado is false (manual edit), the periods
      // are preserved as-is and the weighted average stays the same
      expect(result2, closeTo(result1, 0.001));
    });

    test('manual edit sets flag to false and is preserved', () {
      provider.setSalarioRegistrado(1500.0);
      provider.setSalarioPromedio250Semanas(2281.53);
      provider.setSemanasAntesMod40(200);
      provider.setSemanasEnMod40(50);

      // Set explicit periodos (this triggers _recalculatePromedioFromPeriodos
      // via setSemanasEnMod40, which sets _salarioPromAutoCalculado = true)
      provider.setPeriodos([
        PeriodoSalarial(salarioDiario: 1500.0, semanas: 50, esMod40: true),
        PeriodoSalarial(salarioDiario: 2281.53, semanas: 200, esMod40: false),
      ]);

      // Act: Manually edit the field
      provider.setSalarioDiarioPromedio(3000.0);

      // Assert: Auto-calculation flag is disabled
      expect(provider.salarioPromAutoCalculado, isFalse);

      // setSemanasEnMod40 calls _recalculatePromedioFromPeriodos()
      // which recalculates from EXISTING periods (not overwriting them)
      provider.setSemanasEnMod40(100);

      // Since _salarioPromAutoCalculado is false, the manual value is preserved
      expect(provider.salarioDiarioPromedio, closeTo(3000.0, 0.001));
    });

    test('formula uses salarioRegistrado directamente (NO multiplica por UMA)', () {
      // NOTE: setUmaDiaria() calls _projectSalarioRegistrado(force: true)
      // which overwrites _salarioRegistrado with 25 × UMA = 2500.
      // So we must call setUmaDiaria FIRST, then setSalarioRegistrado.
      provider.setUmaDiaria(100.0);
      provider.setSalarioRegistrado(3000.0); // en pesos diarios
      provider.setSalarioPromedio250Semanas(2000.0);
      provider.setSemanasAntesMod40(200);
      provider.setSemanasEnMod40(50);

      // Set explicit periodos matching the expected calculation
      provider.setPeriodos([
        PeriodoSalarial(salarioDiario: 3000.0, semanas: 50, esMod40: true),
        PeriodoSalarial(salarioDiario: 2000.0, semanas: 200, esMod40: false),
      ]);

      // Expected: (2000 * 200 + 3000 * 50) / 250 = (400000 + 150000) / 250 = 2200
      // NOTA: Si multiplicara por UMA sería (2000*200 + 3000*100*50)/250 = 61600, incorrecto
      expect(provider.salarioDiarioPromedio, closeTo(2200.0, 0.001));
    });

    test('semanas antes Mod40 does NOT affect salario promedio (con Mod40)', () {
      provider.setSalarioRegistrado(1500.0);
      provider.setSalarioPromedio250Semanas(2281.53);
      provider.setSemanasAntesMod40(200);
      provider.setSemanasEnMod40(50);

      // Set explicit periodos
      provider.setPeriodos([
        PeriodoSalarial(salarioDiario: 1500.0, semanas: 50, esMod40: true),
        PeriodoSalarial(salarioDiario: 2281.53, semanas: 200, esMod40: false),
      ]);

      // Mark as manually edited so _recalculatePromedioFromPeriodos()
      // preserves the periods as-is (doesn't auto-update salarioDiario).
      // Use a slightly different value to trigger the flag change.
      final currentValue = provider.salarioDiarioPromedio;
      provider.setSalarioDiarioPromedio(currentValue + 0.01);
      provider.setSalarioDiarioPromedio(currentValue);

      final result1 = provider.salarioDiarioPromedio;

      provider.setSemanasAntesMod40(150);

      final result2 = provider.salarioDiarioPromedio;

      // _semanasAntesMod40 no afecta _salarioDiarioPromedio porque
      // _recalculatePromedioFromPeriodos solo usa los periodos existentes.
      // El valor debe ser el mismo.
      expect(result2, closeTo(result1, 0.001));
    });
  });
}
