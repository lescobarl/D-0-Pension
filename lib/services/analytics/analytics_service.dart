import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../billing/play_purchase_success.dart';

/// Nombre del evento GA4 que registra la finalización del onboarding.
const String _kOnboardingCompleteEvent = 'onboarding_complete';

/// Categoría GA4 asignada a los ítems de licencia vendidos en la app.
const String _kItemCategory = 'Suscripción';

/// Servicio singleton de Firebase Analytics.
///
/// Solo se activa en Android, la única plataforma con `google-services.json`
/// declarado. En cualquier otra plataforma —o si la inicialización de Firebase
/// falla— todos los métodos son no-op, de modo que Analytics nunca interfiere
/// con el arranque ni con la experiencia del usuario.
class AnalyticsService {
  /// Instancia global utilizada por toda la aplicación.
  static final AnalyticsService instance = AnalyticsService._();

  /// Crea el servicio con una instancia de [FirebaseAnalytics] ya lista.
  ///
  /// Solo para pruebas: permite ejercitar el logging inyectando un fake de
  /// plataforma sin inicializar Firebase nativo. En producción se usa
  /// [instance], que se prepara en [init].
  @visibleForTesting
  AnalyticsService.forTesting(FirebaseAnalytics analytics)
    : _analytics = analytics,
      _isReady = true;

  AnalyticsService._();

  FirebaseAnalytics? _analytics;
  bool _isReady = false;
  bool _initAttempted = false;

  /// Claves de compras ya reportadas (`transactionId ?? purchaseToken`).
  ///
  /// Evita registrar dos veces la misma transacción dentro de la sesión (por
  /// ejemplo si el flujo de pago se re-ejecuta), preservando el conteo real de
  /// conversiones.
  final Set<String> _reportedTransactionKeys = <String>{};

  /// Inicializa Firebase Analytics de forma no bloqueante.
  ///
  /// Es idempotente y solo actúa en Android. Un fallo de Firebase nunca debe
  /// impedir el arranque de la app.
  Future<void> init() async {
    if (_initAttempted) return;
    _initAttempted = true;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _analytics = FirebaseAnalytics.instance;
      _isReady = true;
    } on Exception {
      // Analytics es opcional: se degrada a no-op sin propagar el error.
      _isReady = false;
    }
  }

  bool get _enabled => _isReady && _analytics != null;

  /// Registra la finalización del onboarding.
  Future<void> logOnboardingComplete() {
    if (!_enabled) return Future.value();
    return _analytics!.logEvent(name: _kOnboardingCompleteEvent);
  }

  /// Registra una compra verificada de licencia como evento GA4 de e-commerce.
  ///
  /// Solo debe llamarse para compras NUEVAS (no para restauraciones,
  /// renovaciones automáticas ni el refresco al arrancar), para no inflar el
  /// conteo de conversiones. El valor y la moneda provienen del
  /// [ProductDetails] real de la tienda, nunca de valores fijos.
  Future<void> logVerifiedPlayPurchase(PlayPurchaseSuccess success) {
    if (!_enabled) return Future.value();

    final String? dedupKey = success.transactionId ?? success.purchaseToken;
    if (dedupKey != null && !_reportedTransactionKeys.add(dedupKey)) {
      return Future.value();
    }

    // Invariante de logPurchase: value y currency deben ir juntos. En
    // in_app_purchase ambos campos son no-nulos (`rawPrice`, `currencyCode`),
    // por lo que siempre viajan juntos y no hay valores fijos.
    final double price = success.product.rawPrice;
    final String currency = success.product.currencyCode;

    return _analytics!.logPurchase(
      value: price,
      currency: currency,
      transactionId: success.transactionId,
      items: <AnalyticsEventItem>[
        AnalyticsEventItem(
          itemId: success.verifiedProductId,
          itemName: success.product.title,
          itemCategory: _kItemCategory,
          price: price,
          quantity: 1,
          currency: currency,
        ),
      ],
    );
  }
}
