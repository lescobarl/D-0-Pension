import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/services/billing/play_billing_service.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo A — variante: el dispositivo YA tiene una licencia válida y un usuario
/// nuevo se registra → la pantalla de pago ofrece 'Vincular licencia a mi
/// cuenta' (sin pagar de nuevo). Al vincular, la cuenta se crea y se abre
/// sesión → navega a la raíz ('/' → [HomeStub]).
///
/// Funcional: valida la materialización diferida de la cuenta (checkout
/// diferido) reutilizando la licencia del dispositivo.
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Flujo A: vincular licencia de dispositivo a cuenta nueva', (
    tester,
  ) async {
    // Licencia semestral válida (60 días) ya presente en el dispositivo.
    final expiry = DateTime.now().add(const Duration(days: 60));
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'license_expiry': expiry.toIso8601String(),
      'license_product_id': kProductIdSemestral,
    });
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

    // 1) Registrarse como usuario nuevo (0=Usuario, 1=Contraseña, 2=Confirmar).
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

    // 2) Al llegar a /payment, el botón de vincular SÍ está presente porque el
    //    dispositivo ya tiene una licencia válida.
    await pumpUntilFound(tester, find.text('Vincular licencia a mi cuenta'));
    expect(find.text('Vincular licencia a mi cuenta'), findsOneWidget);

    // 3) Vincular → crea la cuenta con la licencia del dispositivo y navega '/'.
    await tester.ensureVisible(find.text('Vincular licencia a mi cuenta'));
    await tester.tap(find.text('Vincular licencia a mi cuenta'));
    await pumpUntilFound(tester, find.text('HOME_STUB_OK'));

    // 4) La cuenta quedó materializada con la licencia del dispositivo.
    final accounts = jsonDecode(prefs.getString('user_accounts')!) as List;
    expect(accounts, hasLength(1));
    final account = accounts.first as Map<String, dynamic>;
    expect(account['username'], 'nuevouser');
    expect(account['purchasedProductId'], kProductIdSemestral);
    expect(account['licenseExpiry'], isNotNull);
    final parsedExpiry = DateTime.parse(account['licenseExpiry'] as String);
    expect(
      parsedExpiry.difference(expiry).inSeconds.abs(),
      lessThan(5),
      reason: 'la licencia de la cuenta debe copiar la del dispositivo',
    );
  });
}
