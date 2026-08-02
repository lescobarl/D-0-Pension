/// Comprehensive integration test for the consolidated app.
///
/// Validates:
/// 1. Provider initialization loads all defaults correctly
/// 2. All 6 calculation models are non-null and internally consistent
/// 3. Cross-model consistency (e.g., pension values match across models)
/// 4. Edad de retiro changes propagate correctly to all dependent calculations
/// 5. Salario changes propagate correctly to all dependent calculations
/// 6. The consolidated views render without errors (widget test)
/// 7. Config view renders without errors (widget test)
///
/// Run with: flutter test test/integration_test.dart
library;

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/presentation/screens/captura_view.dart';
import 'package:d_0_pension/presentation/screens/config_view.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/presentation/screens/inversion_view.dart';
import 'package:d_0_pension/presentation/screens/pension_view.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RetroactiveProvider provider;
  late FormulaEvaluator evaluator;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final persistence = PersistenceService(prefs);
    evaluator = FormulaEvaluator();
    await evaluator.initialize();
    provider = RetroactiveProvider(
      evaluator: evaluator,
      persistence: persistence,
    );
    await provider.initialize();
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 1: Provider initialization integrity
  // ═══════════════════════════════════════════════════════════════
  group('1. Provider initialization integrity', () {
    test('All 6 calculation models are non-null after initialization', () {
      expect(provider.factAsigCalculation, isNotNull);
      expect(provider.pensionMod40Calculation, isNotNull);
      expect(provider.costoMod40Calculation, isNotNull);
      expect(provider.inversionCalculation, isNotNull);
      expect(provider.retroactiveCalculation, isNotNull);
      expect(provider.financiamientoCalculation, isNotNull);
    });

    test('Default input values are reasonable', () {
      expect(provider.salarioDiarioPromedio, greaterThan(0));
      expect(provider.umaDiaria, greaterThan(0));
      expect(provider.salarioMinimoDiario, greaterThan(0));
      expect(provider.pensionYear, greaterThan(2020));
      expect(provider.semanasCotizadas, greaterThan(0));
      expect(provider.edadRetiro, greaterThanOrEqualTo(60));
      expect(provider.edadRetiro, lessThanOrEqualTo(70));
    });

    test('Mod40 input values are reasonable', () {
      expect(provider.salarioRegistrado, greaterThan(0));
      expect(provider.startDate, isNotNull);
      expect(provider.endDate, isNotNull);
      expect(provider.startDate.isBefore(provider.endDate), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 2: Cross-model consistency
  // ═══════════════════════════════════════════════════════════════
  group('2. Cross-model consistency', () {
    test('Pension anual 100% matches FactAsig cuantiaTotalPensionVejez', () {
      final fact = provider.factAsigCalculation!;
      final pension = provider.pensionMod40Calculation!;
      expect(pension.pensionAnual100, closeTo(fact.cuantiaTotalPensionVejez, 0.01));
    });

    test('Pension mensual matches across FactAsig and PensionMod40', () {
      final fact = provider.factAsigCalculation!;
      final pension = provider.pensionMod40Calculation!;
      expect(pension.pensionMensual, closeTo(fact.totalPensionMensual, 0.01));
    });

    test('Inversion pensionMensualConMod40 matches PensionMod40 pensionMensual', () {
      final pension = provider.pensionMod40Calculation!;
      final inv = provider.inversionCalculation!;
      expect(inv.pensionMensualConMod40, closeTo(pension.pensionMensual, 0.01));
    });

    test('CostoMod40 inversionTotal matches Retroactive costoModalidad40', () {
      final costo = provider.costoMod40Calculation!;
      final retro = provider.retroactiveCalculation!;
      expect(retro.costoModalidad40, closeTo(costo.inversionTotal, 0.01));
    });

    test('Financiamiento inversionTotal matches Retroactive costoTotal', () {
      final retro = provider.retroactiveCalculation!;
      final fin = provider.financiamientoCalculation!;
      expect(fin.inversionTotal, closeTo(retro.costoTotal, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 3: Edad de retiro propagation
  // ═══════════════════════════════════════════════════════════════
  group('3. Edad de retiro propagation', () {
    test('Changing edadRetiro recalculates FactAsig and PensionMod40', () {
      // Default edad is 65 (100%), so first change to 60 (75%) to get a lower baseline
      provider.setEdadRetiro(60);
      final lowerPension = provider.pensionMod40Calculation!.pensionMensual;

      // Now change to 65 (100%) — pension should increase
      provider.setEdadRetiro(65);

      final fact = provider.factAsigCalculation!;
      final pension = provider.pensionMod40Calculation!;

      // At 65, porcentajePorEdad should be 1.0 (100%)
      expect(pension.porcentajePorEdad, closeTo(1.0, 0.01));
      // Pension should be higher than at 60 (75%)
      expect(pension.pensionMensual, greaterThan(lowerPension));
      // FactAsig should also reflect the new edad
      expect(fact.totalPensionMensual, greaterThan(lowerPension));
    });

    test('Changing edadRetiro recalculates Inversion', () {
      provider.setEdadRetiro(65);

      final inv = provider.inversionCalculation!;
      // Flujo hasta 80 should be less (fewer years: 80-65=15 vs 80-61=19)
      expect(inv.flujoHasta80ConMod40, lessThan(35000000));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 4: Salario propagation (the bug fix)
  // ═══════════════════════════════════════════════════════════════
  group('4. Salario propagation (bug fix validation)', () {
    test('setSalarioDiarioPromedio recalculates both FactAsig AND PensionMod40', () {
      final originalPensionMensual = provider.pensionMod40Calculation!.pensionMensual;

      // Increase salary significantly
      provider.setSalarioDiarioPromedio(3500.0);

      final fact = provider.factAsigCalculation!;
      final pension = provider.pensionMod40Calculation!;

      // Both should have increased (FactAsig uses _salarioDiarioPromedio directly)
      expect(fact.totalPensionMensual, greaterThan(originalPensionMensual));
      // PensionMod40 also uses _salarioDiarioPromedio via _recalculateFactAsig chain
      expect(pension.pensionMensual, greaterThan(originalPensionMensual));

      // They should still match each other
      expect(pension.pensionMensual, closeTo(fact.totalPensionMensual, 0.01));
    });

    test('setSalarioDiarioPromedio also recalculates Inversion', () {
      provider.setSalarioDiarioPromedio(3500.0);

      final inv = provider.inversionCalculation!;
      // pensionMensualConMod40 should have increased
      expect(inv.pensionMensualConMod40, greaterThan(70000));
    });

    test('setSalarioRegistrado recalculates CostoMod40 and Retroactive', () {
      final originalCosto = provider.costoMod40Calculation!.inversionTotal;

      provider.setSalarioRegistrado(4000.0);

      final costo = provider.costoMod40Calculation!;
      final retro = provider.retroactiveCalculation!;

      // Cost should be higher with higher registered salary
      expect(costo.inversionTotal, greaterThan(originalCosto));
      // Retroactive should reflect the new costo
      expect(retro.costoModalidad40, closeTo(costo.inversionTotal, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 5: Widget rendering - CapturaView
  // ═══════════════════════════════════════════════════════════════
  group('5. Widget rendering - CapturaView', () {
    testWidgets('CapturaView renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RetroactiveProvider>.value(
            value: provider,
            child: const CapturaView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CapturaView), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 6: Widget rendering - PensionView
  // ═══════════════════════════════════════════════════════════════
  group('6. Widget rendering - PensionView', () {
    testWidgets('PensionView renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RetroactiveProvider>.value(
            value: provider,
            child: const PensionView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PensionView), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 7: Widget rendering - InversionView
  // ═══════════════════════════════════════════════════════════════
  group('7. Widget rendering - InversionView', () {
    testWidgets('InversionView renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RetroactiveProvider>.value(
            value: provider,
            child: const InversionView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(InversionView), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 8: Widget rendering - ConfigView
  // ═══════════════════════════════════════════════════════════════
  group('8. Widget rendering - ConfigView', () {
    testWidgets('ConfigView renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RetroactiveProvider>.value(
            value: provider,
            child: const ConfigView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ConfigView), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 9: Widget rendering - HomeTabsScreen
  // ═══════════════════════════════════════════════════════════════
  group('9. Widget rendering - HomeTabsScreen', () {
    testWidgets('HomeTabsScreen renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RetroactiveProvider>.value(
            value: provider,
            child: const HomeTabsScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(HomeTabsScreen), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 10: Cross-model recalculation chain
  // ═══════════════════════════════════════════════════════════════
  group('10. Cross-model recalculation chain', () {
    test('Changing UMA triggers full recalculation chain', () {
      final originalPension = provider.pensionMod40Calculation!.pensionMensual;

      provider.setUmaDiaria(120.0);

      // UMA change should affect FactAsig (cuantia basica uses UMA)
      final fact = provider.factAsigCalculation!;
      expect(fact.cuantiaBasicaPorDia, greaterThan(0));

      // Pension should have changed
      final pension = provider.pensionMod40Calculation!;
      expect(pension.pensionMensual, isNot(closeTo(originalPension, 0.01)));
    });

    test('Changing startDate recalculates CostoMod40', () {
      final originalCosto = provider.costoMod40Calculation!.inversionTotal;

      provider.setStartDate(DateTime(2020, 1, 1));

      final costo = provider.costoMod40Calculation!;
      // Cost should be different with different start date
      expect(costo.inversionTotal, isNot(closeTo(originalCosto, 0.01)));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 11: Edge cases and boundary conditions
  // ═══════════════════════════════════════════════════════════════
  group('11. Edge cases and boundary conditions', () {
    test('EdadRetiro=60 gives correct percentage (Art. 168 LSS)', () {
      provider.setEdadRetiro(60);
      // 60 years = 75% (Art. 168 LSS: 60 years = 75%)
      expect(provider.pensionMod40Calculation!.porcentajePorEdad, closeTo(0.75, 0.01));
    });

    test('EdadRetiro=65 gives 100%', () {
      provider.setEdadRetiro(65);
      expect(provider.pensionMod40Calculation!.porcentajePorEdad, closeTo(1.0, 0.01));
    });

    test('EdadRetiro=70 gives 100% (max cap)', () {
      provider.setEdadRetiro(70);
      expect(provider.pensionMod40Calculation!.porcentajePorEdad, closeTo(1.0, 0.01));
    });

    test('Zero hijos means no asignacion hijos', () {
      provider.setNumeroHijos(0);
      final fact = provider.factAsigCalculation!;
      expect(fact.asignacionHijos, closeTo(0, 0.01));
    });

    test('TieneEsposa=true adds asignacion esposa', () {
      provider.setTieneEsposa(true);
      final fact = provider.factAsigCalculation!;
      expect(fact.asignacionEsposa, greaterThan(0));
    });

    test('Multiple hijos increases asignacion proportionally', () {
      provider.setNumeroHijos(2);
      final fact2 = provider.factAsigCalculation!;

      provider.setNumeroHijos(1);
      final fact1 = provider.factAsigCalculation!;

      // 2 hijos should be roughly double 1 hijo
      expect(fact2.asignacionHijos, closeTo(fact1.asignacionHijos * 2, fact1.asignacionHijos * 0.1));
    });

    test('SalarioDiarioPromedio=0 does not crash', () {
      // Should handle gracefully without throwing
      provider.setSalarioDiarioPromedio(0);
      // Values should be 0 or very small
      expect(provider.factAsigCalculation!.totalPensionMensual, lessThan(1));
    });
  });
}
