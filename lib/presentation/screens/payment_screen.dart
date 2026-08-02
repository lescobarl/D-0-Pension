import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../services/billing/payment_provider.dart';
import '../../services/billing/play_billing_service.dart';

/// Plan selection and checkout screen.
///
/// Ported from machote's `PaymentScreen` (~560 lines).
/// Adaptations:
///   - Uses [AppTheme] instead of `FamilyTheme`
///   - Uses [PaymentProvider] instead of BLoC
///   - Uses default Material fonts instead of `GoogleFonts.nunito()`
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selectedPlan = kProductIdAnnual;

  @override
  void initState() {
    super.initState();
    // Initialize billing if not already done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PaymentProvider>();
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
          Text(
            'Accede a todas las funcionalidades de la calculadora',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          // Annual plan card
          _buildPlanCard(
            title: 'Suscripción Anual',
            price: '\$199',
            period: '/año',
            description: 'Acceso completo por 1 año',
            features: [
              'Cálculos precisos Ley 73 IMSS',
              'Modalidad 40 y Pago Retroactivo',
              'Proyecciones de pensión',
              'Soporte prioritario',
            ],
            productId: kProductIdAnnual,
            isPopular: true,
            onTap: () => setState(() => _selectedPlan = kProductIdAnnual),
          ),
          const SizedBox(height: 16),

          // Perpetual plan card
          _buildPlanCard(
            title: 'Licencia Vitalicia',
            price: '\$499',
            period: 'único pago',
            description: 'Acceso de por vida',
            features: [
              'Todo lo del plan anual',
              'Sin renovaciones',
              'Actualizaciones gratuitas',
              'Soporte VIP',
            ],
            productId: kProductIdPerpetual,
            isPopular: false,
            onTap: () => setState(() => _selectedPlan = kProductIdPerpetual),
          ),
          const SizedBox(height: 24),

          // Security info
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 16, color: AppTheme.textHint),
              const SizedBox(width: 6),
              Text(
                'Pago seguro procesado por Google Play',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Buy button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _onPurchase(provider),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: Text(
                _selectedPlan == kProductIdAnnual
                    ? 'Comprar Suscripción Anual - \$199'
                    : 'Comprar Licencia Vitalicia - \$499',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Restore link
          Center(
            child: TextButton(
              onPressed: () => _onRestore(provider),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
              ),
              child: const Text(
                '¿Ya tienes una licencia? Restaurar compra',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 32),
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
              padding: const EdgeInsets.all(20),
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
                  const SizedBox(height: 8),

                  // Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        price,
                        style: TextStyle(
                          fontSize: 32,
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
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Features
                  ...features.map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: AppTheme.successColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            feature,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Radio indicator
            Positioned(
              top: 20,
              right: 20,
              child: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected ? AppTheme.primary : AppTheme.textHint,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessScreen(PaymentProvider provider) {
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
              'Ya puedes acceder a todas las funcionalidades de la calculadora.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/home',
                    (route) => false,
                  );
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(PaymentProvider provider) {
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
              const Text(
                'Error de conexión',
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
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () async {
                    // Capture navigator before async gap to avoid
                    // use_build_context_synchronously warnings.
                    final navigator = Navigator.of(context);
                    await provider.enableDemoMode();
                    navigator.pushNamedAndRemoveUntil(
                      '/home',
                      (route) => false,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Continuar en modo demo'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  provider.resetState();
                },
                child: const Text('Volver'),
              ),
              const SizedBox(height: 16),
              // Info card about demo mode
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.warningColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El modo demo te permite explorar la aplicación '
                        'sin necesidad de una licencia. Algunas funciones '
                        'avanzadas podrían no estar disponibles.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
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
    if (_selectedPlan == kProductIdAnnual) {
      await provider.purchaseAnnual();
    } else {
      await provider.purchasePerpetual();
    }
  }

  Future<void> _onRestore(PaymentProvider provider) async {
    await provider.restorePurchase();
  }
}
