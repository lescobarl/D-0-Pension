import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

void main() {
  // IMPORTANTE (hallazgo empírico): un segundo flujo completo
  // "buildProvider + pumpWidget" en el MISMO proceso de test se cuelga en
  // pumpWidget. Por eso TODAS las verificaciones de widgets se agrupan en
  // UN solo testWidgets (un único flujo completo por proceso).
  testWidgets('HomeTabs: IA Experta como 1ª pestaña (sin back)', (
    tester,
  ) async {
    // Superficie de ancho de teléfono (390x844 lógicos) para validar que el
    // header del chat no desborda en pantallas reales.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'disclaimer_seen': true});
    final prefs = await SharedPreferences.getInstance();
    final persistenceService = PersistenceService(prefs);
    final formulaEvaluator = FormulaEvaluator();
    final provider = RetroactiveProvider(
      evaluator: formulaEvaluator,
      persistence: persistenceService,
    );
    await provider.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RetroactiveProvider>.value(value: provider),
          ChangeNotifierProvider<PaymentProvider>(
            create: (_) => PaymentProvider(PlayBillingService(), prefs),
          ),
        ],
        child: const MaterialApp(home: HomeTabsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // ── La pestaña "IA Experta" existe en el TabBar y es la PRIMERA ──
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('IA Experta'),
      ),
      findsOneWidget,
    );

    // IA Experta es la 1ª pestaña: al iniciar la app el chat ya está visible
    // (sin tener que navegar), el acceso más amigable para personas mayores.
    expect(find.text('ASISTENTE DE PENSIÓN'), findsOneWidget);

    // ── El botón flotante dorado "IA Experta" está en la esquina inferior ──
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('IA Experta'),
      ),
      findsOneWidget,
    );

    // ── Tocar el botón flotante mantiene el chat visible (sin ruta nueva) ──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // El header del asistente debe estar visible
    expect(find.text('ASISTENTE DE PENSIÓN'), findsOneWidget);

    // El subtítulo y "Limpiar conversación" comparten el MISMO renglón (sin
    // fila extra que engrose el encabezado) y ambos son visibles sin overflow.
    final subtitleFinder = find.text(
      'Platícame tu situación y yo lleno los datos de la calculadora.',
    );
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
    // El TabBar no es desplazable: las 4 pestañas están siempre visibles en
    // el teléfono, así que "Captura" se toca directamente.
    final capturaTab = find.descendant(
      of: find.byType(TabBar),
      matching: find.text('Captura'),
    );
    await tester.tap(capturaTab);
    await tester.pumpAndSettle();

    // La pantalla de captura vuelve a estar visible
    expect(find.text('Captura SIMPLIFICADA'), findsOneWidget);

    // ── Botón "Acerca de" (círculo con i) en la esquina superior derecha ──
    expect(find.text('Acerca de'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // ── Abre el aviso con el aviso de no afiliación y el hipervínculo oficial ──
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Descargo de Responsabilidad'), findsOneWidget);
    expect(find.textContaining('NO es una aplicación oficial'), findsOneWidget);
    expect(find.text('https://www.gob.mx/imss'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('Descargo de Responsabilidad'), findsNothing);
  });
}
