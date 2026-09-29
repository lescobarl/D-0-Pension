import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/theme/app_theme.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/presentation/screens/inversion_view.dart';
import 'package:d_0_pension/presentation/screens/pension_view.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Capturas de la ficha de la tienda (Play Store) en formato **9:16 exacto**:
/// 1080×1920 píxeles físicos (dpr 3.0 → 360×640 lógicos, escala natural de
/// teléfono).
///
/// NOTA IMPORTANTE sobre la resolución del dorado: este Flutter usa
/// `layer.toImage(renderObject.paintBounds)` (sin `pixelRatio`), por lo que el
/// PNG dorado se escribe a resolución LÓGICA (360×640), NO a 1080×1920. Para
/// obtener el PNG físico 1080×1920 se aplica un upscale 3× entero (replica
/// exacta de lo que renderiza un dispositivo 1080×1920/dpr 3.0):
///   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/upscale_screenshots.ps1
/// (genera los PNG finales en `capturas_tienda/`).
///
/// Pantallas capturadas (según la solicitud: Captura/Escenarios, Pensión, IA y
/// valores por defecto — todos los valores por defecto viven en la pestaña
/// "Captura", pre-cargada con `default_values`):
///   01_captura.png   → Captura de datos / Escenarios (valores por defecto).
///   02_pension.png   → Resultado de pensión Ley 73.
///   03_ia.png        → Asistente IA Experta.
///   04_inversion.png → Inversión (Modalidad 40 / costo-beneficio).
///
/// Regenerar (ambos pasos):
///   1) flutter test test/capturas_tienda_test.dart --update-goldens
///   2) powershell -NoProfile -ExecutionPolicy Bypass -File scripts/upscale_screenshots.ps1
///
/// IMPORTANTE (hallazgo empírico de validacion_tabs_ia_test.dart): un segundo
/// flujo completo "buildProvider + pumpWidget" en el MISMO proceso se cuelga en
/// pumpWidget. Por eso las 4 capturas se realizan en UN solo testWidgets,
/// cambiando de pestaña entre captura y captura.
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Capturas ficha tienda 9:16 — 1080x1920 (4 pantallas)', (
    tester,
  ) async {
    // Superficie determinista 9:16: física 1080×1920, dpr 3.0 → 360×640 lógicos.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'disclaimer_seen': true});
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
          ChangeNotifierProvider<PaymentProvider>(
            create: (_) => PaymentProvider(PlayBillingService(), prefs),
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
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // El AppBar muestra el nombre oficial de la app (proveniente de metadata).
    expect(find.text('Calculadora Pensión Ley 73 IA'), findsOneWidget);

    // Helper para localizar una pestaña dentro del TabBar (fill, no
    // desplazable: las 4 pestañas quedan siempre visibles en el teléfono).
    Finder tab(String label) =>
        find.descendant(of: find.byType(TabBar), matching: find.text(label));

    // ─────────────────────────────────────────────────────────────
    // 1) CAPTURA (Escenarios + valores por defecto)
    // ─────────────────────────────────────────────────────────────
    // La 1ª pestaña es "IA Experta" (acceso amigable por defecto); se navega
    // a Captura con su pestaña antes de validar/capturar (mismo patrón que
    // validacion_tabs_ia_test.dart).
    await tester.tap(tab('Captura'));
    await tester.pumpAndSettle();
    expect(find.text('Captura SIMPLIFICADA'), findsOneWidget);
    await expectLater(
      find.byType(HomeTabsScreen),
      matchesGoldenFile('store_screenshots/01_captura.png'),
    );

    // ─────────────────────────────────────────────────────────────
    // 2) PENSIÓN (resultado Ley 73)
    // ─────────────────────────────────────────────────────────────
    // NOTA: hay que asentar el cambio de pestaña con pumpAndSettle() (no con un
    // pump(450ms) fijo): aunque el TabController cambia de índice al instante,
    // la transición del TabBarView no termina con un solo pump, y el golden
    // capturaría todavía el cuerpo de Captura (bug "la de pensión es igual a la
    // de captura"). Este patrón es el que ya usa validacion_tabs_ia_test.dart.
    await tester.ensureVisible(tab('Pensión'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Pensión'));
    await tester.pumpAndSettle();
    // Prueba de que el cuerpo SÍ cambió de pestaña (no es una repetición).
    expect(find.text('Captura SIMPLIFICADA'), findsNothing);
    expect(find.byType(PensionView), findsOneWidget);
    await expectLater(
      find.byType(HomeTabsScreen),
      matchesGoldenFile('store_screenshots/02_pension.png'),
    );

    // ─────────────────────────────────────────────────────────────
    // 3) IA EXPERA (asistente) — botón flotante
    // ─────────────────────────────────────────────────────────────
    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntilFound(tester, find.text('ASISTENTE DE PENSIÓN'));
    await tester.pump(const Duration(milliseconds: 250));
    await expectLater(
      find.byType(HomeTabsScreen),
      matchesGoldenFile('store_screenshots/03_ia.png'),
    );

    // ─────────────────────────────────────────────────────────────
    // 4) INVERSIÓN (Modalidad 40 / costo-beneficio)
    // ─────────────────────────────────────────────────────────────
    await tester.ensureVisible(tab('Inversión'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Inversión'));
    await tester.pumpAndSettle();
    // Prueba de que el cuerpo SÍ cambió a Inversión (no repite la IA).
    expect(find.byType(InversionView), findsOneWidget);
    await expectLater(
      find.byType(HomeTabsScreen),
      matchesGoldenFile('store_screenshots/04_inversion.png'),
    );
  });
}
