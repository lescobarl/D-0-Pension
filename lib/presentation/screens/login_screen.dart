import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../services/billing/login_provider.dart';

/// Login screen — user enters email + password before continuing.
///
/// Visually consistent with [AppTheme] (Verde Petroleo + Dorado).
/// Validates locally for now; production should integrate with a real
/// auth backend (Firebase, OAuth, etc.).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill email if previously saved
    final savedEmail = context.read<LoginProvider>().userEmail;
    if (savedEmail != null) {
      _emailCtrl.text = savedEmail;
    } else {
      // Default credentials for quick access
      _emailCtrl.text = 'demo@example.com';
      _passwordCtrl.text = '1234';
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<LoginProvider>();
    final ok = await provider.signIn(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      // On success, go to the next step (payment or home)
      Navigator.of(context).pushReplacementNamed('/payment');
    }
  }

  void _onSkip() {
    // Allow user to skip login (demo mode) — they can use the app
    // without authentication. In production this would be removed.
    Navigator.of(context).pushReplacementNamed('/payment');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Consumer<LoginProvider>(
                builder: (context, provider, _) {
                  return Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header icon
                        Container(
                          width: 64,
                          height: 64,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.calculate_rounded,
                            size: 32,
                            color: AppTheme.accent,
                          ),
                        ),
                        Text(
                          'Iniciar Sesión',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeSectionTitle,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ingresa tus credenciales para continuar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeBodySmall,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Email field
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enabled: !provider.isLoading,
                          decoration: InputDecoration(
                            labelText: 'Correo electrónico',
                            hintText: 'tu@correo.com',
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Ingresa tu correo';
                            }
                            if (!v.contains('@')) {
                              return 'Correo inválido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Password field
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          enabled: !provider.isLoading,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            hintText: '••••••••',
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppTheme.textSecondary,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Ingresa tu contraseña';
                            }
                            if (v.length < 4) {
                              return 'Mínimo 4 caracteres';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _onLogin(),
                        ),
                        const SizedBox(height: 12),

                        // Error message
                        if (provider.errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.errorColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.errorColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: AppTheme.errorColor,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    provider.errorMessage!,
                                    style: TextStyle(
                                      color: AppTheme.errorColor,
                                      fontSize: AppTheme.fontSizeBodySmall,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // Login button
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: provider.isLoading ? null : _onLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 1,
                            ),
                            child: provider.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Iniciar Sesión',
                                    style: TextStyle(
                                      fontSize: AppTheme.fontSizeBody,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Skip link
                        TextButton(
                          onPressed: provider.isLoading ? null : _onSkip,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Continuar sin cuenta',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: AppTheme.fontSizeBodySmall,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Info note
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppTheme.accentDark,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Modo demo: cualquier correo y contraseña '
                                  '(mín. 4 caracteres) es válida.',
                                  style: TextStyle(
                                    fontSize: AppTheme.fontSizeTableData,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
