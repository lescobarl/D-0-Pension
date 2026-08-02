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
import 'services/billing/login_provider.dart';
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
  final billingService = PlayBillingService();

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
          create: (_) => PaymentProvider(billingService, prefs)..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => LoginProvider(prefs)..initialize(),
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
      title: 'Calculadora Ley 73 IMSS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromConfig(themeConfig),
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => const _AppEntryPoint(),
        );
      case '/onboarding':
        return MaterialPageRoute(
          builder: (_) => const OnboardingScreen(),
        );
      case '/login':
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        );
      case '/payment':
        return MaterialPageRoute(
          builder: (_) => const PaymentScreen(),
        );
      case '/license':
        return MaterialPageRoute(
          builder: (_) => const LicenseScreen(),
        );
      case '/home':
        return MaterialPageRoute(
          builder: (_) => SelectionArea(
            child: const HomeTabsScreen(),
          ),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const _AppEntryPoint(),
        );
    }
  }
}

/// Entry point that decides whether to show onboarding, login, payment, or home.
///
/// Flow:
/// 1. If user has NOT completed onboarding → show OnboardingScreen
/// 2. If user is NOT logged in → show LoginScreen
/// 3. If user has NO valid license → show PaymentScreen
/// 4. Otherwise → show HomeTabsScreen
class _AppEntryPoint extends StatelessWidget {
  const _AppEntryPoint();

  @override
  Widget build(BuildContext context) {
    final paymentProvider = context.watch<PaymentProvider>();
    final loginProvider = context.watch<LoginProvider>();

    // Wait for payment initialization
    if (!paymentProvider.isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Inicializando...',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 1. Onboarding not completed → show onboarding
    if (!paymentProvider.isOnboardingCompleted) {
      return const OnboardingScreen();
    }

    // 2. User not logged in → show login
    if (!loginProvider.isLoggedIn) {
      return const LoginScreen();
    }

    // 3. No valid license → show payment
    if (!paymentProvider.hasValidLicense) {
      return const PaymentScreen();
    }

    // 4. All good → show home
    return SelectionArea(
      child: const HomeTabsScreen(),
    );
  }
}
