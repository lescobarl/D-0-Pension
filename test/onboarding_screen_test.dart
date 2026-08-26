import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/presentation/screens/onboarding_screen.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

/// Verifica el flujo de onboarding "Opción A":
///   - El botón "Saltar" es visible desde el inicio (nunca oculto).
///   - No existe botón "Comenzar" (el onboarding continúa solo).
///   - Auto-avance a `/login` aunque el video falle o nunca termine.
///
/// En el entorno de pruebas el plugin de video no tiene implementación
/// (`MissingPluginException`), por lo que `_initVideo` falla rápido y se avanza
/// a `/login`; si por cualquier motivo no fallara, el temporizador de respaldo
/// de 30 s fuerza el mismo avance. El guard `_navigated` evita navegar dos
/// veces.
void main() {
  Future<PaymentProvider> makeProvider(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    return PaymentProvider(PlayBillingService(), prefs);
  }

  Widget buildApp(PaymentProvider payments) {
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: payments)],
      child: MaterialApp(
        routes: {'/login': (_) => const Scaffold(body: Text('LOGIN_MARKER'))},
        home: const OnboardingScreen(),
      ),
    );
  }

  testWidgets('Opción A: Saltar es visible desde el inicio', (tester) async {
    final payments = await makeProvider({'onboarding_completed': false});
    await tester.pumpWidget(buildApp(payments));

    // Primer fotograma: el botón Saltar ya está presente (la navegación, si
    // ocurre, es asíncrona y no puede ejecutarse durante el build).
    expect(find.text('Saltar'), findsOneWidget);
  });

  testWidgets('Opción A: no existe botón Comenzar', (tester) async {
    final payments = await makeProvider({'onboarding_completed': false});
    await tester.pumpWidget(buildApp(payments));

    expect(find.text('Comenzar'), findsNothing);
  });

  testWidgets('Opción A: auto-avanza a /login (fallback 30 s)', (tester) async {
    final payments = await makeProvider({'onboarding_completed': false});
    await tester.pumpWidget(buildApp(payments));

    // Avanza el reloj más allá del temporizador de respaldo (30 s) para forzar
    // la navegación aunque el video no haya terminado ni fallado.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_MARKER'), findsOneWidget);
    expect(payments.isOnboardingCompleted, isTrue);
  });
}
