import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../services/retroactive_provider.dart';
import 'captura_view.dart';
import 'pension_view.dart';
import 'inversion_view.dart';
import 'ai_chat_view.dart';
import '../widgets/disclaimer_card.dart';

/// TabBar screen with 4 main groups + AI assistant.
///
/// Tabs:
/// - CAPTURA: Unified data entry (personal + laboral + Mod40)
/// - PENSIÓN: Pension results (actual vs Mod40 + FactAsig details)
/// - INVERSIÓN: Investment analysis (costo, retroactivo, financiamiento, tasas)
/// - IA EXPERTA: Conversational AI assistant that fills the calculator fields.
///
/// The AI assistant is a 4th tab (not a pushed route) so switching to it and
/// back never requires the system back button and preserves the conversation.
class HomeTabsScreen extends StatefulWidget {
  const HomeTabsScreen({super.key});

  @override
  State<HomeTabsScreen> createState() => _HomeTabsScreenState();
}

class _HomeTabsScreenState extends State<HomeTabsScreen> {
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                child: const Icon(Icons.account_balance, size: 16, color: AppTheme.accent),
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
            IconButton(
              tooltip: 'Descargo de Responsabilidad',
              onPressed: () => DisclaimerCard.show(context),
              icon: const Icon(Icons.info_outline, size: 20),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(32),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: SizedBox(
                height: 32,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorWeight: 2.0,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note, size: 16),
                          SizedBox(width: 4),
                          Text('Captura', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.elderly, size: 16),
                          SizedBox(width: 4),
                          Text('Pensión', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up, size: 16),
                          SizedBox(width: 4),
                          Text('Inversión', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 16),
                          SizedBox(width: 4),
                          Text('IA Experta', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
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
            final double initialTop = constraints.maxHeight - fabHeight - margin;

            return Stack(
              children: [
                TabBarView(
                  children: [
                    const CapturaView(),
                    const PensionView(),
                    const InversionView(),
                    const AiChatView(),
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
                        backgroundColor: AppTheme.accentLight.withValues(alpha: 0.35),
                        foregroundColor: AppTheme.accentDark,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: AppTheme.accent.withValues(alpha: 0.6),
                          ),
                        ),
                        onPressed: () {
                          DefaultTabController.of(fabContext).animateTo(3);
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
