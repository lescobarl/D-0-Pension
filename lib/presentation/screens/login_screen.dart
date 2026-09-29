import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/account/pending_registration.dart';
import '../../services/account/user_account_service.dart';
import '../../services/account/validation_privileges_service.dart';
import '../../services/billing/payment_provider.dart';

/// Pantalla de login/registro del flujo de entrada.
///
/// - **Login**: primero busca la cuenta local ([UserAccountService]); si no
///   existe, solo cuando el usuario coincide con la cuenta de validación
///   integrada ([ValidationPrivilegesService]) se concede acceso libre.
/// - **Registro**: captura credenciales y navega a `/payment` con un
///   [PendingRegistration] (checkout diferido: la cuenta se materializa solo
///   después de una compra verificada).
enum _AuthMode { login, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmController;
  _AuthMode _mode = _AuthMode.login;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _rememberMe = true;

  bool get _isRegister => _mode == _AuthMode.register;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _mode = _isRegister ? _AuthMode.login : _AuthMode.register;
      _confirmController.clear();
    });
  }

  Future<void> _onSubmit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);
    if (_isRegister) {
      await _submitRegister();
    } else {
      await _submitLogin();
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  Future<void> _submitLogin() async {
    final accounts = context.read<UserAccountService>();
    final privileges = context.read<ValidationPrivilegesService>();
    final payments = context.read<PaymentProvider>();

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // 1) Cuenta local (flujo normal).
    final result = await accounts.loginUser(
      username,
      password,
      rememberMe: _rememberMe,
    );
    if (result == AccountLoginResult.ok) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }

    // 2) Único fallback: acceso libre solo para la cuenta de validación.
    if (privileges.matchesPrivilegedUsername(username)) {
      final granted = await payments.grantValidatorAccess(username, password);
      if (!mounted) return;
      if (granted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Usuario o contraseña incorrectos.')),
    );
  }

  Future<void> _submitRegister() async {
    final pending = PendingRegistration.create(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    // Checkout diferido: la cuenta se materializa solo tras la compra.
    Navigator.of(context).pushNamed('/payment', arguments: pending);
  }

  String? _validateUsername(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu usuario';
    if (_isRegister && v.length < 3) {
      return 'El usuario debe tener al menos 3 caracteres';
    }
    if (_isRegister) {
      final accounts = context.read<UserAccountService>();
      if (accounts.usernameExists(v)) {
        return 'Este usuario ya está registrado';
      }
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Ingresa tu contraseña';
    if (_isRegister && v.length < 4) {
      return 'La contraseña debe tener al menos 4 caracteres';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (!_isRegister) return null;
    if (value != _passwordController.text) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primaryDark,
              AppTheme.primary,
              AppTheme.primaryLight,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingXl,
                vertical: AppTheme.spacingLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App branding (logo oficial de la app)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/icons/app_icon_512.png',
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingLg),
                  Text(
                    'Calculadora Pensión Ley 73 IA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(
                    _isRegister
                        ? 'Crea tu cuenta y obtén tu licencia'
                        : 'Inicia sesión para acceder a tu calculadora',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: AppTheme.fontSizeBody,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingXl),

                  // Auth card
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.all(AppTheme.spacingXl),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isRegister ? 'Crear tu cuenta' : 'Iniciar sesión',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: AppTheme.fontSizeSectionTitle,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingLg),
                          TextFormField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Usuario',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: _validateUsername,
                          ),
                          const SizedBox(height: AppTheme.spacingLg),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: _isRegister
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onFieldSubmitted: _isRegister
                                ? null
                                : (_) => _onSubmit(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: _validatePassword,
                          ),
                          if (_isRegister) ...[
                            const SizedBox(height: AppTheme.spacingLg),
                            TextFormField(
                              controller: _confirmController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Confirmar contraseña',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: _validateConfirm,
                            ),
                          ],
                          const SizedBox(height: AppTheme.spacingMd),
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: _isSubmitting
                                    ? null
                                    : (v) => setState(
                                        () => _rememberMe = v ?? true,
                                      ),
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text(
                                  'Recordarme en este dispositivo',
                                  style: TextStyle(
                                    fontSize: AppTheme.fontSizeLabel,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacingSm),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _onSubmit,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isRegister ? 'Crear cuenta' : 'Acceder',
                                  ),
                          ),
                          const SizedBox(height: AppTheme.spacingSm),
                          TextButton(
                            onPressed: _isSubmitting ? null : _toggleMode,
                            child: Text(
                              _isRegister
                                  ? '¿Ya tienes cuenta? Inicia sesión'
                                  : '¿No tienes cuenta? Regístrate',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
