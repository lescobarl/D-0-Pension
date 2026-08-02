import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

void main() {
  testWidgets('App loads and displays tabs', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final persistenceService = PersistenceService(prefs);
    final formulaEvaluator = FormulaEvaluator();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => RetroactiveProvider(
              evaluator: formulaEvaluator,
              persistence: persistenceService,
            )..initialize(),
          ),
        ],
        child: const MaterialApp(
          home: HomeTabsScreen(),
        ),
      ),
    );

    // Verify the app loads without errors
    expect(find.byType(HomeTabsScreen), findsOneWidget);
  });
}
