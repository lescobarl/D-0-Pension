import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/presentation/screens/payment_screen.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo A — Usuario NUEVO: registro → /payment con [PendingRegistration].
///
/// Funcional:
///   1. El toggle '¿No tienes cuenta? Regístrate' activa el modo registro.
///   2. Enviar credenciales válidas navega a /payment.
///   3. La pantalla de pago muestra el plan semestral ($599/6 meses) sin
///      botón de vincular (aún no hay licencia en el dispositivo).
///   4. El [PendingRegistration] viaja en los argumentos de la ruta.
/// Visual: golden 9:16 (física 1080×1920, dpr 3.0) →
/// `test/store_screenshots/06_pago.png` (subida a 1080×1920 reales por
/// scripts/upscale_screenshots.ps1 → capturas_tienda/06_captura.png).
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('Flujo A: registro → pantalla de pago (golden 06_pago)', (
    tester,
  ) async {
    // Superficie determinista 9:16: física 1080×1920, dpr 3.0 → 360×640 lógicos.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      buildFlowApp(prefs: prefs, billing: FakeBillingService()),
    );
    await pumpUntilFound(tester, find.text('¿No tienes cuenta? Regístrate'));

    // 1) Activar modo registro.
    final toggle = find.text('¿No tienes cuenta? Regístrate');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();

    // 2) Llenar el formulario (0=Usuario, 1=Contraseña, 2=Confirmar).
    await tester.enterText(find.byType(TextFormField).at(0), 'nuevouser');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    await tester.enterText(find.byType(TextFormField).at(2), '1234');

    // 3) Enviar registro → navega a /payment.
    final crear = find.widgetWithText(ElevatedButton, 'Crear cuenta');
    await tester.ensureVisible(crear);
    await tester.tap(crear);
    await pumpUntilFound(tester, find.text('Elige tu plan'));

    // 4) Pantalla de pago: encabezado, plan semestral y acciones.
    expect(find.text('Obtén tu Licencia'), findsOneWidget);
    expect(find.text('Elige tu plan'), findsOneWidget);
    expect(find.text('Suscripción Semestral'), findsOneWidget);
    expect(find.text(r'$599'), findsWidgets);
    expect(find.text('/6 meses'), findsOneWidget);
    expect(find.text('Comprar Suscripción Semestral'), findsOneWidget);
    expect(find.text('Recuperar acceso'), findsOneWidget);
    expect(find.text('Pago seguro procesado por Google Play'), findsOneWidget);

    // 5) Sin licencia previa → no hay botón de vincular licencia.
    expect(find.text('Vincular licencia a mi cuenta'), findsNothing);

    // 6) El registro pendiente viaja en los argumentos de la ruta.
    final pending = tester
        .widget<PaymentScreen>(find.byType(PaymentScreen))
        .pendingRegistration;
    expect(pending, isNotNull);
    expect(pending!.username, 'nuevouser');
    expect(pending.verifyPassword('1234'), isTrue);

    // 7) Golden 9:16.
    await expectLater(
      find.byType(PaymentScreen),
      matchesGoldenFile('store_screenshots/06_pago.png'),
    );
  });
}
