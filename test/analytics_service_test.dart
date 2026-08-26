// Test unitario de AnalyticsService sin Firebase nativo.
//
// Estrategia:
//   1. El fake de plataforma y la preparación de Firebase viven en
//      `analytics_test_fakes.dart` (compartidos con el test de cableado de
//      pago). `setupFirebaseCoreMocks()` permite `Firebase.initializeApp()` en
//      Dart puro y `FakeAnalyticsPlatform` captura los `logEvent`, a los que
//      `logPurchase`/`logEvent` del paquete delegan tras armar los parámetros.
//   2. Como `FirebaseAnalytics.instance` cachea su instancia por app, se
//      reutiliza UN solo fake a lo largo del archivo y se limpia su historial
//      en cada `setUp`.
//
// Run with: flutter test test/analytics_service_test.dart

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:d_0_pension/services/analytics/analytics_service.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/billing/play_purchase_success.dart';

import 'analytics_test_fakes.dart';

/// Producto semestral (el único que vende la app): $599 MXN / 6 meses.
ProductDetails _semestralProduct() => ProductDetails(
  id: kProductIdSemestral,
  title: 'Suscripción Semestral',
  description: '6 meses de acceso a la Calculadora Pensión Ley 73 IMSS',
  price: r'$599',
  rawPrice: 599.0,
  currencyCode: 'MXN',
);

/// Compra semestral verificada lista para reportar a Analytics.
PlayPurchaseSuccess _semestralSuccess({
  String? transactionId = 'GPA.1234-5678',
}) => PlayPurchaseSuccess(
  product: _semestralProduct(),
  verifiedProductId: kProductIdSemestral,
  purchaseToken: 'token-de-prueba-123',
  transactionId: transactionId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAnalyticsPlatform fakePlatform;
  late AnalyticsService service;

  setUpAll(() async {
    fakePlatform = FakeAnalyticsPlatform();
    await initAnalyticsTestPlatform(fakePlatform);
  });

  setUp(() {
    fakePlatform.loggedEvents.clear();
    service = AnalyticsService.forTesting(FirebaseAnalytics.instance);
  });

  group('AnalyticsService (Android, analytics activo)', () {
    test(
      'logOnboardingComplete registra el evento onboarding_complete',
      () async {
        await service.logOnboardingComplete();

        expect(fakePlatform.loggedEvents, hasLength(1));
        final event = fakePlatform.loggedEvents.single;
        expect(event.name, 'onboarding_complete');
        expect(event.parameters, isNull);
      },
    );

    test(
      'logVerifiedPlayPurchase registra purchase con value/currency/items',
      () async {
        await service.logVerifiedPlayPurchase(_semestralSuccess());

        final event = fakePlatform.loggedEvents.single;
        expect(event.name, 'purchase');

        final params = event.parameters!;
        expect(params['value'], 599.0);
        expect(params['currency'], 'MXN');
        expect(params['transaction_id'], 'GPA.1234-5678');

        final items = params['items'] as List<dynamic>;
        expect(items, hasLength(1));
        final item = items.single as Map<dynamic, dynamic>;
        expect(item['item_id'], kProductIdSemestral);
        expect(item['item_name'], 'Suscripción Semestral');
        expect(item['item_category'], 'Suscripción');
        expect(item['price'], 599.0);
        expect(item['quantity'], 1);
        expect(item['currency'], 'MXN');
      },
    );

    test('logVerifiedPlayPurchase no repite la misma transacción', () async {
      await service.logVerifiedPlayPurchase(_semestralSuccess());
      await service.logVerifiedPlayPurchase(_semestralSuccess());

      expect(fakePlatform.loggedEvents, hasLength(1));
    });

    test('logVerifiedPlayPurchase deduplica por purchaseToken si no hay '
        'transactionId', () async {
      await service.logVerifiedPlayPurchase(
        _semestralSuccess(transactionId: null),
      );
      await service.logVerifiedPlayPurchase(
        _semestralSuccess(transactionId: null),
      );

      expect(fakePlatform.loggedEvents, hasLength(1));
    });

    test('logVerifiedPlayPurchase registra transacciones distintas', () async {
      await service.logVerifiedPlayPurchase(
        _semestralSuccess(transactionId: 'T1'),
      );
      await service.logVerifiedPlayPurchase(
        _semestralSuccess(transactionId: 'T2'),
      );

      expect(fakePlatform.loggedEvents, hasLength(2));
    });
  });

  group('AnalyticsService (deshabilitado)', () {
    test('init() fuera de Android deja Analytics como no-op', () async {
      // El singleton global nunca se inicializa en el host de test (no es
      // Android), así que todos los métodos deben ser no-op sin lanzar.
      final instance = AnalyticsService.instance;
      await instance.init();
      await instance.logOnboardingComplete();
      await instance.logVerifiedPlayPurchase(_semestralSuccess());

      // Sin analytics activo no debe llegar nada al fake.
      expect(fakePlatform.loggedEvents, isEmpty);
    });
  });
}
