import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/app_metadata.dart';
import '../../core/models/result.dart';
import '../../core/utils/pii_cipher.dart';
import '../analytics/analytics_service.dart';
import 'play_billing_service.dart';
import 'play_purchase_success.dart';

/// Keys used in [SharedPreferences] to persist license info.
const _kLicenseExpiry = 'license_expiry';
const _kLicenseProductId = 'license_product_id';
const _kLicensePurchaseToken = 'license_purchase_token';
const _kOnboardingCompleted = 'onboarding_completed';
const _kDisclaimerSeen = 'disclaimer_seen';
const _kLoginUsername = 'login_username';

/// Possible states for a payment operation.
enum PaymentState { idle, loading, success, error }

/// Provider that manages the payment/license flow.
///
/// Replaces the BLoC pattern from machote with a simple [ChangeNotifier].
class PaymentProvider extends ChangeNotifier {
  final PlayBillingService _billingService;
  final SharedPreferences _prefs;

  /// Analytics opcional: por defecto usa el singleton global, pero se inyecta
  /// en pruebas para no depender de Firebase nativo.
  final AnalyticsService _analytics;

  /// Notifica a la capa de cuentas cuando se detecta una renovación PAGADA o
  /// una suscripción activa en la misma cuenta de Google, para que extienda la
  /// licencia del perfil de la sesión activa (no solo la del dispositivo).
  ///
  /// DI seam (Rule 0.2): lo registra [UserAccountService] en su constructor.
  void Function(DateTime? renewedExpiry, String productId)?
  onSubscriptionRenewed;

  /// Cuenta de validación integrada (acceso libre), si está configurada.
  ///
  /// Se inyecta desde [main] (leída de `app_metadata.json`). Si es `null` o las
  /// credenciales no coinciden, el acceso libre no se concede y el usuario debe
  /// seguir el flujo normal (pago).
  final BuiltinAccountConfig? _builtinAccount;

  PaymentProvider(
    this._billingService,
    this._prefs, {
    BuiltinAccountConfig? builtinAccount,
    AnalyticsService? analytics,
  }) : _builtinAccount = builtinAccount,
       _analytics = analytics ?? AnalyticsService.instance {
    // DI seam (Rule 0.2): the service never calls the provider directly; the
    // provider registers its renewal handler in the constructor.
    _billingService.onRenewalDetected = _handleRenewalDetected;
  }

  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------
  PaymentState _state = PaymentState.idle;
  PaymentState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// User-friendly error message suitable for displaying in the UI.
  /// Filters out internal exceptions and technical jargon.
  String? get userFriendlyError {
    if (_errorMessage == null) return null;
    final msg = _errorMessage!;
    // Hide internal platform exceptions (LateInitializationError, etc.)
    if (msg.contains('LateInitializationError') ||
        msg.contains('has not been initialized') ||
        msg.contains('Field') && msg.contains('instance@')) {
      return 'Esta función no está disponible en este dispositivo. '
          'Por favor usa la aplicación en un dispositivo Android o iOS.';
    }
    // Hide stack-trace style messages
    if (msg.contains('Exception:') || msg.contains('Error:')) {
      return msg.replaceAll(RegExp(r'(Exception|Error):\s*'), '').trim();
    }
    return msg;
  }

  /// Whether the last error is due to Play Billing being unavailable on this
  /// platform (e.g. web), as opposed to a real store failure.
  bool get isBillingUnavailableError =>
      _errorMessage == kBillingUnavailableMessage;

  /// Whether the last error means the current Google account has no ACTIVE,
  /// PAID subscription (e.g. it lapsed or was bought with another account).
  bool get isNoActiveSubscriptionError =>
      _errorMessage == kNoSubscriptionMessage;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // -----------------------------------------------------------------------
  // License info
  // -----------------------------------------------------------------------

