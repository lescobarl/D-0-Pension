import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/app_metadata.dart';
import 'package:d_0_pension/core/models/result.dart';
import 'package:d_0_pension/core/theme/app_theme.dart';
import 'package:d_0_pension/core/utils/password_hasher.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/presentation/screens/license_screen.dart';
import 'package:d_0_pension/presentation/screens/login_screen.dart';
import 'package:d_0_pension/presentation/screens/onboarding_screen.dart';
import 'package:d_0_pension/presentation/screens/payment_screen.dart';
import 'package:d_0_pension/services/account/app_startup.dart';
import 'package:d_0_pension/services/account/pending_registration.dart';
import 'package:d_0_pension/services/account/registration_checkout.dart';
import 'package:d_0_pension/services/account/user_account_service.dart';
import 'package:d_0_pension/services/account/validation_privileges_service.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/billing/play_purchase_success.dart';

// ---------------------------------------------------------------------------
// Harness compartido de los tests de flujo de entrada (flujos A–F).
//
// Proporciona:
//   1. Productos falsos deterministas ([ProductDetails]) + [PlayPurchaseSuccess].
//   2. [FakeBillingService]: sustituye a Google Play por una tienda siempre
//      disponible con compras/restauraciones VERIFICADAS al instante. Es un
//      seam legítimo de test (regla 0.2: nada de objetos dummy en producción)
//      inyectado por constructor en [PaymentProvider].
//   3. [HomeStub]: destino '/' de reemplazo para aserciones de navegación.
//   4. [seedUserJson]: siembra cuentas ya existentes en 'user_accounts'.
//   5. [buildFlowApp]: árbol completo de providers + rutas del flujo de entrada.
// ---------------------------------------------------------------------------

/// Producto semestral ($599 / 6 meses), el único que vende la app.
ProductDetails fakeSemestralProduct() => ProductDetails(
  id: kProductIdSemestral,
  title: 'Suscripción Semestral',
  description:
      '6 meses de acceso completo a la Calculadora Pensión Ley 73 IMSS',
  price: r'$599',
  rawPrice: 599.0,
  currencyCode: 'MXN',
);

/// Producto anual (solo del fake; la app vende únicamente semestral).
ProductDetails fakeAnnualProduct() => ProductDetails(
  id: kProductIdAnnual,
  title: 'Suscripción Anual',
  description:
      '12 meses de acceso completo a la Calculadora Pensión Ley 73 IMSS',
  price: r'$1,199',
  rawPrice: 1199.0,
  currencyCode: 'MXN',
);

/// Producto vitalicio (perpetuo).
ProductDetails fakePerpetualProduct() => ProductDetails(
  id: kProductIdPerpetual,
  title: 'Licencia Vitalicia',
  description: 'Acceso de por vida a la Calculadora Pensión Ley 73 IMSS',
  price: r'$2,499',
  rawPrice: 2499.0,
  currencyCode: 'MXN',
);

/// Compra semestral verificada (flujo A pago / flujo C renovación).
PlayPurchaseSuccess fakeSemestralSuccess() => PlayPurchaseSuccess(
  product: fakeSemestralProduct(),
  verifiedProductId: kProductIdSemestral,
  purchaseToken: 'token-de-prueba-123',
  transactionId: 'GPA.1234-5678',
);

/// Compra anual verificada (solo usada por el override `purchaseAnnualLicense`
/// del fake; la app no vende el plan anual).
PlayPurchaseSuccess fakeAnnualSuccess() => PlayPurchaseSuccess(
  product: fakeAnnualProduct(),
  verifiedProductId: kProductIdAnnual,
  purchaseToken: 'token-de-prueba-anual-456',
  transactionId: 'GPA.9876-5432',
);

/// Compra vitalicia verificada.
PlayPurchaseSuccess fakePerpetualSuccess() => PlayPurchaseSuccess(
  product: fakePerpetualProduct(),
  verifiedProductId: kProductIdPerpetual,
  purchaseToken: 'token-de-prueba-vitalicia-789',
  transactionId: 'GPA.1111-2222',
);

/// Sustituto determinista de [PlayBillingService] para widget tests.
///
/// Simula una tienda siempre disponible y compras/restauraciones verificadas
/// al instante. Permite recorrer TODO el flujo post-compra (pantalla de éxito,
/// checkout diferido, 'Vincular a mi cuenta') sin tocar Google Play.
class FakeBillingService extends PlayBillingService {
  @override
  Future<Result<bool>> initialize() async => const Success(true);

  @override
  Future<Result<PlayPurchaseSuccess>> purchaseSemestralLicense() async =>
      Success(fakeSemestralSuccess());

  @override
  Future<Result<PlayPurchaseSuccess>> purchaseAnnualLicense() async =>
      Success(fakeAnnualSuccess());

  @override
  Future<Result<PlayPurchaseSuccess>> purchasePerpetualLicense() async =>
      Success(fakePerpetualSuccess());

  @override
  Future<Result<PlayPurchaseSuccess>> restoreSemestralLicense() async =>
      Success(fakeSemestralSuccess());

  @override
  Future<Result<PlayPurchaseSuccess?>> checkActiveSubscription({
    required String productId,
  }) async => const Success(null);

