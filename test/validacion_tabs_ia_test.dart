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
    // Superficie de ancho de teléfono (390x844 lógicos) para validar que el
    // header del chat no desborda en pantallas reales.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // El subtítulo y "Limpiar conversación" comparten el MISMO renglón (sin
    // fila extra que engrose el encabezado) y ambos son visibles sin overflow.
    final subtitleFinder =
        find.text('Platícame tu situación y yo lleno los datos de la calculadora.');
    final buttonFinder = find.text('Limpiar conversación');
    expect(subtitleFinder, findsOneWidget);
    expect(buttonFinder, findsOneWidget);
    // El ancestro Row más cercano del subtítulo ES el renglón del subtítulo
    // (el texto está dentro de un Expanded); el botón debe ser descendiente
    // de ese mismo renglón para confirmar que comparten línea.
    final subtitleRow = find
        .ancestor(of: subtitleFinder, matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: subtitleRow, matching: buttonFinder),
      findsOneWidget,
    );

    // ── Volver a Captura es por pestaña (sin botón back) ──
    // En ancho de teléfono (390px) el TabBar es desplazable: al estar en la
    // última pestaña (IA Experta), "Captura" queda fuera de pantalla. Se
    // asegura la visibilidad del tab antes de tocar, igual que haría el usuario.
    final capturaTab = find.descendant(
      of: find.byType(TabBar),
      matching: find.text('Captura'),
    );
    await tester.ensureVisible(capturaTab);
    await tester.pumpAndSettle();
    await tester.tap(capturaTab);
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