  /// The license expiry date (null = perpetual).
  DateTime? get licenseExpiry {
    final expiryStr = _prefs.getString(_kLicenseExpiry);
    if (expiryStr == null) return null;
    return DateTime.tryParse(expiryStr);
  }

  /// The purchased product ID.
  String? get licenseProductId => _prefs.getString(_kLicenseProductId);

  /// Whether the user has a valid (non-expired) license.
  bool get hasValidLicense {
    final expiry = licenseExpiry;
    if (expiry == null) {
      // No expiry stored → check if we have any license at all
      return _prefs.containsKey(_kLicenseProductId);
    }
    return DateTime.now().isBefore(expiry);
  }

  /// Whether the user has completed onboarding.
  bool get isOnboardingCompleted =>
      _prefs.getBool(_kOnboardingCompleted) ?? false;

  /// Whether the user has ever purchased anything.
  bool get hasEverPurchased => _prefs.containsKey(_kLicenseProductId);

  /// Username of the validator account logged in (set via [grantValidatorAccess]).
  String? get loginUsername => _prefs.getString(_kLoginUsername);

  /// Whether the validator account is currently logged in (free access granted).
  bool get isLoggedIn => _prefs.containsKey(_kLoginUsername);

  // -----------------------------------------------------------------------
  // Initialization
  // -----------------------------------------------------------------------

  /// Initialize the billing service.
  ///
  /// On platforms without Google Play (e.g. Windows, Linux, macOS, web),
  /// the billing service will fail. We still mark `_isInitialized = true`
  /// so the UI can proceed past the splash screen. The user will only see
  /// the error if they try to actually make a purchase.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isLoading = true;
    notifyListeners();

