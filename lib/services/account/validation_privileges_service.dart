import '../../core/models/app_metadata.dart';

/// Controla la ÚNICA excepción de acceso libre: la cuenta de validación
/// integrada (p. ej. `lescobar69`) definida en `app_metadata.json`.
///
/// El resto de la app NO tiene acceso privilegiado: los usuarios normales
/// deben seguir el flujo completo (registrarse + pagar).
class ValidationPrivilegesService {
  final BuiltinAccountConfig? _config;

  const ValidationPrivilegesService([this._config]);

  /// Hay una cuenta de validación habilitada en la configuración.
  bool get isConfigured => _config?.enabled ?? false;

  /// Usuario privilegiado configurado (o `null` si no hay).
  String? get privilegedUsername => isConfigured ? _config!.username : null;

  /// Solo compara el nombre de usuario (trim + case-insensitive).
  bool matchesPrivilegedUsername(String username) =>
      isConfigured && _config!.matchesUsername(username);

  /// Valida usuario Y contraseña de la cuenta privilegiada.
  bool isPrivilegedValidator(String username, String password) =>
      isConfigured && _config!.matches(username, password);
}
