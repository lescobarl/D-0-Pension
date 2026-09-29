import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../services/account/user_account_service.dart';
import '../../services/billing/payment_provider.dart';
import '../../services/retroactive_provider.dart';
import 'captura_view.dart';
import 'pension_view.dart';
import 'inversion_view.dart';
import 'ai_chat_view.dart';
import '../widgets/disclaimer_card.dart';

/// TabBar screen with 4 main groups + AI assistant.
///
/// Tabs (IA Experta en primera posición: para personas mayores es el acceso
/// más amigable, conversan y la IA captura en vez de llenar formularios):
/// - IA EXPERTA: Asistente conversacional que llena los campos de la calculadora.
/// - CAPTURA: Captura de datos (personal + laboral + Mod40)
/// - PENSIÓN: Resultados de pensión (actual vs Mod40 + detalle de FactAsig)
/// - INVERSIÓN: Análisis de inversión (costo, retroactivo, financiamiento, tasas)
///
/// El asistente de IA es una pestaña (no una ruta empujada) para que entrar y
/// volver nunca requiera el botón de regreso del sistema y preserve la conversación.
/// El TabBar NO es desplazable: las 4 pestañas se reparten el ancho y siempre
/// están visibles, evitando que se "pierdan" en pantallas de teléfono.
class HomeTabsScreen extends StatefulWidget {
  const HomeTabsScreen({super.key});

  @override
  State<HomeTabsScreen> createState() => _HomeTabsScreenState();
}

class _HomeTabsScreenState extends State<HomeTabsScreen> {
  /// Muestra el descargo de responsabilidad una sola vez, en el primer uso.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final paymentProvider = context.read<PaymentProvider>();
      if (!paymentProvider.isDisclaimerSeen) {
        paymentProvider.markDisclaimerSeen();
        DisclaimerCard.show(context);
      }
    });
  }

  /// `true` mientras se está cerrando la sesión (desactiva el botón).
  bool _loggingOut = false;

  /// Pide confirmación antes de cerrar sesión para evitar salidas accidentales.
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Deseas cerrar la sesión y salir de la calculadora?\n'
          'Podrás volver a entrar cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _logout();
  }

  /// Cierra la sesión (cuenta + licencia de dispositivo) y deja que el entry
  /// point vuelva a la pantalla de login. Reutiliza el mismo patrón de la
  /// pantalla de licencia: `logoutUser()` + `logout()`.
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

  /// Construye una pestaña compacta (icono + etiqueta) que se adapta al ancho
  /// disponible. FittedBox (scaleDown) evita desbordes en teléfonos angostos:
  /// la etiqueta se reduce un poco en lugar de cortarse o perderse.
  static Widget _buildTab(IconData icon, String label) {
    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // Position of the draggable IA Experta button (relative to the body area).
  // Stored as an Offset so the user can move it anywhere on screen.
  Offset _fabPosition = const Offset(0, 0);

  // Whether the user has dragged the button. Before the first drag, the button
  // is anchored to the bottom-right corner; after dragging, it stays where the
  // user left it.
  bool _hasDraggedFab = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RetroactiveProvider>();

    // Show loading indicator while evaluator initializes
    if (!provider.evaluator.isInitialized || provider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (provider.errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              provider.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 44,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.account_balance,
                  size: 16,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  provider.evaluator.metadata.appName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            Tooltip(
              message: 'Acerca de',
              child: TextButton.icon(
                onPressed: () => DisclaimerCard.show(context),
                icon: const Icon(Icons.info_outline, size: 20),
                label: const Text('Acerca de'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ),
            TextButton.icon(
              onPressed: _loggingOut ? null : _confirmLogout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout, size: 18),
              label: const Text('Salir'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(32),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: SizedBox(
                height: 32,
                child: TabBar(
                  // NO desplazable: las 4 pestañas se reparten el ancho y
                  // siempre están visibles (no se "pierden" en el teléfono).
                  isScrollable: false,
                  tabAlignment: TabAlignment.fill,
                  indicatorWeight: 2.0,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  tabs: [
                    _buildTab(Icons.auto_awesome, 'IA Experta'),
                    _buildTab(Icons.edit_note, 'Captura'),
                    _buildTab(Icons.elderly, 'Pensión'),
                    _buildTab(Icons.trending_up, 'Inversión'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Button size (approx). Used to anchor it to the bottom-right.
            const double fabWidth = 130;
            const double fabHeight = 48;
            final double margin = 16;

            // Initial bottom-right position (before the user drags).
            final double initialLeft = constraints.maxWidth - fabWidth - margin;
            final double initialTop =
                constraints.maxHeight - fabHeight - margin;

            return Stack(
              children: [
                TabBarView(
                  children: [
                    const AiChatView(),
                    const CapturaView(),
                    const PensionView(),
                    const InversionView(),
                  ],
                ),
                // Draggable IA Experta button. Starts at the bottom-right
                // corner; the user can drag it anywhere on screen. Tapping it
                // still switches to the IA Experta tab.
                Positioned(
                  left: _hasDraggedFab ? _fabPosition.dx : initialLeft,
                  top: _hasDraggedFab ? _fabPosition.dy : initialTop,
                  child: Builder(
                    builder: (fabContext) => GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _hasDraggedFab = true;
                          _fabPosition += details.delta;
                        });
                      },
                      child: FloatingActionButton.extended(
                        backgroundColor: AppTheme.accentLight.withValues(
                          alpha: 0.35,
                        ),
                        foregroundColor: AppTheme.accentDark,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: AppTheme.accent.withValues(alpha: 0.6),
                          ),
                        ),
                        onPressed: () {
                          DefaultTabController.of(fabContext).animateTo(0);
                        },
                        tooltip: 'Preguntar a la IA Experta',
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        label: const Text(
                          'IA Experta',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
