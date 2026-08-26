import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Utilidades de hash de contraseñas (SHA-256 + salt por usuario).
///
/// Nunca se almacena la contraseña en texto plano: cada cuenta guarda un salt
/// aleatorio (16 bytes) y el hash `sha256('$salt:$password')`. La verificación
/// se hace en tiempo constante para mitigar ataques de timing.
class PasswordHasher {
  PasswordHasher._();

  static final Random _random = Random.secure();

  /// Genera un salt aleatorio de 16 bytes codificado en hexadecimal
  /// (32 caracteres).
  static String generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Calcula el hash de [password] con el [salt] dado.
  static String hash(String password, String salt) {
    final input = utf8.encode('$salt:$password');
    return sha256.convert(input).toString();
  }

  /// Verifica [password] contra [expectedHash] comparando en tiempo constante
  /// (sin cortocircuito por carácter, para no filtrar información por timing).
  static bool verify(String password, String salt, String expectedHash) {
    final actual = hash(password, salt);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}
