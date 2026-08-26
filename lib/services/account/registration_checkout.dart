import '../../core/models/user_profile.dart';
import '../billing/payment_provider.dart';
import '../billing/play_purchase_success.dart';
import 'pending_registration.dart';
import 'user_account_service.dart';

/// Orquesta el cierre del checkout diferido: solo después de una compra
/// VERIFICADA se materializa la cuenta de usuario y se aplica la licencia.
///
/// Sigue la regla del proyecto: nadie entra sin pagar o sin usuario; las
/// cuentas no se crean "en el aire" antes de tener una compra válida.
class RegistrationCheckout {
  final UserAccountService accounts;
  final PaymentProvider payments;

  const RegistrationCheckout({required this.accounts, required this.payments});

  /// Cierra el registro pendiente usando la compra ya verificada.
  ///
  /// Crea la cuenta con la licencia reflejada en el dispositivo y abre sesión.
  /// Devuelve `false` si el usuario ya existe o falla la materialización.
  Future<bool> completeCheckoutAfterVerifiedPurchase({
    required PendingRegistration pending,
    required PlayPurchaseSuccess purchase,
  }) async {
    if (accounts.usernameExists(pending.username)) return false;

    final user = await accounts.createAccountWithLicense(
      pending: pending,
      licenseExpiry: payments.licenseExpiry,
      productId: purchase.verifiedProductId,
    );
    if (user == null) return false;

    await accounts.openSession(user, rememberMe: true);
    return true;
  }

  /// Vincula una licencia YA existente (del dispositivo) a una cuenta.
  ///
  /// - Si [pending] != null: crea la cuenta del registro pendiente reutilizando
  ///   la licencia del dispositivo (flujo "Vincular licencia a mi cuenta").
  /// - Si [user] != null: vincula la licencia del dispositivo a la sesión
  ///   activa (renovación desde la pantalla de licencia).
  Future<bool> linkToExistingLicense({
    PendingRegistration? pending,
    UserProfile? user,
  }) async {
    if (pending != null) {
      final created = await accounts.createAccountWithDeviceLicense(
        pending: pending,
      );
      if (created == null) return false;
      await accounts.openSession(created, rememberMe: true);
      return true;
    }
    if (user != null) {
      await accounts.linkDeviceLicenseToUser(user);
      return true;
    }
    return false;
  }
}
