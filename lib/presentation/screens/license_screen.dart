import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/account/user_account_service.dart';
import '../../services/billing/license_service.dart';
import '../../services/billing/payment_provider.dart';

/// License status display screen.
///
/// Ported from machote's `LicenseScreen` (~243 lines).
/// Adaptations:
///   - Uses [AppTheme] instead of `FamilyTheme`
///   - Uses [PaymentProvider] instead of BLoC
///   - Uses default Material fonts instead of `GoogleFonts.nunito()`
///   - Es consciente de la sesión: muestra la cuenta activa y permite cerrar
///     sesión (regla: no se entra sin pagar o sin usuario).
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);

    final accounts = context.read<UserAccountService>();
    final payments = context.read<PaymentProvider>();
    await accounts.logoutUser();
    await payments.logout();

    if (!mounted) return;
    setState(() => _loggingOut = false);
    // El entry point resuelve el destino (vuelve a login).
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PaymentProvider>(
      builder: (context, provider, _) {
        final accounts = context.watch<UserAccountService>();
        final expiry = provider.licenseExpiry;
        final isExpired = LicenseService.isLicenseExpired(expiry);
        final daysLeft = LicenseService.daysRemaining(expiry);
        final status = LicenseService.licenseStatus(expiry);
        final isPerpetual = expiry == null && provider.hasEverPurchased;
        final hasNoLicense = !provider.hasEverPurchased;
        final canPop = Navigator.of(context).canPop();
        final sessionUsername =
            accounts.currentSessionUsername ?? provider.loginUsername;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mi Licencia'),
            // Cuando la pantalla se muestra como ruta raíz (desde el entry
            // point) no hay nada a lo que regresar: se omite la flecha.
            leading: canPop
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : null,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Sesión activa
                if (sessionUsername != null) ...[
                  _buildSessionCard(context, sessionUsername),
                  const SizedBox(height: 24),
                ],

                // License icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: isExpired
                        ? AppTheme.errorColor.withValues(alpha: 0.1)
                        : AppTheme.successColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isExpired ? Icons.lock_outline : Icons.verified_user,
                    size: 48,
                    color: isExpired
                        ? AppTheme.errorColor
                        : AppTheme.successColor,
                  ),
                ),
                const SizedBox(height: 24),

                // Status title
                Text(
                  hasNoLicense
                      ? 'Sin Licencia'
                      : isPerpetual
                      ? 'Licencia Vitalicia'
                      : isExpired
                      ? 'Licencia Expirada'
                      : 'Licencia Activa',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isExpired
                        ? AppTheme.errorColor
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),

                // Status description
                Text(
                  status,
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 32),

                // License info card
                if (provider.hasEverPurchased)
                  _buildLicenseInfoCard(provider, isPerpetual, daysLeft),

                const SizedBox(height: 32),

                // Action buttons
                if (isExpired) _buildRenewButton(context),
                if (!isExpired && !isPerpetual) _buildValidLicenseInfo(),
                if (!provider.hasEverPurchased) _buildNoLicenseInfo(context),

                if (provider.hasValidLicense) ...[
                  const SizedBox(height: 16),

                  // Back to calculator (solo con licencia vigente).
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        // El entry point resuelve el destino (home).
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/', (route) => false);
                      },
                      child: const Text('Ir a la Calculadora'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionCard(BuildContext context, String username) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primary,
              child: Icon(Icons.person, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cuenta',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    username,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _loggingOut ? null : _logout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout, size: 18),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseInfoCard(
    PaymentProvider provider,
    bool isPerpetual,
    int? daysLeft,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalles de la Licencia',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const Divider(),
            _infoRow('Producto', provider.licenseProductId ?? 'N/A'),
            _infoRow('Tipo', isPerpetual ? 'Vitalicia' : 'Suscripción'),
            if (!isPerpetual && provider.licenseExpiry != null)
              _infoRow(
                'Vigencia',
                '${provider.licenseExpiry!.day}/${provider.licenseExpiry!.month}/${provider.licenseExpiry!.year}',
              ),
            if (daysLeft != null) _infoRow('Días restantes', '$daysLeft'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRenewButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: () {
          // pushNamed para que "volver" regrese a la pantalla de licencia.
          Navigator.of(context).pushNamed('/payment');
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
        ),
        child: const Text(
          'Renovar Licencia',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildValidLicenseInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tu licencia está vigente. Disfruta de todas las funcionalidades.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoLicenseInfo(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppTheme.warningColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No tienes una licencia activa. Adquiere una para acceder a todas las funcionalidades.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  // pushNamed para que "volver" regrese a la pantalla de
                  // licencia.
                  Navigator.of(context).pushNamed('/payment');
                },
                child: const Text('Ver Planes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