    final result = await _billingService.initialize();
    result.when(
      onSuccess: (_) {
        _isInitialized = true;
        _isLoading = false;
        _state = PaymentState.idle;
        notifyListeners();
        // Fire-and-forget: extend the local license ONLY if the same Google
        // account has an ACTIVE, PAID subscription (never free access).
        unawaited(_refreshLicenseFromActiveSubscription());
      },
      onFailure: (message) {
        // ⚠️ CRITICAL: even on failure we mark the provider as initialized.
        // Otherwise the app is stuck on the "Inicializando..." screen on
        // platforms where Google Play is not available (Windows, Linux,
        // macOS, web, iOS simulator, etc.).
        _isInitialized = true;
        _isLoading = false;
        _state = PaymentState.error;
        _errorMessage = message;
        notifyListeners();
      },
    );
  }

  // -----------------------------------------------------------------------
  // Purchase
  // -----------------------------------------------------------------------

  /// Purchase the annual subscription.
  Future<Result<PlayPurchaseSuccess>> purchaseAnnual() async {
    return _executePurchase(() => _billingService.purchaseAnnualLicense());
  }

  /// Purchase the perpetual license.
  Future<Result<PlayPurchaseSuccess>> purchasePerpetual() async {
    return _executePurchase(() => _billingService.purchasePerpetualLicense());
  }

  /// Purchase the semestral subscription.
  Future<Result<PlayPurchaseSuccess>> purchaseSemestral() async {
    return _executePurchase(() => _billingService.purchaseSemestralLicense());
  }

  /// Restore ("Recuperar acceso") an existing purchase.
  Future<Result<PlayPurchaseSuccess>> restorePurchase() async {
    // Renewal semantics: a restored license extends from max(now, prev expiry).
    return _executePurchase(
      () => _billingService.restoreSemestralLicense(),
      renew: true,
    );
  }

  /// Internal purchase executor that manages state transitions.
  ///
  /// Locks the UI ([_isLoading]) for the whole operation so a double-tap can't
  /// trigger a second call to Google Play (fixes the "Operación cancelada."
  /// cascade from double clicks).
  Future<Result<PlayPurchaseSuccess>> _executePurchase(
    Future<Result<PlayPurchaseSuccess>> Function() purchaseFn, {
    bool renew = false,
  }) async {
    _isLoading = true;
    _state = PaymentState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await purchaseFn();

    _isLoading = false;
    result.when(
      onSuccess: (success) {
        _saveLicense(success, renew: renew);
        if (!renew) {
          // Solo las compras NUEVAS generan evento de purchase: la restauración,
          // la renovación automática y el refresco al arrancar no re-registran
          // la conversión (evita doble conteo).
          unawaited(_analytics.logVerifiedPlayPurchase(success));
        }
        _state = PaymentState.success;
        notifyListeners();
      },
      onFailure: (message) {
        _state = PaymentState.error;
        _errorMessage = message;
        notifyListeners();
      },
    );

    return result;
  }

  // -----------------------------------------------------------------------
  // License persistence
  // -----------------------------------------------------------------------

  /// Save license info after a successful purchase.
  ///
  /// When [renew] is true (auto-renewal or "Recuperar acceso" for an existing
  /// subscription), the new expiry is computed from the later of "now" and the
  /// previous expiry, so renewing never shortens the user's remaining access.
  DateTime? _saveLicense(PlayPurchaseSuccess purchase, {bool renew = false}) {
    DateTime? expiry;
    // For a subscription, set an expiry. For perpetual, don't set an expiry.
    if (purchase.verifiedProductId == kProductIdAnnual) {
      expiry = _renewalBase(renew).add(const Duration(days: 365));
      _prefs.setString(_kLicenseExpiry, expiry.toIso8601String());
    } else if (purchase.verifiedProductId == kProductIdSemestral) {
      expiry = _renewalBase(renew).add(const Duration(days: 180));
      _prefs.setString(_kLicenseExpiry, expiry.toIso8601String());
    }
    // For perpetual, we don't set an expiry (null = perpetual).

    _prefs.setString(_kLicenseProductId, purchase.verifiedProductId);
    if (purchase.purchaseToken != null) {
      // Token de compra: dato sensible, se guarda ofuscado en reposo.
      _prefs.setString(
        _kLicensePurchaseToken,
        PiiCipher.encode(purchase.purchaseToken!),
      );
    }
    return expiry;
  }

  /// Base date for a license expiry: "now" for new purchases, or the later of
  /// "now" and the previous expiry for renewals/restores.
  DateTime _renewalBase(bool renew) {
    if (!renew) return DateTime.now();
    final prev = licenseExpiry;
    if (prev != null && DateTime.now().isBefore(prev)) return prev;
    return DateTime.now();
  }

  /// Called by [PlayBillingService] when a PAID renewal / existing active
  /// subscription is detected on the same Google account. Extends the local
  /// license from its current expiry (renewal-aware) and propagates the new
  /// expiry to the account layer so the session's license stays in sync.
  void _handleRenewalDetected(PlayPurchaseSuccess purchase) {
    final expiry = _saveLicense(purchase, renew: true);
    onSubscriptionRenewed?.call(expiry, purchase.verifiedProductId);
    notifyListeners();
  }

  /// Startup check: extend the local license ONLY if the current Google account
  /// has an ACTIVE, PAID subscription. If it lapsed, nothing is granted — the
  /// user must pay again.
  Future<void> _refreshLicenseFromActiveSubscription() async {
    final result = await _billingService.checkActiveSubscription(
      productId: kProductIdSemestral,
    );
    final purchase = result.valueOrNull;
    if (purchase == null) return;
    final expiry = _saveLicense(purchase, renew: true);
    onSubscriptionRenewed?.call(expiry, purchase.verifiedProductId);
    notifyListeners();
  }

  /// Mark onboarding as completed.
  Future<void> completeOnboarding() async {
    await _prefs.setBool(_kOnboardingCompleted, true);
    unawaited(_analytics.logOnboardingComplete());
    notifyListeners();
  }

  /// Grant free full-flow access to the configured validator account.
  ///
  /// Solo concede acceso si existe cuenta integrada configurada (`builtin_account`
  /// en `app_metadata.json`) y las credenciales coinciden (usuario con trim y
  /// case-insensitive, password exacta). Devuelve `false` en cualquier otro caso
  /// y el usuario debe seguir el flujo normal (pago).
  ///
  /// Al coincidir, persiste un usuario `login_username` y una licencia con
  /// vencimiento (`now + license_days`, product id semestral), marcando
  /// onboarding como completado para que aterrice directo en la pantalla
  /// principal.
  Future<bool> grantValidatorAccess(String username, String password) async {
    final config = _builtinAccount;
    if (config == null || !config.matches(username, password)) {
      return false;
    }
    final expiry = DateTime.now().add(Duration(days: config.licenseDays));
    await _prefs.setString(_kLoginUsername, config.username);
    await _prefs.setString(_kLicenseExpiry, expiry.toIso8601String());
    await _prefs.setString(_kLicenseProductId, kProductIdSemestral);
    await _prefs.setBool(_kOnboardingCompleted, true);
    notifyListeners();
    return true;
  }

  /// Aplica una licencia al dispositivo (sin pasar por un pago nuevo).
  ///
  /// Usado por la capa de cuentas para sincronizar la licencia de la cuenta con
  /// el dispositivo, de modo que `hasValidLicense` y el flujo de entrada sean
  /// consistentes. Si [expiry] es `null` la licencia es perpetua.
  Future<void> applyLicense({
    required DateTime? expiry,
    required String productId,
  }) async {
    if (expiry != null) {
      await _prefs.setString(_kLicenseExpiry, expiry.toIso8601String());
    } else {
      await _prefs.remove(_kLicenseExpiry);
    }
    await _prefs.setString(_kLicenseProductId, productId);
    notifyListeners();
  }

  /// Cierra sesión y limpia la licencia del DISPOSITIVO.
  ///
  /// Mantiene `onboarding_completed` (el usuario ya vio el onboarding). Se usa
  /// junto con [UserAccountService.logoutUser] para que, tras cerrar sesión, la
  /// app regrese al login (regla: no se entra sin pagar o sin usuario).
  Future<void> logout() async {
    await _prefs.remove(_kLoginUsername);
    await _prefs.remove(_kLicenseExpiry);
    await _prefs.remove(_kLicenseProductId);
    await _prefs.remove(_kLicensePurchaseToken);
    notifyListeners();
  }

  /// Reset the license (for testing / debugging).
  Future<void> resetLicense() async {
    await _prefs.remove(_kLicenseExpiry);
    await _prefs.remove(_kLicenseProductId);
    await _prefs.remove(_kLicensePurchaseToken);
    await _prefs.remove(_kOnboardingCompleted);
    await _prefs.remove(_kLoginUsername);
    notifyListeners();
  }

  /// Reset state to idle.
  void resetState() {
    _state = PaymentState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  /// Limpia el estado TRANSITORIO (loading/error) al montar una nueva sesión
  /// de checkout (p. ej. al abrir `/payment`).
  ///
  /// Es la corrección de raíz del ciclo de recuperación: un restore fallido
  /// hecho desde cualquier pantalla dejaba `_state=error` y `_errorMessage`
  /// envenenando el singleton; al volver a `/payment` se mostraba un error
  /// fantasma en lugar de la selección de plan. No toca la licencia persistida
  /// ni el flag de inicialización.
  void resetTransientState() {
    _state = PaymentState.idle;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Whether the user has already seen the disclaimer on first use.
  bool get isDisclaimerSeen => _prefs.getBool(_kDisclaimerSeen) ?? false;

  /// Mark the first-use disclaimer as acknowledged.
  Future<void> markDisclaimerSeen() async {
    await _prefs.setBool(_kDisclaimerSeen, true);
    notifyListeners();
  }
}
