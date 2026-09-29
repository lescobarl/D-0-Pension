import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/ai/api_key_obfuscator.dart';
import '../../core/ai/fair_use_policy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_handler.dart';
import '../../services/ai_chat_service.dart';
import '../../services/retroactive_provider.dart';
import '../widgets/legal_note_card.dart';

/// AI Chat view for conversational pension scenario input.
///
/// Designed for elderly users with:
/// - Large fonts (18px+)
/// - High contrast colors
/// - Big touch targets (48px+)
/// - Simple, clear interface aligned with the rest of the app
///
/// The user describes their pension scenario in natural language,
/// and the AI extracts the data to fill the calculator fields.
class AiChatView extends StatefulWidget {
  const AiChatView({super.key});

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView>
    with AutomaticKeepAliveClientMixin {
  // Mantiene viva la conversación al cambiar de pestaña (TabBarView descarta
  // los hijos fuera de pantalla por defecto; con esto el chat no se pierde).
  @override
  bool get wantKeepAlive => true;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AiChatService _chatService;
  int _lastMessageCount = 0;
  bool _lastLoading = false;
  bool _initialized = false;
  // Flujo natural IA → Captura: recuerda si la captura ya estaba completa para
  // navegar a Captura UNA sola vez (en el flanco incompleto → completo).
  bool _captureWasComplete = false;

  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    // Never let a missing/corrupt key block the assistant UI.
    String key = '';
    try {
      final jsonStr = await rootBundle.loadString('assets/config/api_key.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final obfuscated = json['openrouter_api_key_obfuscated'] as String? ?? '';
      key = obfuscated.isEmpty ? '' : ApiKeyObfuscator.decode(obfuscated);
    } catch (_) {
      key = '';
    }
    _apiKey = key;
    _initChatService();
  }

  void _initChatService() {
    final provider = context.read<RetroactiveProvider>();
    _chatService = AiChatService(provider: provider, apiKey: _apiKey);
    _chatService.addListener(_onServiceChanged);
    _chatService
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() => _initialized = true);
            // Arranca desde el estado real de completitud (la sesión restaurada
            // puede venir ya completa y no debe re-saltar a Captura por error).
            _captureWasComplete = _chatService.isCaptureComplete;
            // Show the most recent messages (or the welcome card) on first load.
            _scrollToBottom();
          }
        })
        .catchError((Object e) {
          // Ensure the "Iniciando asistente..." screen is never left hanging.
          if (mounted) {
            setState(() => _initialized = true);
          }
        });
  }

  @override
  void dispose() {
    _chatService.removeListener(_onServiceChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      ErrorHandler.logDebug(
        'AiChatView - Rebuild triggered at ${DateTime.now().toIso8601String()}',
      );
      final count = _chatService.messages.length;
      final loading = _chatService.isLoading;
      // React to BOTH the message count and the loading state: the loading
      // flag flips right after the user sends a message (so their message and
      // the typing indicator appear immediately) and again when the response
      // arrives. Each change rebuilds and scrolls to the latest message.
      if (count != _lastMessageCount || loading != _lastLoading) {
        _lastMessageCount = count;
        _lastLoading = loading;
        setState(() {});
        _scrollToBottom();
      } else {
        ErrorHandler.logDebug(
          'Skipping rebuild - message count and loading unchanged',
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    await _sendText(_textController.text.trim());
  }

  /// Envía un texto concreto (del campo de entrada, de un chip de ejemplo o de
  /// una sugerencia de respuesta rápida) a [AiChatService.sendMessage].
  ///
  /// [guideField] lo aporta un chip de respuesta rápida: es el campo guiado al
  /// que pertenece el chip, para que el clic se aplique SIEMPRE a ese campo
  /// (aunque la guía ya haya avanzado a otra pregunta).
  Future<void> _sendText(String text, {String? guideField}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Se lee el proveedor ANTES del await: así no se usa el context después de
    // una brecha asíncrona (lint use_build_context_synchronously).
    final provider = context.read<RetroactiveProvider>();
    _textController.clear();
    final result = await _chatService.sendMessage(
      trimmed,
      guideField: guideField,
    );

    if (result is AiFillFields || result is AiError) {
      setState(() {});
    }

    _scrollToBottom();

    // ── Flujo natural IA → Captura ──
    // Cuando ya no falta ningún dato capturable, se avisa con un SnackBar y,
    // tras un breve retraso para que el usuario lea la confirmación, se cambia
    // a la pestaña Captura para revisar y guardar (solo en el flanco de
    // incompleto → completo; una sola vez por sesión).
    //
    // Regla A (Ley 73): aunque la captura esté completa, si hay errores
    // bloqueantes (p. ej. nacimiento o alta posteriores a 1997-07-01, régimen
    // de la Ley 1997) NO se permite avanzar: se avisa y se permanece en la IA
    // Experta para corregir los datos.
    final wasComplete = _captureWasComplete;
    final nowComplete = _chatService.isCaptureComplete;
    _captureWasComplete = nowComplete;
    if (nowComplete && !wasComplete && provider.hasBlockingErrors) {
      await _warnNoSePuedeAvanzar(provider);
    } else if (nowComplete && !wasComplete) {
      await _goToCapturaForReview();
    }
  }

  /// Flujo natural IA Experta → Captura: avisa que la captura quedó completa
  /// y, tras un breve retraso para que el adulto mayor lea el mensaje, cambia
  /// a la pestaña Captura para revisar y guardar sus datos.
  Future<void> _goToCapturaForReview() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '✅ ¡Captura completa! Revisa y guarda tus datos en la pestaña '
          'Captura.',
        ),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Retraso breve: da tiempo a leer la confirmación antes del cambio.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    // Cambio defensivo de pestaña: solo si existe un DefaultTabController
    // ancestro (DefaultTabController.of lanza si no hay); así no se rompen
    // los tests que montan la vista suelta sin el shell de pestañas.
    if (context.findAncestorWidgetOfExactType<DefaultTabController>() != null) {
      DefaultTabController.of(context).animateTo(1);
    }
  }

  /// No se puede avanzar a Captura: hay errores bloqueantes que impiden
  /// calcular la pensión (por ejemplo, la Ley 73 no aplica). Muestra un aviso
  /// claro para el adulto mayor y permanece en la IA Experta para corregir.
  Future<void> _warnNoSePuedeAvanzar(RetroactiveProvider provider) async {
    if (!mounted) return;
    final mensajeLey73 = provider.ley73BlockingMessage;
    final texto = mensajeLey73 != null
        ? '⚠️ $mensajeLey73 Por eso no puedo avanzar a la captura: '
              'corrige tus datos para continuar.'
        : '⚠️ Hay datos que impiden calcular tu pensión. '
              'Corrige los errores en la pestaña Captura para continuar.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startNewSession() async {
    await _chatService.startNewSession();
    setState(() {
      // El servicio limpia el conjunto de campos guiados: la captura vuelve a
      // estar incompleta y puede volver a completarse (y navegar) de nuevo.
      _captureWasComplete = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Desplaza la conversación una cantidad fija de píxeles (usado por las
  /// flechas del cursor). No hace nada si el scroll aún no tiene clientes.
  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  // ──────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // Requerido por AutomaticKeepAliveClientMixin.
    if (!_initialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Iniciando asistente...',
              style: TextStyle(fontSize: AppTheme.fontSizeBody),
            ),
          ],
        ),
      );
    }

    final messages = _chatService.messages;

    return Column(
      children: [
        // Encabezado fijo y compacto, pegado arriba (unificado con las demás
        // pestañas que usan padding superior de 2).
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          child: _buildHeader(),
        ),
        // Conversación con scroll propio: aprovecha todo el espacio y el área
        // de entrada (botón Enviar) permanece siempre visible abajo.
        Expanded(
          // Focus + onKeyEvent: permite desplazar la conversación con las
          // flechas del cursor (arriba/abajo) además del scroll táctil.
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.arrowDown) {
                _scrollBy(120);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowUp) {
                _scrollBy(-120);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              children: [
                if (messages.isEmpty)
                  _buildWelcomeCard()
                else
                  _buildConversationCard(messages),
              ],
            ),
          ),
        ),
        // Entrada fija al fondo: el botón "Enviar" nunca desaparece.
        _buildInputCard(),
        // Aviso legal fijo al fondo de la página, a lo ancho y en una sola línea.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: _buildLegalNoteCard(),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // Header (same pattern as other 6 views)
  // ──────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      // Compacto, unificado con el resto de subtítulos de las pestañas.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.smart_toy,
              color: AppTheme.accent,
              size: 14,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ASISTENTE DE PENSIÓN',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeCardTitle,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                // El botón comparte el renglón del subtítulo (sin fila extra),
                // para no engrosar el encabezado.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text(
                        'Platícame tu situación y yo lleno los datos de la calculadora.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeBodySmall,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    TextButton.icon(
                      onPressed: _startNewSession,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                      label: const Text('Limpiar conversación'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Welcome card (initial state, no messages yet)
  // ──────────────────────────────────────────────

  Widget _buildWelcomeCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Primera opción: inicia el llenado guiado paso a paso (mismo
            // estilo que el resto de las opciones).
            _buildExampleChip('Ayúdame a llenar mi cálculo de pensión'),
            const SizedBox(height: 6),
            const SelectableText(
              'Cuéntame en tus palabras tu caso. Por ejemplo:',
              style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildExampleChip(
              'Tengo 60 años, 1200 semanas cotizadas, salario de \$500',
            ),
            const SizedBox(height: 6),
            _buildExampleChip(
              'Estoy casado, tengo 2 hijos, mi salario diario es \$400',
            ),
            const SizedBox(height: 6),
            _buildExampleChip(
              'Quiero pensionarme a los 62 años con Modalidad 40',
            ),
            const SizedBox(height: 8),
            const SelectableText(
              'Si ya tienes un cálculo de otro lado, también puedes pegarlo '
              'abajo para compararlo con el resultado de la app.',
              style: TextStyle(
                fontSize: AppTheme.fontSizeBodySmall,
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleChip(String text) {
    return InkWell(
      // Los chips de ejemplo ENVÍAN directo el texto (antes solo lo dejaban en
      // el campo de entrada, obligando al usuario a pulsar Enviar). Así la app
      // guía con un solo toque.
      onTap: () {
        HapticFeedback.selectionClick();
        _sendText(text);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.backgroundLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 20,
              color: AppTheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward, size: 18, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Conversation card (messages list)
  // ──────────────────────────────────────────────

  Widget _buildConversationCard(List<ChatMessage> messages) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...List.generate(
              messages.length + (_chatService.isLoading ? 1 : 0),
              (index) {
                if (index == messages.length && _chatService.isLoading) {
                  return _buildTypingIndicator();
                }
                final message = messages[index];
                // Sin separación vertical entre mensajes: los frames quedan
                // pegados (solo el relleno interno de 1px de cada burbuja).
                return _buildMessageBubble(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == 'user';
    final color = isUser ? AppTheme.primary : AppTheme.backgroundLight;
    final textColor = isUser ? Colors.white : AppTheme.textPrimary;
    final icon = isUser ? Icons.person : Icons.smart_toy;
    final iconBg = isUser ? AppTheme.accent : AppTheme.primary;

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) _buildAvatar(icon, iconBg),
        if (!isUser) const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isUser ? 12 : 2),
                bottomRight: Radius.circular(isUser ? 2 : 12),
              ),
              border: isUser
                  ? null
                  : Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      width: 1,
                    ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectionArea(
                  child: SelectableText(
                    message.text,
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeBody,
                      color: textColor,
                      height: 1.0,
                    ),
                    selectionColor: isUser
                        ? Colors.white.withValues(alpha: 0.35)
                        : Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                // Chips de respuesta rápida de la pregunta guiada: viajan con
                // el mensaje del asistente y se envían con un solo toque.
                if (!isUser && (message.suggestions?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final suggestion in message.suggestions!)
                          ActionChip(
                            label: Text(
                              suggestion,
                              style: const TextStyle(
                                fontSize: AppTheme.fontSizeBodySmall,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: AppTheme.primary.withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            onPressed: _chatService.canSendMessage
                                ? () => _sendText(
                                    suggestion,
                                    // El chip viaja con el campo al que
                                    // pertenece. Respaldo: si la sesión es
                                    // antigua (sin suggestionField) pero la
                                    // guía sigue activa, se aplica al campo
                                    // guiado actual en lugar de caer en la IA
                                    // y mostrar "No pude aplicar ningún
                                    // campo".
                                    guideField:
                                        message.suggestionField ??
                                        _chatService.currentGuideField,
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isUser) const SizedBox(width: 8),
        if (isUser) _buildAvatar(icon, iconBg),
      ],
    );
  }

  Widget _buildAvatar(IconData icon, Color color) {
    return CircleAvatar(
      radius: 10,
      backgroundColor: color,
      child: Icon(icon, size: 14, color: Colors.white),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      children: [
        _buildAvatar(Icons.smart_toy, AppTheme.primary),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AppTheme.backgroundLight,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(12),
            ),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDot(0),
              const SizedBox(width: 4),
              _buildDot(200),
              const SizedBox(width: 4),
              _buildDot(400),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDot(int delayMs) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + delayMs),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppTheme.textSecondary.withValues(alpha: value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────
  // Input card
  // ──────────────────────────────────────────────

  Widget _buildInputCard() {
    final canSend = _chatService.canSendMessage;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_note,
                  size: AppTheme.fontSizeIcon,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Platícale al asistente',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeCardTitle,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              enabled: canSend,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: canSend
                    ? 'Escribe tu situación aquí...'
                    : 'Has alcanzado el límite de uso',
                hintStyle: canSend
                    ? TextStyle(
                        color: AppTheme.primary.withValues(alpha: 0.35),
                        fontSize: AppTheme.fontSizeInput,
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.primary.withValues(alpha: 0.12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(
                fontSize: AppTheme.fontSizeInput,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canSend ? _showPasteExternalCalcDialog : null,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Pegar cálculo externo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentDark,
                      side: BorderSide(
                        color: AppTheme.accent.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canSend ? _sendMessage : null,
                    icon: _chatService.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      _chatService.isLoading ? 'Enviando...' : 'Enviar',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(
                        fontSize: AppTheme.fontSizeBody,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Legal note card (footer, like the other 6 views)
  // ──────────────────────────────────────────────

  Widget _buildLegalNoteCard() {
    return const LegalNoteCard(
      // Una sola línea compacta: mantiene el frame delgado, sin ocupar
      // demasiado alto en la parte inferior de la pantalla.
      singleLine: true,
      note:
          'Este asistente es una ayuda para capturar tus datos. NO hace cálculos. '
          'La IA puede cometer errores, revisa siempre la información en las pestañas de la calculadora. '
          'La app cumple con uso justo: 30 mensajes por consulta, 15 consultas por día.',
    );
  }

  // ──────────────────────────────────────────────
  // Paste external calc dialog
  // ──────────────────────────────────────────────

  void _showPasteExternalCalcDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Pegar cálculo externo',
          style: TextStyle(
            fontSize: AppTheme.fontSizeSectionTitle,
            color: AppTheme.primary,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 8,
            maxLength: FairUsePolicy.maxCharsForExternalCalc,
            decoration: const InputDecoration(
              hintText:
                  'Pega aquí el texto del cálculo externo\npara comparar contra los resultados de la app...',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: AppTheme.fontSizeBody),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: AppTheme.fontSizeBody),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                _textController.text = text;
                _sendMessage();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Comparar',
              style: TextStyle(fontSize: AppTheme.fontSizeBody),
            ),
          ),
        ],
      ),
    );
  }
}
