import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/user_profile.dart';
import '../billing/payment_provider.dart';
import 'pending_registration.dart';

/// Resultado de un intento de inicio de sesión con cuenta local.
enum AccountLoginResult { ok, notFound, wrongPassword }

/// Almacena las cuentas de usuario y la sesión activa.
///
/// Las cuentas se persisten como lista JSON en [SharedPreferences]. Las
/// contraseñas NUNCA se guardan en claro: solo un hash SHA-256 con sal (ver
/// [PasswordHasher] y [UserProfile]).
///
/// La licencia de la cuenta se sincroniza con [PaymentProvider] (licencia de
/// dispositivo) para que `hasValidLicense` y el flujo de entrada sean
/// consistentes.
class UserAccountService extends ChangeNotifier {
  static const _kAccountsKey = 'user_accounts';
  static const _kSessionUsername = 'session_username';
  static const _kRememberMe = 'remember_me';

  final SharedPreferences _prefs;
  final PaymentProvider _payments;

  late final Map<String, UserProfile> _accounts;
  String? _sessionUsername;
  bool _rememberMe = true;

  UserAccountService(this._prefs, {required PaymentProvider payments})
    : _payments = payments {
    _accounts = _loadAccounts(_prefs);
    _sessionUsername = _prefs.getString(_kSessionUsername);
    _rememberMe = _prefs.getBool(_kRememberMe) ?? true;
    // DI seam (Rule 0.2): cuando se detecta una renovación PAGADA en la misma
    // cuenta de Google (auto-renovación, "Recuperar acceso" o check de arranque),
    // la licencia de la CUENTA de la sesión activa también se extiende. Sin esto,
    // la renovación solo actualizaba la licencia de DISPOSITIVO y al reabrir
    // sesión la licencia anterior de la cuenta la sobrescribía.
    _payments.onSubscriptionRenewed = _handleAccountRenewal;
  }

  // ---------------------------------------------------------------------
  // Estado de solo lectura
  // ---------------------------------------------------------------------

  List<UserProfile> get allAccounts => _accounts.values.toList(growable: false);

  /// Normaliza (trim + minúsculas) para comparaciones case-insensitive.
  static String normalize(String username) => username.trim().toLowerCase();

  bool usernameExists(String username) =>
      _accounts.containsKey(normalize(username));

  UserProfile? findByUsername(String username) =>
      _accounts[normalize(username)];

  String? get currentSessionUsername => _sessionUsername;

  bool get isLoggedIn => _sessionUsername != null;

  UserProfile? get currentUser {
    final username = _sessionUsername;
    if (username == null) return null;
    return _accounts[normalize(username)];
  }

  bool get isAccountLicenseValid {
    final user = currentUser;
    return user != null && user.isLicenseValid;
  }

  bool get rememberMe => _rememberMe;

  // ---------------------------------------------------------------------
  // Sesión
  // ---------------------------------------------------------------------

  /// Intenta iniciar sesión con credenciales en claro.
  Future<AccountLoginResult> loginUser(
    String username,
    String password, {
    bool rememberMe = true,
  }) async {
    final user = findByUsername(username);
    if (user == null) return AccountLoginResult.notFound;
    if (!user.verifyPassword(password)) {
      return AccountLoginResult.wrongPassword;
    }
    await openSession(user, rememberMe: rememberMe);
    return AccountLoginResult.ok;
  }

  /// Abre una sesión para un usuario ya autenticado (sin pedir password).
  ///
  /// Usado por el checkout: tras una compra verificada no se vuelve a pedir la
  /// contraseña en claro.
  Future<void> openSession(UserProfile user, {bool rememberMe = true}) async {
    _sessionUsername = user.username;
    _rememberMe = rememberMe;
    await _prefs.setBool(_kRememberMe, rememberMe);
    if (rememberMe) {
      await _prefs.setString(_kSessionUsername, user.username);
    } else {
      await _prefs.remove(_kSessionUsername);
    }

    // Con licencia en la cuenta: se sincroniza al dispositivo.
    if (user.purchasedProductId != null) {
      await _syncLicenseToDevice(user);
    } else {
      // Sin licencia en la cuenta: se intenta vincular una licencia de
      // dispositivo ya comprada/restaurada (p. ej. tras la recuperación).
      await _linkDeviceLicenseIfUnlinked(user);
    }

    notifyListeners();
  }

