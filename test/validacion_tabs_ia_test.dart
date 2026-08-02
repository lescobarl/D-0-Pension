import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

void main() {
  // IMPORTANTE (hallazgo empírico): un segundo flujo completo
  // "buildProvider + pumpWidget" en el MISMO proceso de test se cuelga en
  // pumpWidget. Por eso TODAS las verificaciones de widgets se agrupan en
  // UN solo testWidgets (un único flujo completo por proceso).
  testWidgets('HomeTabs: IA Experta como 4ª pestaña (sin back)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final persistenceService = PersistenceService(prefs);
    final formulaEvaluator = FormulaEvaluator();
    final provider = RetroactiveProvider(
      evaluator: formulaEvaluator,
      persistence: persistenceService,
    );
    await provider.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: HomeTabsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // ── La pestaña "IA Experta" existe en el TabBar ──
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('IA Experta'),
      ),
      findsOneWidget,
    );

    // ── El botón flotante dorado "IA Experta" está en la esquina inferior ──
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('IA Experta'),
      ),
      findsOneWidget,
    );

    // ── Al tocar el botón flotante se muestra el chat (sin ruta nueva) ──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // El header del asistente debe estar visible
    expect(find.text('ASISTENTE DE PENSIÓN'), findsOneWidget);

    // ── Volver a Captura es por pestaña (sin botón back) ──
    await tester.tap(find.text('Captura'));
    await tester.pumpAndSettle();

    // La pantalla de captura vuelve a estar visible
    expect(find.text('Captura SIMPLIFICADA'), findsOneWidget);

    // ── El descargo sigue accesible desde el botón superior derecho ──
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Descargo de Responsabilidad'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('Descargo de Responsabilidad'), findsNothing);
  });
}
