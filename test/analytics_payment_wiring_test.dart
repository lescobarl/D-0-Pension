// Test de cableado (wiring) entre PaymentProvider y AnalyticsService.
//
// Verifica que los hooks de analytics dentro del flujo real de pago disparan
// los eventos correctos, sin tocar Firebase nativo:
//   1. Se inyecta un AnalyticsService REAL (con fake de plataforma) en
//      PaymentProvider vía el parámetro opcional `analytics:`.
//   2. Se ejecuta el flujo real con FakeBillingService (compra, restauración,
//      onboarding) y se comprueba qué eventos llegan al fake de plataforma.
//   3. Un último caso comprueba que, SIN inyectar analytics (singleton global
//      deshabilitado en el host de test), la compra se completa sin romperse:
//      el seam por defecto mantiene verdes los tests previos.
//
// Los `unawaited(...)` del provider se descargan con `pumpEventQueue()` antes
// de inspeccionar el historial del fake.
//
// Run with: flutter test test/analytics_payment_wiring_test.dart

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/result.dart';
import 'package:d_0_pension/services/analytics/analytics_service.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

import 'analytics_test_fakes.dart';
import 'entry_flow_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAnalyticsPlatform fakePlatform;
  late AnalyticsService service;
  late SharedPreferences prefs;

  setUpAll(() async {
    fakePlatform = FakeAnalyticsPlatform();
    await initAnalyticsTestPlatform(fakePlatform);
  });

  setUp(() async {
    fakePlatform.loggedEvents.clear();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = AnalyticsService.forTesting(FirebaseAnalytics.instance);
  });

  group('PaymentProvider -> Analytics (cableado real)', () {
    test('purchaseSemestral registra un evento purchase', () async {
      final provider = PaymentProvider(
        FakeBillingService(),
        prefs,
        analytics: service,
      );
      await provider.initialize();
      await provider.purchaseSemestral();
      await pumpEventQueue();

      final event = fakePlatform.loggedEvents.single;
      expect(event.name, 'purchase');

      final params = event.parameters!;
      expect(params['value'], 599.0);
      expect(params['currency'], 'MXN');
      expect(params['transaction_id'], 'GPA.1234-5678');

      final items = params['items'] as List<dynamic>;
      final item = items.single as Map<dynamic, dynamic>;
      expect(item['item_id'], kProductIdSemestral);
      expect(item['item_name'], 'Suscripción Semestral');
      expect(item['item_category'], 'Suscripción');
      expect(item['price'], 599.0);
      expect(item['quantity'], 1);
      expect(item['currency'], 'MXN');
    });

    test('restorePurchase (renovación) NO registra purchase', () async {
      final provider = PaymentProvider(
        FakeBillingService(),
        prefs,
        analytics: service,
      );
      await provider.initialize();
      await provider.restorePurchase();
      await pumpEventQueue();

      // La restauración no es una conversión nueva: evita doble conteo.
      expect(fakePlatform.loggedEvents, isEmpty);
    });

    test('completeOnboarding registra onboarding_complete', () async {
      final provider = PaymentProvider(
        FakeBillingService(),
        prefs,
        analytics: service,
      );
      await provider.completeOnboarding();
      await pumpEventQueue();

      final event = fakePlatform.loggedEvents.single;
      expect(event.name, 'onboarding_complete');
      expect(event.parameters, isNull);
    });
  });

  group('PaymentProvider sin analytics (seam por defecto)', () {
    test(
      'la compra se completa sin inyectar analytics (singleton no-op)',
      () async {
        // Sin el parámetro `analytics:`, PaymentProvider usa el singleton
        // global, que en el host de test (no Android) nunca se inicializa: todos
        // los métodos son no-op. La compra debe completarse igual y no debe
        // registrarse nada en el fake.
        final provider = PaymentProvider(FakeBillingService(), prefs);
        await provider.initialize();
        final result = await provider.purchaseSemestral();
        await pumpEventQueue();

        expect(result.isSuccess, isTrue);
        expect(provider.hasValidLicense, isTrue);
        expect(fakePlatform.loggedEvents, isEmpty);
      },
    );
  });
}
