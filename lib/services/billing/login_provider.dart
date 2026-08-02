import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/pii_cipher.dart';

/// Keys used in [SharedPreferences] to persist user info.
const _kUserEmail = 'user_email';
const _kUserLoggedIn = 'user_logged_in';

/// Provider that manages user login state.
///
/// Simple username/password authentication persisted in SharedPreferences.
/// For production this would integrate with a real auth backend.
class LoginProvider extends ChangeNotifier {
  final SharedPreferences _prefs;

  LoginProvider(this._prefs);

  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------
  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  String? _userEmail;
  String? get userEmail => _userEmail;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // -----------------------------------------------------------------------
  // Initialization
  // -----------------------------------------------------------------------

  /// Restore session from SharedPreferences (called from main.dart).
  void initialize() {
    _isLoggedIn = _prefs.getBool(_kUserLoggedIn) ?? false;
    _userEmail = _decodeEmail(_prefs.getString(_kUserEmail));
    notifyListeners();
  }

  /// Decodes the persisted email. Accepts the obfuscated format (v2+) and
  /// legacy plaintext (older builds stored the raw email; emails contain '@'
  /// and '.' which are outside the base64 alphabet, so decode fails → fallback).
  String? _decodeEmail(String? raw) {
    if (raw == null) return null;
    try {
      return PiiCipher.decode(raw);
    } catch (_) {
      return raw;
    }
  }

  // -----------------------------------------------------------------------
  // Login / Logout
  // -----------------------------------------------------------------------

  /// Attempt to sign in with the given credentials.
  ///
  /// For demo / local development: any email + password >= 4 chars succeeds.
  /// Production: replace with real auth (Firebase, OAuth, etc.).
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Simulate network call
    await Future.delayed(const Duration(milliseconds: 600));

    // Validación básica de email
    if (!email.contains('@')) {
      _isLoading = false;
      _errorMessage = 'Correo electrónico inválido.';
      notifyListeners();
      return false;
    }
    if (password.length < 4) {
      _isLoading = false;
      _errorMessage = 'La contraseña debe tener al menos 4 caracteres.';
      notifyListeners();
      return false;
    }

    // Persist session (email obfuscated at rest via PiiCipher, ver KEY-PII-OFUSCACION.txt)
    await _prefs.setBool(_kUserLoggedIn, true);
    await _prefs.setString(_kUserEmail, PiiCipher.encode(email));

    _isLoggedIn = true;
    _userEmail = email;
    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Sign out and clear persisted credentials.
  Future<void> signOut() async {
    await _prefs.remove(_kUserLoggedIn);
    await _prefs.remove(_kUserEmail);
    _isLoggedIn = false;
    _userEmail = null;
    notifyListeners();
  }
}
