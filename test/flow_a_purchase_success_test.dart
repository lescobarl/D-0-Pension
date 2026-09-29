import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/presentation/screens/payment_screen.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo A — Usuario NUEVO: registro → compra verificada → pantalla de ÉXITO
/// con cuenta materializada y sesión abierta (golden 08_pago_exito).
///
/// Funcional:
///   1. El pago (fake verificado) activa la licencia en el dispositivo.
///   2. El checkout diferido crea la cuenta y abre sesión.
///   3. La pantalla de éxito saluda al usuario (sin 'Vincular a mi cuenta',
///      porque ya hay sesión).
///   4. 'Ir a la Calculadora' navega a la raíz ('/' → [HomeStub]).
/// Visual: golden 9:16 → test/store_screenshots/08_pago_exito.png.
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Flujo A: compra verificada → éxito con sesión (golden 08)', (
    tester,
  ) async {
    // Superficie determinista 9:16: física 1080×1920, dpr 3.0 → 360×640 lógicos.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      buildFlowApp(
        prefs: prefs,
        billing: FakeBillingService(),
        home: const HomeStub(),
        initialRoute: '/login',
      ),
    );
    await tester.pump();

    // 1) Registrarse como usuario nuevo.
    final toggle = find.text('¿No tienes cuenta? Regístrate');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'nuevouser');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    await tester.enterText(find.byType(TextFormField).at(2), '1234');
    final crear = find.widgetWithText(ElevatedButton, 'Crear cuenta');
    await tester.ensureVisible(crear);
    await tester.tap(crear);

    // 2) Comprar el plan semestral.
    await pumpUntilFound(tester, find.text('Comprar Suscripción Semestral'));
    await tester.ensureVisible(find.text('Comprar Suscripción Semestral'));
    await tester.tap(find.text('Comprar Suscripción Semestral'));

    // 3) Esperar el éxito CON sesión establecida (la pantalla de éxito se pinta
    //    antes de que el checkout diferido termine de crear la cuenta).
    await pumpUntilFound(tester, find.textContaining('nuevouser'));
    expect(find.text('¡Licencia Activada!'), findsOneWidget);
    expect(find.text('Ir a la Calculadora'), findsOneWidget);
    expect(find.text('Vincular a mi cuenta'), findsNothing);
    expect(
      find.textContaining('nuevouser'),
      findsWidgets,
      reason: 'la pantalla de éxito saluda a la sesión recién creada',
    );

    // 4) La licencia quedó guardada y la cuenta materializada.
    expect(prefs.getString('license_product_id'), kProductIdSemestral);
    expect(prefs.getString('license_expiry'), isNotNull);
    final semExpiry = DateTime.parse(prefs.getString('license_expiry')!);
    final semDays = semExpiry.difference(DateTime.now()).inDays;
    expect(
      semDays,
      inInclusiveRange(179, 180),
      reason: 'la suscripción semestral dura 180 días (6 meses)',
    );
    final accounts = jsonDecode(prefs.getString('user_accounts')!) as List;
    expect(accounts, hasLength(1));
    expect((accounts.first as Map<String, dynamic>)['username'], 'nuevouser');
    expect(prefs.getString('session_username'), 'nuevouser');

    // 5) Golden 9:16.
    await expectLater(
      find.byType(PaymentScreen),
      matchesGoldenFile('store_screenshots/08_pago_exito.png'),
    );

    // 6) 'Ir a la Calculadora' navega a la raíz.
    await tester.tap(find.text('Ir a la Calculadora'));
    await pumpUntilFound(tester, find.text('HOME_STUB_OK'));
  });
}
