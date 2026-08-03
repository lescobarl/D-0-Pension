import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/ai/chat_prompt.dart';
import '../core/ai/fair_use_policy.dart';
import '../core/ai/field_extractor.dart';
import 'retroactive_provider.dart';

/// OpenRouter base URL for chat completions.
const String _kOpenRouterUrl =
    'https://openrouter.ai/api/v1/chat/completions';

/// Default model to use via OpenRouter.
const String _kDefaultModel = 'google/gemini-2.5-flash-lite';

/// Represents a single message in the chat conversation.
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String? ?? 'user',
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Result from parsing an AI response.
sealed class AiResponseResult {
  const AiResponseResult();
}

class AiFillFields extends AiResponseResult {
  final Map<String, dynamic> values;
  final String message;
  final List<String> missingFields;
  final List<String> setFields;

  const AiFillFields({
    required this.values,
    required this.message,
    required this.missingFields,
    required this.setFields,
  });
}

/// Free conversational text response (greetings, thanks, casual chat).
class AiChat extends AiResponseResult {
  final String message;
  const AiChat(this.message);
}

class AiQuestion extends AiResponseResult {
  final String message;
  final String? expectedField;

  const AiQuestion({required this.message, this.expectedField});
}

class AiCompare extends AiResponseResult {
  final Map<String, dynamic> externalValues;
  final String message;
  final List<String> differences;

  const AiCompare({
    required this.externalValues,
    required this.message,
    required this.differences,
  });
}

/// Explanation response after a comparison (breaks the compare loop).
///
/// When the user says "yes" to "Do you want me to explain the differences?",
/// the AI uses this mode to provide a natural-language explanation of
/// the differences between the external calculation and the app's results.
class AiExplain extends AiResponseResult {
  final String message;
  final List<String> differences;

  const AiExplain({
    required this.message,
    required this.differences,
  });
}

class AiError extends AiResponseResult {
  final String error;

  const AiError(this.error);
}

/// Service that manages the AI chat conversation via OpenRouter.
///
/// Handles:
/// - Sending messages to OpenRouter API (OpenAI-compatible format)
/// - Parsing structured JSON responses
/// - Applying extracted values to the provider
/// - Enforcing fair use policy limits
/// - Persisting chat history
class AiChatService extends ChangeNotifier {
  final RetroactiveProvider _provider;
  final String _apiKey;
  final http.Client _client;

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _lastError;

  // Session tracking
  int _sessionMessageCount = 0;
  int _dailySessionCount = 0;
  int _dailyMessageCount = 0;

  AiChatService({
    required RetroactiveProvider provider,
    required String apiKey,
    http.Client? client,
  })  : _provider = provider,
        _apiKey = apiKey,
        _client = client ?? http.Client();

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  // ──────────────────────────────────────────────
  // Getters
  // ──────────────────────────────────────────────

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  int get sessionMessageCount => _sessionMessageCount;
  int get dailySessionCount => _dailySessionCount;
  int get dailyMessageCount => _dailyMessageCount;
  int get sessionMessageRemaining =>
      FairUsePolicy.maxMessagesPerSession - _sessionMessageCount;
  int get dailyMessageRemaining =>
      FairUsePolicy.maxMessagesPerDay - _dailyMessageCount;
  int get dailySessionRemaining =>
      FairUsePolicy.maxSessionsPerDay - _dailySessionCount;

  bool get canSendMessage =>
      !_isLoading &&
      _sessionMessageCount < FairUsePolicy.maxMessagesPerSession &&
      _dailyMessageCount < FairUsePolicy.maxMessagesPerDay &&
      _dailySessionCount < FairUsePolicy.maxSessionsPerDay;

  String? get limitReason {
    if (_sessionMessageCount >= FairUsePolicy.maxMessagesPerSession) {
      return FairUsePolicy.limitSessionMessages;
    }
    if (_dailyMessageCount >= FairUsePolicy.maxMessagesPerDay) {
      return FairUsePolicy.limitDailyMessages;
    }
    if (_dailySessionCount >= FairUsePolicy.maxSessionsPerDay) {
      return FairUsePolicy.limitDailySessions;
    }
    return null;
  }

