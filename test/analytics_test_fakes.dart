// Fakes compartidos para los tests de Firebase Analytics.
//
// No es un test (`*_test.dart`): es un helper reutilizado por
// `analytics_service_test.dart` y `analytics_payment_wiring_test.dart` para no
// duplicar el fake de plataforma ni la preparación de Firebase en cada archivo.
//
// Estrategia:
//   1. `setupFirebaseCoreMocks()` (mock oficial de Pigeon) permite llamar a
//      `Firebase.initializeApp()` en Dart puro.
//   2. `FakeAnalyticsPlatform` sustituye al canal nativo y captura las llamadas
//      a `logEvent`, a las que `logPurchase`/`logEvent` del paquete delegan
//      tras armar los parámetros.
//   3. Como `FirebaseAnalytics.instance` cachea su instancia por app, cada
//      archivo de test debe crear UN solo fake en `setUpAll` (vía
//      [initAnalyticsTestPlatform]) y reutilizarlo, limpiando su historial en
//      cada `setUp`.

import 'package:firebase_analytics_platform_interface/firebase_analytics_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';

/// Evento capturado por [FakeAnalyticsPlatform].
class CapturedEvent {
  CapturedEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object?>? parameters;
}

/// Fake de la plataforma de Firebase Analytics.
///
/// `FirebaseAnalyticsPlatform` no tiene métodos abstractos (todos lanzan
/// `UnimplementedError`), así que solo hay que anular `delegateFor` (para que
/// `instanceFor` devuelva este mismo fake) y `logEvent` (para capturar).
class FakeAnalyticsPlatform extends FirebaseAnalyticsPlatform {
  final List<CapturedEvent> loggedEvents = <CapturedEvent>[];

  @override
  FirebaseAnalyticsPlatform delegateFor({
    required FirebaseApp app,
    Map<String, dynamic>? webOptions,
  }) => this;

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object?>? parameters,
    AnalyticsCallOptions? callOptions,
  }) async {
    loggedEvents.add(CapturedEvent(name, parameters));
  }
}

/// Prepara el entorno de test: mock de Firebase Core + fake de plataforma.
///
/// Debe llamarse en `setUpAll` (UNA vez por archivo) porque
/// `FirebaseAnalytics.instance` cachea su instancia por app: si se creara un
/// fake nuevo por test, el delegate cacheado seguiría apuntando al primero.
/// En cada `setUp` hay que limpiar `fake.loggedEvents`.
Future<void> initAnalyticsTestPlatform(FakeAnalyticsPlatform fake) async {
  setupFirebaseCoreMocks();
  FirebaseAnalyticsPlatform.instance = fake;
  await Firebase.initializeApp();
}
