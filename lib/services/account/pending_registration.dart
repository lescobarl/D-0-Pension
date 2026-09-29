import '../../core/utils/password_hasher.dart';

/// Registro capturado en la pantalla de login ANTES del pago.
///
/// La cuenta NO se crea aquí: solo se materializa después de que una compra
/// verificada completa el checkout (checkout diferido). Almacena el hash de la
/// contraseña (nunca en claro) para transferirlo al [UserProfile] final.
class PendingRegistration {
  final String username;
  final String? email;
  final String salt;
  final String passwordHash;
  final DateTime createdAt;

  PendingRegistration._({
    required this.username,
    required this.email,
    required this.salt,
    required this.passwordHash,
    required this.createdAt,
  });

  /// Crea un registro pendiente a partir de credenciales en claro.
  factory PendingRegistration.create({
    required String username,
    required String password,
    String? email,
  }) {
    final trimmedUsername = username.trim();
    final trimmedEmail = email?.trim();
    final salt = PasswordHasher.generateSalt();
    return PendingRegistration._(
      username: trimmedUsername,
      email: (trimmedEmail == null || trimmedEmail.isEmpty)
          ? null
          : trimmedEmail,
      salt: salt,
      passwordHash: PasswordHasher.hash(password, salt),
      createdAt: DateTime.now(),
    );
  }

  /// Verifica la contraseña en claro contra el hash capturado.
  bool verifyPassword(String password) =>
      PasswordHasher.verify(password, salt, passwordHash);
}