  /// Cierra la sesión local. La licencia de la CUENTA se conserva en el
  /// perfil; la licencia de DISPOSITIVO se limpia desde la UI llamando
  /// [PaymentProvider.logout] (regla: no se entra sin pagar o sin usuario).
  Future<void> logoutUser() async {
    _sessionUsername = null;
    await _prefs.remove(_kSessionUsername);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Creación / renovación de cuentas
  // ---------------------------------------------------------------------

  /// Crea una cuenta nueva aplicándole una licencia recién comprada.
  ///
  /// Devuelve `null` si el usuario ya existe (o por cualquier otra razón no se
  /// puede materializar la cuenta).
  Future<UserProfile?> createAccountWithLicense({
    required PendingRegistration pending,
    required DateTime? licenseExpiry,
    required String productId,
  }) async {
    if (usernameExists(pending.username)) return null;
    final now = DateTime.now();
    final user = UserProfile(
      id: 'u_${now.microsecondsSinceEpoch}',
      username: pending.username,
      salt: pending.salt,
      passwordHash: pending.passwordHash,
      email: pending.email,
      licenseExpiry: licenseExpiry,
      purchasedProductId: productId,
      createdAt: now,
    );
    _accounts[normalize(user.username)] = user;
    await _saveAccounts();
    // Refleja la licencia a nivel dispositivo para `hasValidLicense`.
    await _payments.applyLicense(expiry: licenseExpiry, productId: productId);
    notifyListeners();
    return user;
  }

  /// Crea una cuenta reutilizando la licencia de dispositivo ya vigente
  /// (flujo "Vincular licencia a mi cuenta" / recuperación).
  ///
  /// Devuelve `null` si el usuario ya existe o no hay licencia válida.
  Future<UserProfile?> createAccountWithDeviceLicense({
    required PendingRegistration pending,
  }) async {
    if (usernameExists(pending.username)) return null;
    if (!_payments.hasValidLicense) return null;

    final now = DateTime.now();
    final user = UserProfile(
      id: 'u_${now.microsecondsSinceEpoch}',
      username: pending.username,
      salt: pending.salt,
      passwordHash: pending.passwordHash,
      email: pending.email,
      licenseExpiry: _payments.licenseExpiry,
      purchasedProductId: _payments.licenseProductId,
      createdAt: now,
    );
    _accounts[normalize(user.username)] = user;
    await _saveAccounts();
    notifyListeners();
    return user;
  }

  /// Renueva la licencia de un usuario existente tras una nueva compra.
  Future<bool> renewLicenseForUser(
    UserProfile user, {
    required DateTime? licenseExpiry,
    required String productId,
  }) async {
    final updated = user.copyWith(
      licenseExpiry: licenseExpiry,
      clearLicenseExpiry: licenseExpiry == null,
      purchasedProductId: productId,
      clearPurchasedProductId: false,
    );
    _accounts[normalize(updated.username)] = updated;
    await _saveAccounts();
    await _payments.applyLicense(expiry: licenseExpiry, productId: productId);
    notifyListeners();
    return true;
  }

  /// Vincula la licencia de dispositivo vigente a la cuenta del usuario.
  Future<void> linkDeviceLicenseToUser(UserProfile user) async {
    final productId = _payments.licenseProductId;
    if (productId == null) return;
    final expiry = _payments.licenseExpiry;
    final updated = user.copyWith(
      licenseExpiry: expiry,
      clearLicenseExpiry: expiry == null,
      purchasedProductId: productId,
      clearPurchasedProductId: false,
    );
    _accounts[normalize(updated.username)] = updated;
    await _saveAccounts();
    notifyListeners();
  }

  /// Extiende la licencia de la cuenta de la sesión activa cuando se detecta
  /// una renovación PAGADA o una suscripción activa en la misma cuenta de
  /// Google (auto-renovación de Play, "Recuperar acceso" o check de arranque).
  ///
  /// Toma el vencimiento MAYOR entre el actual y el renovado para nunca
  /// acortar el acceso restante del usuario. Sin esta propagación, el arranque
  /// ([AppStartup.resolveStartupDestination]) prioriza la licencia de la cuenta
  /// y `_syncLicenseToDevice` sobrescribiría la renovada con la anterior.
  void _handleAccountRenewal(DateTime? renewedExpiry, String productId) {
    final user = currentUser;
    if (user == null || renewedExpiry == null) return;

    final currentExpiry = user.licenseExpiry;
    final nextExpiry =
        (currentExpiry != null && currentExpiry.isAfter(renewedExpiry))
        ? currentExpiry
        : renewedExpiry;

    final updated = user.copyWith(
      licenseExpiry: nextExpiry,
      clearLicenseExpiry: false,
      purchasedProductId: productId,
      clearPurchasedProductId: false,
    );
    _accounts[normalize(updated.username)] = updated;
    // Fire-and-forget: el callback del billing no debe bloquear el flujo.
    unawaited(_saveAccounts());
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------

  Future<void> _syncLicenseToDevice(UserProfile user) async {
    await _payments.applyLicense(
      expiry: user.licenseExpiry,
      productId: user.purchasedProductId!,
    );
  }

  Future<void> _linkDeviceLicenseIfUnlinked(UserProfile user) async {
    if (user.purchasedProductId != null) return; // ya tiene licencia
    if (!_payments.hasValidLicense) return;
    await linkDeviceLicenseToUser(user);
  }

  Future<void> _saveAccounts() async {
    final list = _accounts.values.map((u) => u.toJson()).toList();
    await _prefs.setString(_kAccountsKey, jsonEncode(list));
  }

  static Map<String, UserProfile> _loadAccounts(SharedPreferences prefs) {
    final raw = prefs.getString(_kAccountsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      final map = <String, UserProfile>{};
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final user = UserProfile.fromJson(item);
          map[normalize(user.username)] = user;
        }
      }
      return map;
    } catch (e) {
      // Prefs corruptos: no bloqueamos el arranque; se descartan y, si hace
      // falta, se vuelven a crear.
      debugPrint('UserAccountService: no se pudieron leer las cuentas: $e');
      return {};
    }
  }
}
