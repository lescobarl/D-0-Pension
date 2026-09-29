import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo B — Usuario EXISTENTE con licencia vigente: login → entra directo al
/// shell de la calculadora ([HomeTabsScreen]) sin pasar por pago ni licencia.
///
/// Funcional: valida que una cuenta sembrada con licencia válida autentica y
/// aterriza en la raíz, con el RetroactiveProvider inicializado (sin spinner).
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Flujo B: usuario existente con licencia → home', (tester) async {
    setGoldenSurface(tester);

    // Cuenta existente con licencia semestral vigente (30 días).
    final expiry = DateTime.now().add(const Duration(days: 30));
    SharedPreferences.setMockInitialValues({
      'user_accounts': jsonEncode([
        seedUserJson(
          username: 'lopez',
          password: '1234',
          licenseExpiry: expiry,
          purchasedProductId: kProductIdSemestral,
        ),
      ]),
      'session_username': 'lopez',
      'license_expiry': expiry.toIso8601String(),
      'license_product_id': kProductIdSemestral,
      'onboarding_completed': true,
      'disclaimer_seen': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      buildFlowApp(
        prefs: prefs,
        billing: FakeBillingService(),
        home: const HomeTabsScreen(),
        initialRoute: '/login',
        extraProviders: [
          ChangeNotifierProvider(
            create: (_) => RetroactiveProvider(
              evaluator: FormulaEvaluator(),
              persistence: PersistenceService(prefs),
            )..initialize(),
          ),
        ],
      ),
    );
    await tester.pump();

    // 1) Login con credenciales de la cuenta sembrada.
    await tester.enterText(find.byType(TextFormField).at(0), 'lopez');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    final acceder = find.widgetWithText(ElevatedButton, 'Acceder');
    await tester.ensureVisible(acceder);
    await tester.tap(acceder);

    // 2) Tras autenticar, '/' resuelve al shell real de la calculadora.
    await pumpUntilFound(tester, find.byType(TabBar));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(HomeTabsScreen), findsOneWidget);

    // 3) La sesión quedó abierta para la cuenta 'lopez'.
    expect(prefs.getString('session_username'), 'lopez');
  });
}
