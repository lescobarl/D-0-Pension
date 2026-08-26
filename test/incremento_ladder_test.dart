import 'package:flutter_test/flutter_test.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/pension_calculation.dart';
import 'package:d_0_pension/services/retroactive/incremento_ladder.dart';

import 'incremento_ladder_test_helpers.dart';

/// Pruebas unitarias del motor de asesoría "Escalón de tus Incrementos".
///
/// Las reglas (FinancialRules) se cargan desde la metadata real del bundle
/// (assets/config/app_metadata.json) vía [FormulaEvaluator.initialize()], de
/// modo que los valores esperados derivan de la misma configuración que usa la
/// app (aguinaldo_factor 1.11, weeks_per_year 52, min_weeks 500, umbrales
/// 13/52 y 27/52) — nada hardcodeado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormulaEvaluator evaluator;

  setUpAll(() async {
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
  });

  group('IncrementoLadder.compute', () {
    test('Escenario A: 2090.29 semanas → 31.0 incrementos, piso 2087, '
        'recortables 3.29 y siguiente en 2125', () {
      final rules = evaluator.metadata.financialRules;

      final advice = IncrementoLadder.compute(
        rules: rules,
        semanasTotales: 2090.29,
        semanasEnMod40: 130.29,
        factAsig: buildFactAsig(),
        pensionMod40: buildPensionMod40(),
        costoMod40: buildCostoMod40(),
        pensionYear: 2029,
      );

      // Estado del escalón.
      expect(advice.incrementosActuales, 31.0);
      expect(advice.siguienteIncremento, 31.5);
      expect(advice.incrementosAnteriores, 30.5);

      // Pisos (derivados de la metadata, sin hardcode).
      expect(advice.pisoActualSemanas, closeTo(2087, 0.001));
      expect(advice.pisoSiguienteSemanas, closeTo(2125, 0.001));
      expect(advice.pisoAnteriorSemanas, closeTo(2073, 0.001));

      // Subir / recortar.
      expect(advice.semanasParaSiguiente, closeTo(34.71, 0.01));
      expect(advice.semanasRecortablesSinPerder, closeTo(3.29, 0.01));

      // Valores monetarios.
      expect(advice.beneficioIncrementoCompletoMensual, closeTo(1917.25, 0.01));
      expect(advice.beneficioMedioIncrementoMensual, closeTo(958.63, 0.01));
      expect(advice.costoPorSemanaM40, closeTo(3970.09, 0.01));
      expect(advice.ahorroEstimado, closeTo(13061.59, 0.01));

      // Regla de decisión (subir / dejar de aportar).
      expect(advice.semanasPorMes, closeTo(52 / 12, 1e-9));
      expect(advice.recomiendaSubir, isFalse);
      expect(advice.costoParaSubir, closeTo(34.71 * 3970.09, 1.0));
      expect(advice.mesesParaSubir, closeTo(34.71 / (52 / 12), 0.01));

      // Regla (Art. 167).
      expect(advice.fraccionMedioIncremento, closeTo(13 / 52, 1e-9));
      expect(advice.fraccionIncrementoCompleto, closeTo(27 / 52, 1e-9));
    });

    test('Escenario B: 2080 semanas → 30.5 incrementos, piso 2073 y siguiente '
        'en 2087 (7 semanas exactas para ambos caminos)', () {
      final rules = evaluator.metadata.financialRules;

      final advice = IncrementoLadder.compute(
        rules: rules,
        semanasTotales: 2080,
        semanasEnMod40: 26,
        factAsig: buildFactAsig(numeroIncrementosRedondeado: 30.5),
        pensionMod40: buildPensionMod40(),
        costoMod40: buildCostoMod40(),
        pensionYear: 2029,
      );

      expect(advice.incrementosActuales, 30.5);
      expect(advice.siguienteIncremento, 31.0);
      expect(advice.pisoActualSemanas, closeTo(2073, 0.001));
      expect(advice.pisoSiguienteSemanas, closeTo(2087, 0.001));
      expect(advice.semanasParaSiguiente, closeTo(7.0, 0.001));
      expect(advice.semanasRecortablesSinPerder, closeTo(7.0, 0.001));

      // Regla de decisión: 7 semanas > ~1 mes (4.33) → no conviene subir.
      expect(advice.recomiendaSubir, isFalse);
      expect(advice.mesesParaSubir, closeTo(7.0 / (52 / 12), 0.001));
      expect(advice.costoParaSubir, closeTo(7.0 * 3970.09, 1.0));
    });

    test(
      'Conviene SUBIR cuando falta poco (≤ ~1 mes) al siguiente escalón',
      () {
        final rules = evaluator.metadata.financialRules;

        // 2084 semanas: piso de 31.0 en la semana 2087 → faltan 3.0 semanas
        // (menos de un mes de aportación), así que sí conviene subir.
        final advice = IncrementoLadder.compute(
          rules: rules,
          semanasTotales: 2084,
          semanasEnMod40: 24,
          factAsig: buildFactAsig(numeroIncrementosRedondeado: 30.5),
          pensionMod40: buildPensionMod40(),
          costoMod40: buildCostoMod40(),
          pensionYear: 2029,
        );

        expect(advice.incrementosActuales, 30.5);
        expect(advice.siguienteIncremento, 31.0);
        expect(advice.pisoSiguienteSemanas, closeTo(2087, 0.001));
        expect(advice.semanasParaSiguiente, closeTo(3.0, 0.001));
        expect(advice.semanasPorMes, closeTo(52 / 12, 1e-9));
        expect(advice.recomiendaSubir, isTrue);
        expect(advice.costoParaSubir, closeTo(3.0 * 3970.09, 1.0));
        expect(advice.mesesParaSubir, closeTo(3.0 / (52 / 12), 0.001));
      },
    );

    test('Sin costo Mod40 el costo semanal y el ahorro estimado son 0', () {
      final rules = evaluator.metadata.financialRules;

      final advice = IncrementoLadder.compute(
        rules: rules,
        semanasTotales: 2090.29,
        semanasEnMod40: 130.29,
        factAsig: buildFactAsig(),
        pensionMod40: buildPensionMod40(),
        costoMod40: null,
        pensionYear: 2029,
      );

      expect(advice.costoPorSemanaM40, 0);
      expect(advice.ahorroEstimado, 0);
      expect(advice.costoParaSubir, 0);
      expect(advice.recomiendaSubir, isFalse);
      // El resto de la asesoría sigue calculándose.
      expect(advice.semanasRecortablesSinPerder, closeTo(3.29, 0.01));
      expect(advice.beneficioMedioIncrementoMensual, closeTo(958.63, 0.01));
    });

    test('Las semanas recortables se limitan a las semanas realmente pagadas '
        'en Mod40 (nunca más de las que existen)', () {
      final rules = evaluator.metadata.financialRules;

      final advice = IncrementoLadder.compute(
        rules: rules,
        semanasTotales: 2090.29,
        semanasEnMod40: 2.0,
        factAsig: buildFactAsig(),
        pensionMod40: buildPensionMod40(),
        costoMod40: buildCostoMod40(),
        pensionYear: 2029,
      );

      // 2090.29 − 2087 = 3.29 teóricas, pero solo se pagan 2.0 Mod40.
      expect(advice.semanasRecortablesSinPerder, closeTo(2.0, 0.001));
      expect(advice.ahorroEstimado, closeTo(2.0 * 3970.09, 1.0));
    });

    test('El costo semanal se toma del año de pensión correcto en la tabla '
        'de costos (varios años)', () {
      final rules = evaluator.metadata.financialRules;

      // Filas de 2027 (tasa 0.16) y 2029 (tasa 0.17709).
      final costo2027 = buildCostoMod40(
        tasa: 0.16,
        salarioRegistrado: 3000.0,
        yearStart: 2027,
        yearEnd: 2028,
      );
      final costo2029 = buildCostoMod40(
        tasa: 0.17709,
        salarioRegistrado: 3202.64,
        yearStart: 2029,
        yearEnd: null,
      );
      final costoMod40 = CostoMod40Calculation(
        yearlyCosts: [...costo2027.yearlyCosts, ...costo2029.yearlyCosts],
        inversionTotal: 0,
        recuperacionAfore: 0,
        inversionNeta: 0,
      );

      final advice = IncrementoLadder.compute(
        rules: rules,
        semanasTotales: 2090.29,
        semanasEnMod40: 130.29,
        factAsig: buildFactAsig(),
        pensionMod40: buildPensionMod40(),
        costoMod40: costoMod40,
        pensionYear: 2029,
      );

      // Debe usar la fila de 2029 (0.17709 × 3202.64 × 7).
      expect(advice.costoPorSemanaM40, closeTo(3970.09, 0.01));
    });
  });
}
