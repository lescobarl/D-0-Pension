import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/app_metadata.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo F — Cuenta de VALIDACIÓN integrada (lescobar69): entra por login,
/// obtiene acceso libre configurado y aterriza en el shell de la calculadora.
///
/// Funcional: valida que `grantValidatorAccess` (vía el flujo normal de login)
/// concede la licencia de validación y navega a la raíz con el shell real.
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Flujo F: usuario de validación → home', (tester) async {
    setGoldenSurface(tester);

    SharedPreferences.setMockInitialValues({
      'disclaimer_seen': true,
      'onboarding_completed': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      buildFlowApp(
        prefs: prefs,
        billing: FakeBillingService(),
        builtinAccount: const BuiltinAccountConfig(
          enabled: true,
          username: 'lescobar69',
          password: '1234',
          licenseDays: 365,
        ),
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

    // 1) Login con la cuenta de validación integrada.
    await tester.enterText(find.byType(TextFormField).at(0), 'lescobar69');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    final acceder = find.widgetWithText(ElevatedButton, 'Acceder');
    await tester.ensureVisible(acceder);
    await tester.tap(acceder);

    // 2) Acceso libre concedido → shell real de la calculadora.
    await pumpUntilFound(tester, find.byType(TabBar));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(HomeTabsScreen), findsOneWidget);

    // 3) La licencia de validación quedó activa (producto semestral) y el acceso
    //    libre se registra a nivel dispositivo ('login_username'), sin sesión
    //    local (la cuenta de validación no crea un UserAccount).
    expect(prefs.getString('license_product_id'), kProductIdSemestral);
    expect(prefs.getString('license_expiry'), isNotNull);
    expect(prefs.getString('login_username'), 'lescobar69');
    expect(prefs.getString('session_username'), isNull);
  });
}
