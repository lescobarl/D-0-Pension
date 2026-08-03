import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/ai/api_key_obfuscator.dart';
import '../../core/ai/fair_use_policy.dart';
import '../../core/ai/field_extractor.dart';
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

class _AiChatViewState extends State<AiChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AiChatService _chatService;
  int _lastMessageCount = 0;
  bool _initialized = false;
  String? _lastAppliedMessage;
  bool _lastAppliedIsWarning = false;

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
      final jsonStr =
          await rootBundle.loadString('assets/config/api_key.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final obfuscated =
          json['openrouter_api_key_obfuscated'] as String? ?? '';
      key = obfuscated.isEmpty ? '' : ApiKeyObfuscator.decode(obfuscated);
    } catch (_) {
      key = '';
    }
    _apiKey = key;
    _initChatService();
  }

  void _initChatService() {
    final provider = context.read<RetroactiveProvider>();
    _chatService = AiChatService(
      provider: provider,
      apiKey: _apiKey,
    );
    _chatService.addListener(_onServiceChanged);
    _chatService.initialize().then((_) {
      if (mounted) {
        setState(() => _initialized = true);
      }
    }).catchError((Object e) {
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
      ErrorHandler.logDebug('AiChatView - Rebuild triggered at ${DateTime.now().toIso8601String()}');
      if (_chatService.messages.length != _lastMessageCount) {
        _lastMessageCount = _chatService.messages.length;
        setState(() {});
      } else {
        ErrorHandler.logDebug('Skipping rebuild - message count unchanged');
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    final result = await _chatService.sendMessage(text);

    if (result is AiFillFields) {
      if (result.setFields.isNotEmpty) {
        final details = result.setFields
            .map((f) =>
                '• ${FieldExtractor.fieldLabel(f)}: ${_formatAppliedValue(result.values, f)}')
            .join('\n');
        _lastAppliedMessage = '✅ Datos aplicados en la calculadora:\n$details';
        _lastAppliedIsWarning = false;
      } else {
        _lastAppliedMessage =
            '⚠️ No pude aplicar ningún campo. Repítelo claro, por ejemplo: '
            '"Pon mi edad de retiro en 63 años".';
        _lastAppliedIsWarning = true;
      }
      setState(() {});
    } else if (result is AiError) {
      _lastAppliedMessage = '⚠️ ${result.error}';
      _lastAppliedIsWarning = true;
      setState(() {});
    }

    _scrollToBottom();
  }

  String _formatAppliedValue(Map<String, dynamic> values, String field) {
    final v = FieldExtractor.valueFor(values, field);
    if (v == null) return 'actualizado';
    if (v is num) {
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
    }
    return '$v';
  }

  Future<void> _startNewSession() async {
    await _chatService.startNewSession();
    setState(() {
      _lastAppliedMessage = null;
      _lastAppliedIsWarning = false;
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

  // ──────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
        // Encabezado fijo y compacto.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: _buildHeader(),
        ),
        // Aviso de campos aplicados (compacto, justo sobre la conversación).
        if (_lastAppliedMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: _buildAppliedNotification(),
          ),
        // Conversación con scroll propio: aprovecha todo el espacio y el área
        // de entrada (botón Enviar) permanece siempre visible abajo.
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            children: [
              if (messages.isEmpty)
                _buildWelcomeCard()
              else
                _buildConversationCard(messages),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: const Icon(Icons.smart_toy, color: AppTheme.accent, size: 24),
          ),
          const SizedBox(width: AppTheme.spacingMd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ASISTENTE DE PENSIÓN',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Platícame tu situación y yo lleno los datos de la calculadora.',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeBodySmall,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Applied fields notification (green)
  // ──────────────────────────────────────────────

  Widget _buildAppliedNotification() {
    final isWarning = _lastAppliedIsWarning;
    final Color background =
        isWarning ? Colors.amber.shade50 : Colors.green.shade50;
    final Color foreground =
        isWarning ? Colors.orange.shade800 : Colors.green;
    final IconData icon =
        isWarning ? Icons.warning_amber_rounded : Icons.check_circle;
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: SelectionArea(
                child: SelectableText(
                  _lastAppliedMessage!,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeBody,
                    color: foreground,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _lastAppliedMessage = null),
              icon: Icon(Icons.close, color: foreground, size: 18),
              tooltip: 'Cerrar aviso',
            ),
          ],
        ),
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
            Row(
              children: [
                const Icon(
                  Icons.smart_toy,
                  size: AppTheme.fontSizeIcon,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: SelectableText(
                    '¿Cómo te puedo ayudar?',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeCardTitle,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
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
      onTap: () {
        _textController.text = text;
        HapticFeedback.selectionClick();
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
            const Icon(
              Icons.arrow_forward,
              size: 18,
              color: AppTheme.primary,
            ),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Botón de limpiar conversación (compacto, alineado a la derecha).
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _startNewSession,
                icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                label: const Text('Limpiar conversación'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: AppTheme.fontSizeBodySmall,
                  ),
                ),
              ),
            ),
            ...List.generate(
              messages.length + (_chatService.isLoading ? 1 : 0),
              (index) {
                if (index == messages.length && _chatService.isLoading) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _buildTypingIndicator(),
                  );
                }
                final message = messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _buildMessageBubble(message),
                );
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
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) _buildAvatar(icon, iconBg),
        if (!isUser) const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            child: SelectionArea(
              child: SelectableText(
                message.text,
                style: TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  color: textColor,
                  height: 1.2,
                ),
                selectionColor: isUser
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.blue.withValues(alpha: 0.3),
              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.backgroundLight,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(12),
            ),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.2),
            ),
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
    final limitReason = _chatService.limitReason;

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
            if (limitReason != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.errorColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.errorColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        limitReason,
                        style: const TextStyle(
                          fontSize: AppTheme.fontSizeBodySmall,
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                filled: true,
                fillColor: AppTheme.backgroundLight,
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
                    label: Text(_chatService.isLoading ? 'Enviando...' : 'Enviar'),
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
      singleLine: true,
      note:
          'Este asistente es una ayuda para capturar tus datos. NO hace cálculos. '
          'La IA puede cometer errores, revisa siempre la información en las pestañas de la calculadora. '
          'La app cumple con uso justo: 30 mensajes por consulta, 5 consultas por día.',
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
