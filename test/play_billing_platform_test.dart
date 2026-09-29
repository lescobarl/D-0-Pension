import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// El paquete principal se importa CON prefijo: re-exporta los tipos de la
// plataforma (PurchaseDetails, ProductDetails...) y su singleton
// `InAppPurchase.instance` debe materializarse ANTES de instalar el fake.
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
// La interfaz de plataforma se importa SIN prefijo: sus tipos son idénticos a
// los re-exportados por el paquete principal, y expone `InAppPurchasePlatform`
// (la clase base real que el fake debe extender).
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/presentation/screens/login_screen.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

// ---------------------------------------------------------------------------
// Fix 2 — InAppPurchasePlatform real en widget tests.
//
// A diferencia de [FakeBillingService] (que sobreescribe los métodos del
// servicio), este fake se inyecta en la CAPA MÁS BAJA de in_app_purchase
// (`InAppPurchasePlatform.instance`). De este modo el `PlayBillingService` REAL
// ejecuta su lógica completa: inicialización, suscripción al purchase stream,
// sesiones de compra/restauración, timeouts y verificación Play Store.
//
// ⚠️ ORDEN CRÍTICO: `InAppPurchaseAndroidPlatform.registerPlatform()` ejecuta
//    `InAppPurchasePlatform.instance = InAppPurchaseAndroidPlatform()` de forma
//    INCONDICIONAL en el primer acceso a `InAppPurchase.instance` (y `flutter
//    test` fija `defaultTargetPlatform == android`). Por eso hay que:
//      1. Materializar el singleton primero (`iap.InAppPurchase.instance;`) para
//         que `registerPlatform()` se ejecute una sola vez y `_instance` quede
//         cacheado.
//      2. REEMPLAZAR después la instancia de plataforma por el fake.
//    A partir de ahí `InAppPurchase.instance` devuelve el singleton cacheado y
//    delega CADA llamada viva a `InAppPurchasePlatform.instance` (el fake).
// ---------------------------------------------------------------------------

/// Sustituto determinista de [InAppPurchasePlatform] (capa inferior de
/// in_app_purchase). Emula Google Play: siempre disponible, consulta de
/// productos determinista y emisión controlada del purchase stream.
class FakeInAppPurchasePlatform extends InAppPurchasePlatform {
  final _purchaseController =
      StreamController<List<PurchaseDetails>>.broadcast();

  /// Catálogo servido por [queryProductDetails].
  final List<ProductDetails> products;

  /// Resultados que devolverá la siguiente [restorePurchases]. Arranca vacío
  /// para que el active-check de inicio no otorgue licencia.
  List<PurchaseDetails> restoreResults = [];

  /// IDs de productos completados vía [completePurchase].
  final completedProductIds = <String>[];

  /// Parámetros de compra registrados por buyNonConsumable/buyConsumable.
  final buyRequests = <PurchaseParam>[];

  /// Nº de veces que se invocó [restorePurchases].
  int restoreCalls = 0;

  FakeInAppPurchasePlatform({List<ProductDetails>? products})
    : products =
          products ??
          [fakeSemestralProduct(), fakeAnnualProduct(), fakePerpetualProduct()];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseController.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    final found = products.where((p) => identifiers.contains(p.id)).toList();
    final foundIds = found.map((p) => p.id).toSet();
    return ProductDetailsResponse(
      productDetails: found,
      notFoundIDs: identifiers.difference(foundIds).toList(),
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyRequests.add(purchaseParam);
    return true;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    buyRequests.add(purchaseParam);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completedProductIds.add(purchase.productID);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
    _purchaseController.add(List.of(restoreResults));
  }

  @override
  Future<String> countryCode() async => 'MX';

  /// Emite compras por el purchase stream (equivalente a restorePurchases).
  void emit(List<PurchaseDetails> purchases) {
    _purchaseController.add(List.of(purchases));
  }
}

