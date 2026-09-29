import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/presentation/screens/license_screen.dart';
import 'package:d_0_pension/presentation/screens/payment_screen.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo D — Sin licencia: el usuario entra a [LicenseScreen] y no tiene
/// ninguna licencia → se le invita a ver planes → /payment.
///
/// Funcional:
///   1. Sin compras previas, la pantalla muestra el estado de "sin licencia".
///   2. No se muestran estados de expirada ni acceso a la calculadora.
///   3. 'Ver Planes' navega a /payment para adquirir una licencia.
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Flujo D: sin licencia → ver planes → pago', (tester) async {
    setGoldenSurface(tester);

    // Sesión existente (lopez) sin licencia en el dispositivo.
    SharedPreferences.setMockInitialValues({
      'user_accounts': jsonEncode([
        seedUserJson(username: 'lopez', password: '1234'),
      ]),
      'session_username': 'lopez',
      'onboarding_completed': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      buildFlowApp(prefs: prefs, billing: FakeBillingService()),
    );
    await pumpUntilFound(tester, find.text('Mi Licencia'));

    // 1) Pantalla de licencia sin licencia activa.
    expect(find.text('Mi Licencia'), findsOneWidget);
    expect(find.text('Sin Licencia'), findsOneWidget);
    expect(
      find.text(
        'No tienes una licencia activa. Adquiere una para acceder a todas las funcionalidades.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ver Planes'), findsOneWidget);

    // 2) Sin licencia → sin estados de expiración ni acceso a la calculadora.
    expect(find.text('Licencia Expirada'), findsNothing);
    expect(find.text('Licencia Activa'), findsNothing);
    expect(find.text('Ir a la Calculadora'), findsNothing);

    // 3) 'Ver Planes' → /payment.
    final verPlanes = find.text('Ver Planes');
    await tester.ensureVisible(verPlanes);
    await tester.tap(verPlanes);
    await pumpUntilFound(tester, find.text('Elige tu plan'));
    expect(find.byType(PaymentScreen), findsOneWidget);
    expect(find.text('Suscripción Semestral'), findsOneWidget);
  });
}
