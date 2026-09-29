import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/result.dart';
import '../../core/theme/app_theme.dart';
import '../../services/account/pending_registration.dart';
import '../../services/account/registration_checkout.dart';
import '../../services/account/user_account_service.dart';
import '../../services/billing/payment_provider.dart';
import '../../services/billing/play_billing_service.dart';
import '../../services/billing/play_purchase_success.dart';

/// Plan selection and checkout screen.
///
/// Ported from machote's `PaymentScreen` (~560 lines).
/// Adaptations:
///   - Uses [AppTheme] instead of `FamilyTheme`
///   - Uses [PaymentProvider] instead of BLoC
///   - Uses default Material fonts instead of `GoogleFonts.nunito()`
///   - Deferred checkout: la cuenta se materializa solo después de una compra
///     verificada (ver [pendingRegistration]).
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, this.pendingRegistration});

  /// Registro pendiente de un usuario nuevo (flujo A: onboarding → registro →
  /// pago). Si es `null`, la compra se aplica a la sesión activa (renovación,
  /// flujo C) o a nivel dispositivo (invitado / recuperación, flujo E).
  final PendingRegistration? pendingRegistration;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selectedPlan = kProductIdSemestral;

  @override
  void initState() {
    super.initState();
    // Corrección de raíz del ciclo de recuperación: al montar /payment se
    // limpia cualquier estado transitorio heredado (p. ej. el error de un
    // restore fallido previo) para que SIEMPRE se muestre la selección de plan
    // y nunca un error fantasma ('No hay suscripción activa' / 'Error de
    // conexión') aunque el provider ya esté inicializado desde el arranque.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PaymentProvider>();
      provider.resetTransientState();
      if (!provider.isInitialized) {
        provider.initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PaymentProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Obtén tu Licencia'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: _buildBody(provider),
        );
      },
    );
  }

  Widget _buildBody(PaymentProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Procesando...'),
          ],
        ),
      );
    }

    if (provider.state == PaymentState.success) {
      return _buildSuccessScreen(provider);
    }

    if (provider.state == PaymentState.error) {
      return _buildErrorScreen(provider);
    }

    return _buildPlanSelection(provider);
  }

  Widget _buildPlanSelection(PaymentProvider provider) {
    final canLinkPendingLicense =
        widget.pendingRegistration != null && provider.hasValidLicense;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const SizedBox(height: 8),
          Text(
            'Elige tu plan',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
              children: [
                const TextSpan(text: 'Accede a todas las funcionalidades de: '),
                const TextSpan(
                  text: 'Calculadora pensión Ley 73 IMSS',
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Único plan: Suscripción Semestral
          _buildPlanCard(
            title: 'Suscripción Semestral',
            price: '\$599',
            period: '/6 meses',
            description:
                'La manera exacta de asegurar tu futuro y el de tu familia',
            highlightedFeatures: [
              'Tu asesor personalizado, con Inteligencia Artificial',
              'Crea tus propios escenarios de pensión',
              'Captura simplificada, sin tantos rollos',
            ],
            features: [
              'Cálculos precisos Ley 73 IMSS',
              'Modalidad 40 y Pago Retroactivo',
              'Proyecciones de pensión',
              'Soporte prioritario',
            ],
            productId: kProductIdSemestral,
            isPopular: true,
            onTap: () => setState(() => _selectedPlan = kProductIdSemestral),
          ),
          const SizedBox(height: 12),

          // Security info
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Pago seguro procesado por Google Play',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Buy button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () => _onPurchase(provider),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: Text(
                'Comprar Suscripción Semestral',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Restore link
          Center(
            child: TextButton(
              onPressed: provider.isLoading ? null : () => _onRestore(provider),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
              child: const Text(
                'Recuperar acceso',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),

          // Al registrarse con una licencia de dispositivo YA vigente, se
          // permite vincularla a la nueva cuenta sin volver a pagar.
          if (canLinkPendingLicense) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _linkPendingLicense(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Vincular licencia a mi cuenta'),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required String period,
    required String description,
    required List<String> features,
    List<String> highlightedFeatures = const [],
    required String productId,
    required bool isPopular,
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedPlan == productId;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and price row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (isPopular)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Popular',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        price,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        period,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Features: all unified (star, gold, bold, dark text)
                  ...[...highlightedFeatures, ...features].map((feature) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessScreen(PaymentProvider provider) {
    final accounts = context.read<UserAccountService>();
    final sessionUser = accounts.currentUser;
    final hasSession = sessionUser != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: AppTheme.successColor,
            ),
            const SizedBox(height: 24),
            const Text(
              '¡Licencia Activada!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSession
                  ? 'Ya puedes acceder a todas las funcionalidades de la '
                        'calculadora, ${sessionUser.username}.'
                  : 'Ya puedes acceder a todas las funcionalidades de la '
                        'calculadora.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  // El entry point resuelve el destino según sesión/licencia.
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/', (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Ir a la Calculadora',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (!hasSession) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Compra como invitado: al iniciar sesión se vincula la
                    // licencia del dispositivo a la cuenta.
                    Navigator.of(context).pushNamed('/login');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Vincular a mi cuenta'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(PaymentProvider provider) {
    // Caso distinto a un simple fallo de conexión: la cuenta de Google actual
    // no tiene una suscripción ACTIVA y PAGADA. Mostramos una vista dedicada
    // con la explicación y el camino accionable, para no dejar al usuario en el
    // ciclo "Recuperar acceso → no hay cuenta → Error de conexión".
    if (provider.isNoActiveSubscriptionError) {
      return _buildNoActiveSubscriptionView(provider);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 80,
                color: AppTheme.errorColor,
              ),
              const SizedBox(height: 24),
              Text(
                provider.isBillingUnavailableError
                    ? 'Compra no disponible'
                    : 'Error de conexión',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                provider.userFriendlyError ?? 'Ocurrió un error desconocido.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    provider.resetState();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Intentar de nuevo'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  provider.resetState();
                },
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Vista dedicada al error "no hay suscripción activa".
  ///
  /// Explica el porqué (suscripción comprada con otra cuenta de Google, venció
  /// y no se renovó, o fue cancelada) y ofrece el camino accionable: comprar de
  /// nuevo la suscripción semestral. `_executePurchase` reinicia el estado
  /// internamente, por lo que llamar a [_onPurchase] desde aquí es seguro.
  Widget _buildNoActiveSubscriptionView(PaymentProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.subscriptions_outlined,
                size: 80,
                color: AppTheme.warningColor,
              ),
              const SizedBox(height: 24),
              Text(
                'No hay suscripción activa',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'En esta cuenta de Google no hay una suscripción vigente.\n\n'
                'Esto puede pasar si la compraste con otra cuenta de Google, si '
                'venció y no se renovó, o si se canceló.\n\n'
                'Para volver a usar la app, compra la suscripción semestral. Si '
                'crees que ya pagaste, verifica que estés usando la misma cuenta '
                'de Google con la que hiciste la compra.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => _onPurchase(provider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Comprar Suscripción Semestral'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  provider.resetState();
                },
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------------

  Future<void> _onPurchase(PaymentProvider provider) async {
    final result = await provider.purchaseSemestral();
    await _handleVerifiedPurchase(result);
  }

  Future<void> _onRestore(PaymentProvider provider) async {
    final result = await provider.restorePurchase();
    await _handleVerifiedPurchase(result);
  }

  /// Vincula una licencia de dispositivo YA vigente al registro pendiente
  /// (flujo "Vincular licencia a mi cuenta") sin volver a cobrar.
  Future<void> _linkPendingLicense() async {
    final pending = widget.pendingRegistration;
    if (pending == null) return;

    final checkout = context.read<RegistrationCheckout>();
    final ok = await checkout.linkToExistingLicense(pending: pending);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo vincular la licencia. Intenta de nuevo.'),
        ),
      );
    }
  }

  /// Cierra el checkout diferido: solo con una compra VERIFICADA se materializa
  /// la cuenta (flujo A) o se actualiza la licencia de la sesión (flujo C).
  Future<void> _handleVerifiedPurchase(
    Result<PlayPurchaseSuccess> result,
  ) async {
    final purchase = result.valueOrNull;
    if (purchase == null) return; // Error ya reflejado por el provider.
    if (!mounted) return;

    final accounts = context.read<UserAccountService>();
    final checkout = context.read<RegistrationCheckout>();

    // Flujo A: usuario nuevo que se registró y llega a pagar.
    if (widget.pendingRegistration != null) {
      final ok = await checkout.completeCheckoutAfterVerifiedPurchase(
        pending: widget.pendingRegistration!,
        purchase: purchase,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo crear tu cuenta. Intenta de nuevo.'),
          ),
        );
      }
      return;
    }

    // Flujo C / renovación con sesión activa: vincula/actualiza la licencia
    // de la cuenta con la compra recién verificada.
    final sessionUser = accounts.currentUser;
    if (sessionUser != null) {
      await checkout.linkToExistingLicense(user: sessionUser);
    }
    // Invitado (flujo E): la licencia queda a nivel dispositivo; la pantalla
    // de éxito ofrece "Vincular a mi cuenta".
  }
}