/// Compra determinista verificable por [PlayPurchaseVerifier].
///
/// Reglas del constructor de [PurchaseDetails] (platform-interface 1.4.1):
///   - `transactionDate` es `String?` con milisegundos desde epoch (NO DateTime).
///   - `status`, `error` y `pendingCompletePurchase` son campos MUTABLES que se
///     fijan DESPUÉS de la construcción.
PurchaseDetails fakePurchase({
  required String productId,
  PurchaseStatus status = PurchaseStatus.purchased,
  bool pendingCompletePurchase = true,
  String? errorMessage,
}) {
  final token = 'token-$productId-123';
  return PurchaseDetails(
      purchaseID: 'GPA.fake-$productId',
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: token,
        serverVerificationData: token,
        source: 'google_play',
      ),
      transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
      status: status,
    )
    ..pendingCompletePurchase = pendingCompletePurchase
    ..error = errorMessage == null
        ? null
        : IAPError(
            source: 'GooglePlay',
            code: 'ITEM_ALREADY_OWNED',
            message: errorMessage,
          );
}

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets(
    'Fix 2: recuperar acceso con InAppPurchasePlatform real → éxito → vincular',
    (tester) async {
      setGoldenSurface(tester);

      // 1) Materializar el singleton PRIMERO: dispara registerPlatform() una
      //    sola vez y cachea `_instance` (si se hiciera al revés, el platform
      //    Android real sobrescribiría el fake).
      final _ = iap.InAppPurchase.instance;

      // 2) Instalar el fake de plataforma.
      final fake = FakeInAppPurchasePlatform();
      InAppPurchasePlatform.instance = fake;

      // Dispositivo limpio (sin licencia ni cuenta), onboarding completado.
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: PlayBillingService(),
          initialRoute: '/payment',
          // La ruta '/' (base del stack del Navigator) sigue viva bajo /payment;
          // tras restaurar la licencia, el entry point resuelve a 'home'. Usamos
          // el stub para no necesitar el shell real (ni su RetroactiveProvider).
          home: const HomeStub(),
        ),
      );
      await pumpUntilFound(tester, find.text('Elige tu plan'));

      // El active-check de arranque NO otorgó licencia (restoreResults = [] al
      // inicio), pero sí ejecutó restorePurchases() al menos una vez.
      expect(prefs.getString('license_product_id'), isNull);
      expect(fake.restoreCalls, greaterThanOrEqualTo(1));

      // A partir de aquí la restauración devuelve la compra semestral verificada.
      fake.restoreResults = [fakePurchase(productId: kProductIdSemestral)];

      // 3) 'Recuperar acceso' (pantalla de pago) → restauración REAL vía el
      //    purchase stream del fake → licencia verificada → pantalla de éxito.
      final recuperar = find.text('Recuperar acceso');
      await tester.ensureVisible(recuperar);
      await tester.tap(recuperar);
      await pumpUntilFound(tester, find.text('¡Licencia Activada!'));

      // 4) Éxito a nivel dispositivo (invitado, sin sesión).
      expect(find.text('Ir a la Calculadora'), findsOneWidget);
      expect(
        find.text(
          'Ya puedes acceder a todas las funcionalidades de la '
          'calculadora.',
        ),
        findsOneWidget,
      );
      expect(find.text('Vincular a mi cuenta'), findsOneWidget);

      // 5) La licencia semestral (180 días) quedó guardada y la compra pendiente
      //    se completó en la tienda (la verificación pasó).
      expect(prefs.getString('license_product_id'), kProductIdSemestral);
      expect(prefs.getString('license_expiry'), isNotNull);
      final restoredExpiry = DateTime.parse(prefs.getString('license_expiry')!);
      final restoredDays = restoredExpiry.difference(DateTime.now()).inDays;
      expect(
        restoredDays,
        inInclusiveRange(179, 180),
        reason: 'la suscripción semestral restaurada dura 180 días (6 meses)',
      );
      expect(fake.completedProductIds, contains(kProductIdSemestral));

      // 6) 'Vincular a mi cuenta' → login para asociar la licencia a una sesión.
      await tester.tap(find.text('Vincular a mi cuenta'));
      await pumpUntilFound(tester, find.text('Iniciar sesión'));
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Fix 2 error: restaurar sin suscripción → "No hay suscripción activa"',
    (tester) async {
      setGoldenSurface(tester);

      // Materializar primero (ver arriba) y luego instalar el fake.
      final _ = iap.InAppPurchase.instance;
      final fake = FakeInAppPurchasePlatform();
      InAppPurchasePlatform.instance = fake;

      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: PlayBillingService(),
          initialRoute: '/payment',
          home: const HomeStub(),
        ),
      );
      await pumpUntilFound(tester, find.text('Elige tu plan'));

      // restoreResults sigue en [] → la restauración no encuentra suscripción:
      // la sesión se cierra con kNoSubscriptionMessage → _buildErrorScreen
      // detecta isNoActiveSubscriptionError → _buildNoActiveSubscriptionView.
      final recuperar = find.text('Recuperar acceso');
      await tester.ensureVisible(recuperar);
      await tester.tap(recuperar);

      await pumpUntilFound(tester, find.text('No hay suscripción activa'));
      expect(find.byIcon(Icons.subscriptions_outlined), findsOneWidget);
      expect(find.text('Comprar Suscripción Semestral'), findsOneWidget);

      // Ninguna licencia quedó guardada.
      expect(prefs.getString('license_product_id'), isNull);
    },
  );

  testWidgets(
    'Fix 2: compra con tienda silenciosa → restore automático (25s) → éxito',
    (tester) async {
      setGoldenSurface(tester);

      // Materializar el singleton primero y luego instalar el fake de plataforma.
      final _ = iap.InAppPurchase.instance;
      final fake = FakeInAppPurchasePlatform();
      InAppPurchasePlatform.instance = fake;

      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: PlayBillingService(),
          initialRoute: '/payment',
          home: const HomeStub(),
        ),
      );
      await pumpUntilFound(tester, find.text('Elige tu plan'));

      // El active-check de arranque no otorgó licencia (restoreResults = []).
      expect(prefs.getString('license_product_id'), isNull);

      // Escenario real: el usuario YA tiene la suscripción en la cuenta. Google
      // Play muestra su diálogo nativo "ya te suscribiste" y NO emite ningún
      // evento de compra (tienda silenciosa). La suscripción solo se revela vía
      // restore. Este es el caso donde el cobro SÍ procede pero la app solía
      // mostrar el error de conexión engañoso.
      fake.restoreResults = [fakePurchase(productId: kProductIdSemestral)];

      // Iniciar la compra: buyNonConsumable retorna true pero NO llega ningún
      // evento de compra → entra el watch de silencio (25s).
      final comprar = find.text('Comprar Suscripción Semestral');
      await tester.ensureVisible(comprar);
      await tester.tap(comprar);
      await tester.pump();

      // Tras 25s de silencio el watch hace restore automático (una sola vez) y
      // la suscripción ya existente se recupera → ÉXITO en lugar de error.
      await tester.pump(const Duration(seconds: 26));
      await pumpUntilFound(tester, find.text('¡Licencia Activada!'));

      // Éxito real: licencia semestral guardada, compra completada en la tienda
      // y el error engañoso "no completó la compra" NUNCA se mostró.
      expect(prefs.getString('license_product_id'), kProductIdSemestral);
      expect(prefs.getString('license_expiry'), isNotNull);
      expect(fake.completedProductIds, contains(kProductIdSemestral));
      expect(find.text('Ir a la Calculadora'), findsOneWidget);
      expect(find.text('Vincular a mi cuenta'), findsOneWidget);
      expect(
        find.textContaining('no completó la compra'),
        findsNothing,
        reason:
            'el silencio de la tienda no debe mostrar error si el cobro sí '
            'procede (la licencia ya existe y se recupera vía restore)',
      );
    },
  );
}
