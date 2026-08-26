import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/result.dart';
import 'package:d_0_pension/presentation/screens/login_screen.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/billing/play_purchase_success.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo E — RECUPERACIÓN DE ACCESO.
///
/// Tras la corrección de fondo del ciclo de recuperación:
///
/// 1) 'Recuperar acceso' existe SOLO en la pantalla de pago (punto único de
///    entrada). Se quitó del LOGIN: su fallo era un callejón sin salida
///    (SnackBar sin camino accionable) y además envenenaba el estado del
///    [PaymentProvider], haciendo que "crear cuenta" mostrara un error fantasma
///    en /payment (ciclo "Recuperar acceso → no hay cuenta → Error de conexión").
/// 2) Al montar /payment se limpia el estado transitorio
///    ([PaymentProvider.resetTransientState]) para que la selección de plan
///    SIEMPRE se muestre y nunca un error heredado.
/// 3) Desde la PANTALLA DE PAGO: 'Recuperar acceso' → restaura la compra
///    verificada → pantalla de éxito → 'Vincular a mi cuenta' → login.
class _FailingRestoreBillingService extends FakeBillingService {
  @override
  Future<Result<PlayPurchaseSuccess>> restoreSemestralLicense() async =>
      const Failure(kNoSubscriptionMessage);
}

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets(
    'Flujo E2: recuperar acceso desde la pantalla de pago → éxito → vincular',
    (tester) async {
      setGoldenSurface(tester);

      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      final prefs = await SharedPreferences.getInstance();

      // Entra directo a /payment (sin registro pendiente, invitado).
      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: FakeBillingService(),
          initialRoute: '/payment',
          home: const HomeStub(),
        ),
      );
      await pumpUntilFound(tester, find.text('Elige tu plan'));

      // 1) 'Recuperar acceso' (pantalla de pago) restaura la compra verificada.
      final recuperar = find.text('Recuperar acceso');
      await tester.ensureVisible(recuperar);
      await tester.tap(recuperar);
      await pumpUntilFound(tester, find.text('¡Licencia Activada!'));

      // 2) Éxito a nivel dispositivo (invitado, sin sesión).
      expect(find.text('Ir a la Calculadora'), findsOneWidget);
      expect(
        find.text(
          'Ya puedes acceder a todas las funcionalidades de la '
          'calculadora.',
        ),
        findsOneWidget,
      );
      expect(find.text('Vincular a mi cuenta'), findsOneWidget);

      // 3) 'Vincular a mi cuenta' → login para asociar la licencia a una sesión.
      await tester.tap(find.text('Vincular a mi cuenta'));
      await pumpUntilFound(tester, find.text('Iniciar sesión'));
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Flujo E3 (regresión): restore fallido → /payment muestra "Elige tu plan"',
    (tester) async {
      setGoldenSurface(tester);

      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      final prefs = await SharedPreferences.getInstance();

      // Arranca en el login con un billing cuyo restore SIEMPRE falla
      // (no hay suscripción activa), reproduciendo el escenario que antes
      // atrapaba al usuario en el ciclo.
      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: _FailingRestoreBillingService(),
          initialRoute: '/login',
          home: const HomeStub(),
        ),
      );
      await pumpUntilFound(tester, find.text('Iniciar sesión'));

      // 1) Simula el restore fallido del antiguo 'Recuperar acceso' del login:
      //    el provider queda en estado error (envenenado) con el mensaje
      //    de "no hay suscripción activa".
      final ctx = tester.element(find.byType(LoginScreen));
      final payments = ctx.read<PaymentProvider>();
      await payments.restorePurchase();
      await tester.pump();
      expect(payments.state, PaymentState.error);
      expect(payments.errorMessage, kNoSubscriptionMessage);

      // 2) El usuario sigue el flujo normal: crear cuenta → /payment.
      await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
      await pumpUntilFound(tester, find.text('Crear tu cuenta'));
      await tester.enterText(find.byType(TextFormField).at(0), 'nuevo_usuario');
      await tester.enterText(find.byType(TextFormField).at(1), 'clave1234');
      await tester.enterText(find.byType(TextFormField).at(2), 'clave1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));

      // 3) Corrección de raíz: al montar /payment se limpia el estado
      //    transitorio → se muestra la selección de plan, NO el error fantasma
      //    ('No hay suscripción activa' / 'Error de conexión').
      await pumpUntilFound(tester, find.text('Elige tu plan'));
      expect(payments.state, PaymentState.idle);
      expect(find.text('No hay suscripción activa'), findsNothing);
      expect(find.text(kNoSubscriptionMessage), findsNothing);
      expect(find.text('Error de conexión'), findsNothing);
    },
  );
}
