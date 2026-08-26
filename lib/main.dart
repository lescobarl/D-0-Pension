import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/engine/formula_evaluator.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home_tabs_screen.dart';
import 'presentation/screens/license_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/payment_screen.dart';
import 'services/account/app_startup.dart';
import 'services/account/pending_registration.dart';
import 'services/account/registration_checkout.dart';
import 'services/account/user_account_service.dart';
import 'services/account/validation_privileges_service.dart';
import 'services/analytics/analytics_service.dart';
import 'services/billing/payment_provider.dart';
import 'services/billing/play_billing_service.dart';
import 'services/persistence_service.dart';
import 'services/retroactive_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize dependencies
  final prefs = await SharedPreferences.getInstance();
  final persistenceService = PersistenceService(prefs);
  final formulaEvaluator = FormulaEvaluator();
  // Carga app_metadata.json antes de runApp: expone la cuenta de validación
  // integrada (builtin_account) y la configuración de tema. Es idempotente
  // respecto a RetroactiveProvider.initialize (que también la invoca).
  await formulaEvaluator.initialize();
  final billingService = PlayBillingService();

  // Firebase Analytics: no bloqueante y solo activo en Android.
  unawaited(AnalyticsService.instance.init());

  runApp(
    MultiProvider(
      providers: [
        // Única fuente de verdad: RetroactiveProvider (monolito funcional)
        ChangeNotifierProvider(
          create: (_) => RetroactiveProvider(
            evaluator: formulaEvaluator,
            persistence: persistenceService,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => PaymentProvider(
            billingService,
            prefs,
            builtinAccount: formulaEvaluator.metadata.builtinAccount,
          )..initialize(),
        ),
        // Cuentas de usuario + sesión. Depende de PaymentProvider para
        // sincronizar la licencia de la cuenta con la del dispositivo.
        ChangeNotifierProvider<UserAccountService>(
          create: (context) {
            final payments = context.read<PaymentProvider>();
            final accounts = UserAccountService(prefs, payments: payments);
            // Idempotente: si hay sesión restaurada y faltara el onboarding,
            // se completa para no bloquear al usuario.
            unawaited(
              AppStartup.bootstrapGuest(accounts: accounts, payments: payments),
            );
            return accounts;
          },
        ),
        // Excepción única de acceso libre (cuenta de validación integrada).
        Provider<ValidationPrivilegesService>(
          create: (_) => ValidationPrivilegesService(
            formulaEvaluator.metadata.builtinAccount,
          ),
        ),
        // Orquesta el checkout diferido (registro + compra verificada).
        Provider<RegistrationCheckout>(
          create: (context) => RegistrationCheckout(
            accounts: context.read<UserAccountService>(),
            payments: context.read<PaymentProvider>(),
          ),
        ),
      ],
      child: const PensionCalculatorApp(),
    ),
  );
}

/// Root widget for the Pension Calculator app.
class PensionCalculatorApp extends StatelessWidget {
  const PensionCalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Obtener configuración de tema desde RetroactiveProvider (única fuente)
    final evaluator = context.watch<RetroactiveProvider>().evaluator;
    final themeConfig = evaluator.isInitialized == true
        ? evaluator.metadata.theme
        : null;

    return MaterialApp(
      title: 'Calculadora Pensión Ley 73 IA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromConfig(themeConfig),
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const _AppEntryPoint());
      case '/onboarding':
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case '/payment':
        // El argumento opcional transporta el registro pendiente cuando el
        // usuario llegó desde el registro de la pantalla de login.
        return MaterialPageRoute(
          builder: (_) => PaymentScreen(
            pendingRegistration: settings.arguments as PendingRegistration?,
          ),
        );
      case '/license':
        return MaterialPageRoute(builder: (_) => const LicenseScreen());
      case '/home':
        return MaterialPageRoute(
          builder: (_) => SelectionArea(child: const HomeTabsScreen()),
        );
      default:
        return MaterialPageRoute(builder: (_) => const _AppEntryPoint());
    }
  }
}

/// Entry point that decides whether to show onboarding, login, license, or
/// home using the unique startup resolver ([AppStartup]) — no double routes.
class _AppEntryPoint extends StatelessWidget {
  const _AppEntryPoint();

  @override
  Widget build(BuildContext context) {
    final payments = context.watch<PaymentProvider>();
    final accounts = context.watch<UserAccountService>();

    switch (AppStartup.resolveStartupDestination(
      payments: payments,
      accounts: accounts,
    )) {
      case StartupDestination.splash:
        return const _SplashView();
      case StartupDestination.onboarding:
        return const OnboardingScreen();
      case StartupDestination.login:
        return const LoginScreen();
      case StartupDestination.license:
        return const LicenseScreen();
      case StartupDestination.home:
        return SelectionArea(child: const HomeTabsScreen());
    }
  }
}

/// Splash mientras se inicializa el billing.
class _SplashView extends StatelessWidget {
  const _SplashView();

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