  @override
  void dispose() {
    // No hay sesión ni suscripción real que cancelar en el test.
  }
}

/// Destino raíz ('/') de reemplazo para aserciones de navegación sin cargar
/// todo el shell de la calculadora.
class HomeStub extends StatelessWidget {
  const HomeStub({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('HOME_STUB_OK')));
  }
}

/// Construye el JSON de un [UserProfile] ya existente listo para sembrar en
/// `user_accounts`. Genera salt/hash con el [PasswordHasher] real para que
/// `verifyPassword` funcione en los tests.
Map<String, dynamic> seedUserJson({
  required String username,
  required String password,
  String? email,
  DateTime? licenseExpiry,
  String? purchasedProductId,
  DateTime? createdAt,
}) {
  final salt = PasswordHasher.generateSalt();
  return {
    'id': 'usr-${username.hashCode.abs()}',
    'username': username,
    'salt': salt,
    'passwordHash': PasswordHasher.hash(password, salt),
    'email': email,
    'licenseExpiry': licenseExpiry?.toIso8601String(),
    'purchasedProductId': purchasedProductId,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
  };
}

/// Construye el árbol completo de providers + rutas del flujo de entrada.
///
/// - Providers: [PaymentProvider] (con [billing] y opcional [builtinAccount],
///   inicializado como la app real), [UserAccountService],
///   [ValidationPrivilegesService] (con el [builtinAccount]) y
///   [RegistrationCheckout].
/// - Rutas: `'/'` → [_FlowEntryPoint] (resuelve el destino con [AppStartup],
///   igual que la app real; el destino 'home' es [home], por defecto el shell
///   real de la calculadora); `'/login'` → [LoginScreen]; `'/payment'` →
///   [PaymentScreen] (recibe un [PendingRegistration] por argumentos);
///   `'/license'` → [LicenseScreen].
///
/// [extraProviders] permite añadir providers extra (p. ej. el
/// [RetroactiveProvider] necesario para renderizar [HomeTabsScreen] en los
/// flujos B/F).
///
/// [initialRoute] (por defecto `'/'`) define dónde arranca la app. Los flujos
/// B/F que prueban "login → home" usan `initialRoute: '/login'` para llegar
/// directo a la pantalla de login y, tras autenticarse, `'/'` resuelve al
/// shell real de la calculadora ([HomeTabsScreen]).
Widget buildFlowApp({
  required SharedPreferences prefs,
  required PlayBillingService billing,
  BuiltinAccountConfig? builtinAccount,
  List<SingleChildWidget> extraProviders = const [],
  Widget? home,
  String initialRoute = '/',
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PaymentProvider>(
        create: (_) =>
            PaymentProvider(billing, prefs, builtinAccount: builtinAccount)
              ..initialize(),
      ),
      ChangeNotifierProvider<UserAccountService>(
        create: (context) => UserAccountService(
          prefs,
          payments: context.read<PaymentProvider>(),
        ),
      ),
      Provider<ValidationPrivilegesService>(
        create: (_) => ValidationPrivilegesService(builtinAccount),
      ),
      Provider<RegistrationCheckout>(
        create: (context) => RegistrationCheckout(
          accounts: context.read<UserAccountService>(),
          payments: context.read<PaymentProvider>(),
        ),
      ),
      ...extraProviders,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromConfig(null),
      initialRoute: initialRoute,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute<void>(
              builder: (_) => _FlowEntryPoint(home: home),
            );
          case '/login':
            return MaterialPageRoute<void>(builder: (_) => const LoginScreen());
          case '/payment':
            return MaterialPageRoute<void>(
              builder: (_) => PaymentScreen(
                pendingRegistration: settings.arguments as PendingRegistration?,
              ),
            );
          case '/license':
            return MaterialPageRoute<void>(
              builder: (_) => const LicenseScreen(),
            );
          default:
            return MaterialPageRoute<void>(
              builder: (_) => _FlowEntryPoint(home: home),
            );
        }
      },
    ),
  );
}

/// Entry point de los flujos: replica la resolución ÚNICA de destinos de la
/// app real ([main.dart] `_AppEntryPoint`) usando [AppStartup].
///
/// El destino 'home' es intercambiable ([home]) para que cada flujo pueda
/// sustituir el shell de la calculadora por un [HomeStub] y asertar la
/// navegación sin cargar toda la app.
class _FlowEntryPoint extends StatelessWidget {
  const _FlowEntryPoint({this.home});

  /// Destino 'home' de reemplazo (p. ej. [HomeStub] o [HomeTabsScreen]).
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final payments = context.watch<PaymentProvider>();
    final accounts = context.watch<UserAccountService>();

    switch (AppStartup.resolveStartupDestination(
      payments: payments,
      accounts: accounts,
    )) {
      case StartupDestination.splash:
        return const _FlowSplashView();
      case StartupDestination.onboarding:
        return const OnboardingScreen();
      case StartupDestination.login:
        return const LoginScreen();
      case StartupDestination.license:
        return const LicenseScreen();
      case StartupDestination.home:
        return home ?? const HomeTabsScreen();
    }
  }
}

/// Splash mientras se inicializa el billing (igual que en la app real).
class _FlowSplashView extends StatelessWidget {
  const _FlowSplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Inicializando...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