  // ──────────────────────────────────────────────
  // Initialization & Persistence
  // ──────────────────────────────────────────────

  /// Load persisted state and start a new session.
  Future<void> initialize() async {
    await _loadState();
    _startNewSession();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    // Load daily counters
    final savedDate = prefs.getString('ai_chat_date') ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (savedDate == today) {
      _dailySessionCount = prefs.getInt('ai_chat_sessions') ?? 0;
      _dailyMessageCount = prefs.getInt('ai_chat_messages') ?? 0;
    } else {
      _dailySessionCount = 0;
      _dailyMessageCount = 0;
      await prefs.setString('ai_chat_date', today);
      await prefs.setInt('ai_chat_sessions', 0);
      await prefs.setInt('ai_chat_messages', 0);
    }

    // Load last session messages
    try {
      final historyJson = prefs.getStringList('ai_chat_history') ?? [];
      _messages = historyJson
          .map((s) =>
              ChatMessage.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt persisted history should never block the assistant.
      _messages = [];
      await prefs.remove('ai_chat_history');
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ai_chat_sessions', _dailySessionCount);
    await prefs.setInt('ai_chat_messages', _dailyMessageCount);

    // Save only last N messages
    final maxMessages = FairUsePolicy.maxSavedChats * 6;
    final toSave =
        _messages.length > maxMessages
            ? _messages.sublist(_messages.length - maxMessages)
            : _messages;
    await prefs.setStringList(
      'ai_chat_history',
      toSave.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  void _startNewSession() {
    _sessionMessageCount = 0;
    // NOTA: aquí ya NO se incrementa _dailySessionCount. Una consulta se
    // cuenta de forma perezosa en sendMessage(), solo cuando el usuario envía
    // el primer mensaje de una sesión nueva. Antes, cada apertura de la
    // pestaña AI (initialize) y cada "Limpiar conversación" (startNewSession)
    // consumía un cupo diario y bloqueaba al usuario tras pocas interacciones.
    notifyListeners();
  }

  // ──────────────────────────────────────────────
  // Send Message
  // ──────────────────────────────────────────────

  /// Send a user message to OpenRouter and process the response.
  Future<AiResponseResult?> sendMessage(String text) async {
    // Count a consultation lazily: only the first message of a fresh session
    // consumes a daily slot. Page loads and "Limpiar conversación" do not.
    if (_sessionMessageCount == 0) {
      _dailySessionCount++;
    }

    // Check fair use limits
    if (!canSendMessage) {
      _lastError = limitReason;
      notifyListeners();
      return AiError(limitReason ?? 'Límite de uso alcanzado');
    }

    // Check message length
    if (text.length > FairUsePolicy.maxCharsPerMessage) {
      _lastError = FairUsePolicy.limitMessageLength;
      notifyListeners();
      return AiError(FairUsePolicy.limitMessageLength);
    }

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      // Add user message
      final userMsg = ChatMessage(role: 'user', text: text);
      _messages.add(userMsg);
      _sessionMessageCount++;
      _dailyMessageCount++;

      // Build conversation messages for OpenRouter (OpenAI format)
      final openAiMessages = _buildOpenAiMessages();

      // Call OpenRouter API
      final responseText = await _callOpenRouterApi(openAiMessages);

      // Parse the response
      final result = _parseResponse(responseText);

      // Add assistant message
      final assistantMsg = ChatMessage(
        role: 'assistant',
        text: _getDisplayMessage(result),
      );
      _messages.add(assistantMsg);

      // Apply values if it's a fill_fields response
      if (result is AiFillFields) {
        // Guardia determinista: si el usuario pidió explícitamente mover la
        // edad de retiro a un número concreto (p. ej. "mueve la edad de
        // pensión a 62 años"), se aplica EXACTAMENTE ese número aunque la IA
        // devuelva otro (por contaminación del número del ejemplo del prompt).
        final values = FieldExtractor.enforceRequestedAge(result.values, text);
        final setFields = FieldExtractor.applyValues(_provider, values);
        final updatedResult = AiFillFields(
          values: values,
          message: result.message,
          missingFields: result.missingFields,
          setFields: setFields,
        );
        await _saveState();
        _isLoading = false;
        notifyListeners();
        return updatedResult;
      }

      await _saveState();
      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _lastError = 'Error al comunicarse con el asistente: $e';
      _isLoading = false;
      notifyListeners();
      return AiError(_lastError!);
    }
  }

  // ──────────────────────────────────────────────
  // New Session
  // ──────────────────────────────────────────────

  /// Start a new chat session (clears current conversation).
  Future<void> startNewSession() async {
    _messages = [];
    _sessionMessageCount = 0;
    _lastError = null;
    _startNewSession();
    await _saveState();
  }

  /// Reset daily counters (for testing or admin purposes).
  Future<void> resetDailyCounters() async {
    _dailySessionCount = 0;
    _dailyMessageCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ai_chat_sessions', 0);
    await prefs.setInt('ai_chat_messages', 0);
    notifyListeners();
  }

  // ──────────────────────────────────────────────
  // OpenRouter API Call (OpenAI-compatible format)
  // ──────────────────────────────────────────────

  Future<String> _callOpenRouterApi(List<Map<String, String>> messages) async {
    final url = Uri.parse(_kOpenRouterUrl);

    final body = jsonEncode({
      'model': _kDefaultModel,
      'messages': messages,
      'temperature': 0.2,
      'max_tokens': 1024,
      'top_p': 0.8,
    });

    // package:http resolves to BrowserClient (fetch/XHR) on web and
    // IOClient on VM/mobile, so this call works on every platform.
    final response = await _client
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            // OpenRouter recommended headers
            'HTTP-Referer': 'https://d-0-pension.app',
            'X-Title': 'D-0-Pension Calculator',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
          'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    // Decode as UTF-8 explicitly (OpenRouter responses are UTF-8).
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    // Extract the assistant's message from OpenAI format
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No choices in response');
    }
    final message = choices[0] as Map<String, dynamic>;
    final content = message['message'] as Map<String, dynamic>?;
    final text = content?['content'] as String?;
    if (text == null || text.isEmpty) {
      throw Exception('Empty response from model');
    }
    return text;
  }

  /// Test seam: exposes the OpenRouter HTTP call so tests can exercise the
  /// exact request/response path (including web) with a mocked [http.Client].
  @visibleForTesting
  Future<String> callOpenRouterApiForTest(
    List<Map<String, String>> messages,
  ) =>
      _callOpenRouterApi(messages);

  // ──────────────────────────────────────────────
  // Response Parsing
  // ──────────────────────────────────────────────

  AiResponseResult _parseResponse(String text) {
    // First, try to extract structured JSON from the response.
    final jsonStr = _extractJson(text);

    if (jsonStr != null) {
      try {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final type = data['type'] as String? ?? '';

        switch (type) {
          case 'fill_fields':
            final values = data['values'] as Map<String, dynamic>? ?? {};
            final message = data['message'] as String? ??
                'He actualizado los datos en la calculadora.';
            final missingFields =
                (data['missing_fields'] as List<dynamic>?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [];
            return AiFillFields(
              values: values,
              message: message,
              missingFields: missingFields,
              setFields: [],
            );

          case 'question':
            return AiQuestion(
              message: data['message'] as String? ??
                  '¿Qué más necesitas saber?',
              expectedField: data['expected_field'] as String?,
            );

          case 'compare':
            final externalValues =
                data['external_values'] as Map<String, dynamic>? ?? {};
            final message = data['message'] as String? ??
                'He comparado los valores. Revisa las diferencias.';
            final differences = (data['differences'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            return AiCompare(
              externalValues: externalValues,
              message: message,
              differences: differences,
            );

          case 'explain':
            final explainMessage = data['message'] as String? ??
                'Aquí te explico las diferencias encontradas.';
            final explainDifferences =
                (data['differences'] as List<dynamic>?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [];
            return AiExplain(
              message: explainMessage,
              differences: explainDifferences,
            );

          default:
            // JSON without recognized 'type' → treat as chat.
            return AiChat(_cleanText(
              data['message'] as String? ??
                  data['text'] as String? ??
                  text,
            ));
        }
      } catch (_) {
        // JSON extraction succeeded but parsing failed → fall through to chat.
      }
    }

    // No JSON → free conversational response (greetings, thanks, casual chat).
    return AiChat(_cleanText(text));
  }

  /// Clean conversational text: strip leftover markdown/json artifacts.
  String _cleanText(String text) {
    var t = text.trim();
    // Strip any leftover code fences.
    t = t.replaceAll(RegExp(r'```(?:json)?'), '');
    t = t.replaceAll('```', '');
    // Strip stray JSON object/array wrappers.
    final trimmed = t.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      // Try to extract the "message" field from stray JSON.
      final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(trimmed);
      if (m != null) return m.group(1)!.trim();
    }
    return t.trim();
  }

  /// Extract JSON from text that may contain markdown code blocks.
  String? _extractJson(String text) {
    // Try to find JSON in a code block
    final codeBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final match = codeBlockRegex.firstMatch(text);
    if (match != null) {
      return match.group(1)?.trim();
    }

    // Try to find a JSON object via balanced-brace scan.
    return _extractBalancedJson(text);
  }

  /// Extract the first balanced `{...}` JSON object from [text].
  ///
  /// More robust than a greedy regex: it stops at the matching closing brace,
  /// so trailing prose after the JSON (e.g. "Estos son tus datos actualizados.")
  /// does not corrupt the parse. Handles nested objects/arrays and strings
  /// containing braces.
  String? _extractBalancedJson(String text) {
    var inString = false;
    var escape = false;
    var depth = 0;
    int? start;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];

      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }

      if (ch == '"') {
        inString = true;
        continue;
      }

      if (ch == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0 && start != null) {
          return text.substring(start, i + 1);
        }
      }
    }

    return null;
  }

  /// Get a display-friendly message from the response result.
  String _getDisplayMessage(AiResponseResult result) {
    return switch (result) {
      AiFillFields r => r.message,
      AiQuestion r => r.message,
      AiCompare r => r.message,
      AiExplain r => r.message,
      AiChat r => r.message,
      AiError r => r.error,
    };
  }

  // ──────────────────────────────────────────────
  // OpenAI-compatible Messages Builder
  // ──────────────────────────────────────────────

  /// Build messages array in OpenAI format for OpenRouter.
  ///
  /// OpenRouter (and OpenAI) support a dedicated `system` role message,
  /// so we can send the system prompt properly instead of prepending it
  /// to user messages.
  List<Map<String, String>> _buildOpenAiMessages() {
    final messages = <Map<String, String>>[];

    // System prompt as a dedicated system message
    messages.add({
      'role': 'system',
      'content': ChatPrompt.systemPrompt,
    });

    // App state context as a system message (invisible to user but guides AI)
    messages.add({
      'role': 'system',
      'content': _buildAppStateContext(),
    });

    // Add all conversation messages
    for (final msg in _messages) {
      messages.add({
        'role': msg.role, // 'user' or 'assistant'
        'content': msg.text,
      });
    }

    return messages;
  }

  /// Build a context string with current app state values.
  String _buildAppStateContext() {
    final buf = StringBuffer();
    buf.writeln(
        '[CONTEXTO ACTUAL DE LA CALCULADORA - Valores actualmente cargados:]');

    buf.writeln(
        'Salario promedio 250 sem. (anterior): ${_provider.salarioPromedio250Semanas}');
    buf.writeln(
        'Nuevo salario promedio 250 sem. (con M40): ${_provider.nuevoSalarioPromedio}');
    buf.writeln('UMA diaria: ${_provider.umaDiaria}');
    buf.writeln(
        'Salario mínimo diario: ${_provider.salarioMinimoDiario}');
    buf.writeln('Año de pensión: ${_provider.pensionYear}');
    buf.writeln('Semanas cotizadas: ${_provider.semanasCotizadas}');
    buf.writeln('Tiene esposa: ${_provider.tieneEsposa}');
    buf.writeln('Número de hijos: ${_provider.numeroHijos}');
    buf.writeln('Número de padres: ${_provider.numeroPadres}');
    buf.writeln(
        'Edad de retiro (con Mod40): ${_provider.edadRetiro}');
    buf.writeln(
        'Salario registrado: ${_provider.salarioRegistrado}');
    buf.writeln(
        'Años retroactivos: ${_provider.retroactiveYears}');
    buf.writeln(
        'Edad retiro: ${_provider.edadRetiro}');

    final fact = _provider.factAsigCalculation;
    final pension = _provider.pensionMod40Calculation;
    final costo = _provider.costoMod40Calculation;
    final inversion = _provider.inversionCalculation;
    final financiamiento = _provider.financiamientoCalculation;
    final retroactivo = _provider.retroactiveCalculation;

    if (fact != null) {
      buf.writeln(
          '[RESULTADO] Pensión mensual (Fact+Asig): ${fact.totalPensionMensual}');
      buf.writeln(
          '[RESULTADO] Pensión anual (Fact+Asig): ${fact.totalPensionAnual}');
      buf.writeln(
          '[RESULTADO] Cuantía básica anual: ${fact.totalCuantiaBasicaAnual}');
      buf.writeln(
          '[RESULTADO] Incrementos anuales total: ${fact.totalIncrementosAnuales}');
      buf.writeln(
          '[RESULTADO] Asignaciones familiares total: ${fact.cuantiaTotalAsignaciones}');
      buf.writeln(
          '[RESULTADO] Ayuda asistencial total: ${fact.totalAyudaAsistencial}');
    }
    if (pension != null) {
      buf.writeln(
          '[RESULTADO] Pensión mensual (Mod40): ${pension.pensionMensual}');
      buf.writeln(
          '[RESULTADO] Pensión mínima garantizada (Mod40): ${pension.pensionMinimaGarantizada}');
    }
    if (costo != null) {
      buf.writeln(
          '[RESULTADO] Costo total Modalidad 40: ${costo.costoTotal}');
    }
    if (inversion != null) {
      buf.writeln(
          '[RESULTADO] Ganancia total (Inversión): ${inversion.gananciaTotal}');
      buf.writeln(
          '[RESULTADO] Tasa de rendimiento: ${inversion.tasaRendimiento}');
    }
    if (financiamiento != null) {
      buf.writeln(
          '[RESULTADO] Financiamiento - monto del crédito: ${financiamiento.montoCredito}');
      buf.writeln(
          '[RESULTADO] Financiamiento - costo financiamiento: ${financiamiento.costoFinanciamiento}');
    }
    if (retroactivo != null) {
      buf.writeln(
          '[RESULTADO] Pago retroactivo - costo total: ${retroactivo.costoTotal}');
      buf.writeln(
          '[RESULTADO] Pago retroactivo - inversión total: ${retroactivo.inversionTotal}');
    }

    buf.writeln(
        '[INSTRUCCIÓN] Usa esta información de contexto para responder al usuario. Si el usuario pega un cálculo externo, usa el modo "compare" para comparar contra estos valores. Si el usuario responde "sí" a tu pregunta de explicar diferencias, usa el modo "explain" para dar una explicación detallada.');

    return buf.toString();
  }
}
