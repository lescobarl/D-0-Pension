import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/presentation/screens/license_screen.dart';
import 'package:d_0_pension/presentation/screens/payment_screen.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo C — Licencia EXPIRADA: el usuario entra a [LicenseScreen], ve el
/// estado de expirada, renueva → /payment (golden 07_licencia_expirada).
///
/// Funcional:
///   1. Con licencia vencida, la pantalla de licencia muestra 'Licencia
///      Expirada' + 'Detalles de la Licencia' + botón 'Renovar Licencia'.
///   2. No se ofrece 'Ir a la Calculadora' (no hay licencia válida).
///   3. 'Renovar Licencia' navega a /payment para renovar el plan.
/// Visual: golden 9:16 → test/store_screenshots/07_licencia_expirada.png.
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Flujo C: licencia expirada → renovar → pago (golden 07)', (
    tester,
  ) async {
    // Superficie determinista 9:16: física 1080×1920, dpr 3.0 → 360×640 lógicos.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.reset);

    // Reloj congelado: el golden renderiza la fecha de vigencia ('Vigencia:
    // dd/mm/aaaa'), así que el test debe ser determinista sin importar el día
    // en que se ejecute. LicenseService usa `clock.now()`, por lo que
    // `withClock` fija también la evaluación de expiración.
    final frozenNow = DateTime(2026, 8, 8);
    final expiredAt = frozenNow.subtract(const Duration(days: 10));

    await withClock(Clock.fixed(frozenNow), () async {
      // Licencia semestral vencida hace 10 días (fecha fija, no relativa a
      // hoy, para que el texto 'Vigencia' del golden no cambie entre días).
      SharedPreferences.setMockInitialValues({
        'onboarding_completed': true,
        'license_expiry': expiredAt.toIso8601String(),
        'license_product_id': kProductIdSemestral,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        buildFlowApp(prefs: prefs, billing: FakeBillingService()),
      );
      await pumpUntilFound(tester, find.text('Mi Licencia'));

      // 1) Pantalla de licencia con estado expirado.
      expect(find.text('Mi Licencia'), findsOneWidget);
      expect(find.text('Licencia Expirada'), findsOneWidget);
      expect(find.text('Detalles de la Licencia'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Renovar Licencia'),
        findsOneWidget,
      );

      // 2) Sin licencia válida → sin acceso a la calculadora.
      expect(find.text('Ir a la Calculadora'), findsNothing);
      expect(find.text('Licencia Activa'), findsNothing);

      // 3) Golden 9:16.
      await expectLater(
        find.byType(LicenseScreen),
        matchesGoldenFile('store_screenshots/07_licencia_expirada.png'),
      );

      // 4) Renovar → /payment.
      final renovar = find.widgetWithText(ElevatedButton, 'Renovar Licencia');
      await tester.ensureVisible(renovar);
      await tester.tap(renovar);
      await pumpUntilFound(tester, find.text('Elige tu plan'));
      expect(find.byType(PaymentScreen), findsOneWidget);
    });
  });
}
