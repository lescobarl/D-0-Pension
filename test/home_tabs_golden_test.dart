import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/theme/app_theme.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Golden del shell completo de la app: AppBar (nombre de la app + icono),
/// TabBar de 4 pestañas y el cuerpo de la pestaña Captura, con el
/// RetroactiveProvider real inicializado desde metadata (como widget_test).
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('home tabs shell matches golden (pixel-perfect)',
      (tester) async {
    setGoldenSurface(tester);

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
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.fromConfig(null),
          home: const HomeTabsScreen(),
        ),
      ),
    );

    // Espera a que el provider termine de inicializar (sale del spinner).
    await pumpUntilFound(tester, find.byType(TabBar));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await expectLater(
      find.byType(HomeTabsScreen),
      matchesGoldenFile('goldens/home_tabs_shell.png'),
    );
  });
}
