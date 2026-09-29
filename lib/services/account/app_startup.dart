import '../billing/payment_provider.dart';
import 'user_account_service.dart';

/// Destino que debe mostrar el entry point.
enum StartupDestination { splash, onboarding, login, license, home }

/// Decide el punto de entrada de la app de forma ÚNICA (sin rutas dobles).
///
/// Orden de resolución:
/// 1. Sin inicializar → splash.
/// 2. Sin onboarding → onboarding.
/// 3. Sesión activa → home si la licencia de la cuenta es válida; si no,
///    pantalla de licencia (renovar/comprar).
/// 4. Validator (acceso libre) → home si tiene licencia vigente.
/// 5. Licencia de dispositivo vigente → home.
/// 6. Licencia de dispositivo vencida → pantalla de licencia (renovar).
/// 7. Sin nada → login.
class AppStartup {
  AppStartup._();

  static StartupDestination resolveStartupDestination({
    required PaymentProvider payments,
    required UserAccountService accounts,
  }) {
    if (!payments.isInitialized) return StartupDestination.splash;
    if (!payments.isOnboardingCompleted) {
      return StartupDestination.onboarding;
    }

    // Sesión activa: la cuenta manda sobre la licencia del dispositivo.
    if (accounts.isLoggedIn) {
      final user = accounts.currentUser;
      if (user != null && user.isLicenseValid) {
        return StartupDestination.home;
      }
      return StartupDestination.license;
    }

    // Cuenta de validación (acceso libre integrado).
    if (payments.isLoggedIn) {
      return payments.hasValidLicense
          ? StartupDestination.home
          : StartupDestination.license;
    }

    // Licencia de dispositivo vigente.
    if (payments.hasValidLicense) return StartupDestination.home;

    // Hay licencia pero está vencida → pantalla de licencia (renovar).
    if (syncExpiredLicenseFlags(payments: payments)) {
      return StartupDestination.license;
    }

    return StartupDestination.login;
  }

  /// Al arrancar con sesión restaurada, si por algún motivo el onboarding no
  /// quedó marcado, se completa (idempotente) para no bloquear al usuario.
  static Future<void> bootstrapGuest({
    required PaymentProvider payments,
    required UserAccountService accounts,
  }) async {
    if (accounts.isLoggedIn && !payments.isOnboardingCompleted) {
      await payments.completeOnboarding();
    }
  }

  /// `true` si existe una licencia con fecha de vencimiento ya superada.
  static bool syncExpiredLicenseFlags({required PaymentProvider payments}) {
    final expiry = payments.licenseExpiry;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }
}
