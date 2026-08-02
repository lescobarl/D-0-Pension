import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/result.dart';
import 'play_billing_service.dart';
import 'play_purchase_success.dart';

/// Keys used in [SharedPreferences] to persist license info.
const _kLicenseExpiry = 'license_expiry';
const _kLicenseProductId = 'license_product_id';
const _kLicensePurchaseToken = 'license_purchase_token';
const _kOnboardingCompleted = 'onboarding_completed';
const _kDemoMode = 'demo_mode_enabled';

/// Possible states for a payment operation.
enum PaymentState { idle, loading, success, error }

/// Provider that manages the payment/license flow.
///
/// Replaces the BLoC pattern from machote with a simple [ChangeNotifier].
class PaymentProvider extends ChangeNotifier {
  final PlayBillingService _billingService;
  final SharedPreferences _prefs;

  PaymentProvider(this._billingService, this._prefs);

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

  /// Whether the user has a valid (non-expired) license or demo mode is on.
  bool get hasValidLicense {
    // Demo mode bypasses the license check entirely.
    if (isDemoModeEnabled) return true;
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

  /// Whether the user has enabled demo mode (bypasses payment on non-Android).
  bool get isDemoModeEnabled => _prefs.getBool(_kDemoMode) ?? false;

  /// Whether the user has ever purchased anything.
  bool get hasEverPurchased => _prefs.containsKey(_kLicenseProductId);

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

  /// Restore an existing purchase.
  Future<Result<PlayPurchaseSuccess>> restorePurchase() async {
    return _executePurchase(() => _billingService.restoreAnnualLicense());
  }

  /// Internal purchase executor that manages state transitions.
  Future<Result<PlayPurchaseSuccess>> _executePurchase(
    Future<Result<PlayPurchaseSuccess>> Function() purchaseFn,
  ) async {
    _state = PaymentState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await purchaseFn();

    result.when(
      onSuccess: (success) {
        _saveLicense(success);
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
  void _saveLicense(PlayPurchaseSuccess purchase) {
    // For a subscription, set expiry to 1 year from now.
    // For perpetual, don't set an expiry.
    if (purchase.verifiedProductId == kProductIdAnnual) {
      final expiry = DateTime.now().add(const Duration(days: 365));
      _prefs.setString(_kLicenseExpiry, expiry.toIso8601String());
    }
    // For perpetual, we don't set an expiry (null = perpetual).

    _prefs.setString(_kLicenseProductId, purchase.verifiedProductId);
    if (purchase.purchaseToken != null) {
      _prefs.setString(_kLicensePurchaseToken, purchase.purchaseToken!);
    }
  }

  /// Mark onboarding as completed.
  Future<void> completeOnboarding() async {
    await _prefs.setBool(_kOnboardingCompleted, true);
    notifyListeners();
  }

  /// Reset the license (for testing / debugging).
  Future<void> resetLicense() async {
    await _prefs.remove(_kLicenseExpiry);
    await _prefs.remove(_kLicenseProductId);
    await _prefs.remove(_kLicensePurchaseToken);
    await _prefs.remove(_kOnboardingCompleted);
    notifyListeners();
  }

  /// Reset state to idle.
  void resetState() {
    _state = PaymentState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  /// Enable demo mode so the app bypasses the license check.
  ///
  /// This is useful on platforms where Google Play is not available
  /// (Windows, Linux, macOS, web). Once enabled, [hasValidLicense]
  /// returns `true` and the user can access the full app.
  Future<void> enableDemoMode() async {
    await _prefs.setBool(_kDemoMode, true);
    _state = PaymentState.idle;
    _errorMessage = null;
    notifyListeners();
  }
}
