import '../utils/password_hasher.dart';

/// Cuenta local de usuario.
///
/// Guarda el hash de la contraseña (nunca en claro, ver [PasswordHasher]) y,
/// cuando existe, la licencia asociada a la cuenta. La licencia se sincroniza
/// con el dispositivo ([PaymentProvider]) para que `hasValidLicense` y el
/// flujo de entrada funcionen de forma consistente.
class UserProfile {
  final String id;
  final String username;
  final String salt;
  final String passwordHash;
  final String? email;

  /// Vencimiento de la licencia. `null` + [purchasedProductId] no nulo =
  /// licencia vitalicia (perpetua).
  final DateTime? licenseExpiry;
  final String? purchasedProductId;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    required this.salt,
    required this.passwordHash,
    this.email,
    this.licenseExpiry,
    this.purchasedProductId,
    required this.createdAt,
  });

  /// La licencia de la cuenta es válida si existe producto comprado y, en caso
  /// de tener vencimiento, aún no ha expirado.
  bool get isLicenseValid {
    if (purchasedProductId == null) return false;
    final expiry = licenseExpiry;
    if (expiry == null) return true; // perpetua
    return DateTime.now().isBefore(expiry);
  }

  /// Verifica la contraseña contra el hash almacenado.
  bool verifyPassword(String password) =>
      PasswordHasher.verify(password, salt, passwordHash);

  UserProfile copyWith({
    String? id,
    String? username,
    String? salt,
    String? passwordHash,
    String? email,
    DateTime? licenseExpiry,
    bool clearLicenseExpiry = false,
    String? purchasedProductId,
    bool clearPurchasedProductId = false,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      salt: salt ?? this.salt,
      passwordHash: passwordHash ?? this.passwordHash,
      email: email ?? this.email,
      licenseExpiry: clearLicenseExpiry
          ? null
          : (licenseExpiry ?? this.licenseExpiry),
      purchasedProductId: clearPurchasedProductId
          ? null
          : (purchasedProductId ?? this.purchasedProductId),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'salt': salt,
    'passwordHash': passwordHash,
    'email': email,
    'licenseExpiry': licenseExpiry?.toIso8601String(),
    'purchasedProductId': purchasedProductId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      salt: json['salt'] as String,
      passwordHash: json['passwordHash'] as String,
      email: json['email'] as String?,
      licenseExpiry: json['licenseExpiry'] == null
          ? null
          : DateTime.tryParse(json['licenseExpiry'] as String),
      purchasedProductId: json['purchasedProductId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
