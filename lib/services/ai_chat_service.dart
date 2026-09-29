import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/ai/chat_prompt.dart';
import '../core/ai/fair_use_policy.dart';
import '../core/ai/field_extractor.dart';
import '../core/ai/guided_input.dart';
import 'retroactive_provider.dart';

/// OpenRouter base URL for chat completions.
const String _kOpenRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';

/// Default model to use via OpenRouter.
const String _kDefaultModel = 'google/gemini-2.5-flash-lite';

/// Represents a single message in the chat conversation.
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String text;
  final DateTime timestamp;

  /// Chips de respuesta rápida que acompañan al mensaje del asistente cuando
  /// la app hace una pregunta guiada (ej. "Sí"/"No", "1"/"2"/"3").
  /// Solo los mensajes del asistente lo traen; `null` = sin chips.
  final List<String>? suggestions;

  /// Campo guiado al que pertenecen los [suggestions] de este mensaje.
  ///
  /// Permite que un clic en un chip se aplique SIEMPRE al campo que el chip
  /// representa visualmente, aunque la guía ya haya avanzado a otra pregunta.
  /// Sin esto, un clic en un chip de una pregunta ya respondida (p. ej. "1"
  /// sobre el chip viejo de "hijos") se interpretaba contra el campo guiado
  /// ACTIVO (p. ej. "padres") y actualizaba el campo equivocado.
  final String? suggestionField;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.suggestions,
    this.suggestionField,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    if (suggestions != null) 'suggestions': suggestions,
    if (suggestionField != null) 'suggestionField': suggestionField,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] as String? ?? 'user',
    text: json['text'] as String? ?? '',
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    suggestions: (json['suggestions'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList(),
    suggestionField: json['suggestionField'] as String?,
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

  const AiExplain({required this.message, required this.differences});
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

  // Campos opcionales que ya se han preguntado en la guía determinista (para
  // no repetirlos). Los obligatorios (semanas/salario) se re-preguntan hasta
  // que se llenen y no se registran aquí.
  final Set<String> _guidedFields = {};

  // Campo de la pregunta guiada actualmente activa (solo en el flujo
  // determinista iniciado por el chip "Ayúdame a llenar mi cálculo"). Mientras
  // esté fijado, la siguiente respuesta del usuario se interpreta y aplica
  // localmente sin llamar a la IA (causa raíz del bug `"type":"fill_fields"`).
  String? _currentGuideField;

  // Session tracking
  int _sessionMessageCount = 0;
  int _dailySessionCount = 0;
  int _dailyMessageCount = 0;

  AiChatService({
    required this._provider,
    required this._apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

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

  /// Campo de la pregunta guiada activa (null si la guía no está en curso).
  /// Lo usa la vista como respaldo para un clic en un chip de una sesión
  /// antigua (sin `suggestionField`): si la guía sigue activa, el clic se
  /// aplica al campo guiado actual en lugar de caer en la IA y mostrar el
  /// confuso "No pude aplicar ningún campo".
  String? get currentGuideField => _currentGuideField;

  /// `true` cuando ya no falta ningún dato del conjunto capturable (la guía
  /// determinista de [GuidedInput] no tiene más preguntas pendientes).
  ///
  /// Es la señal de "captura terminada" que usa el flujo natural
  /// IA Experta → Captura: la vista la consulta tras cada mensaje y, en el
  /// flanco de incompleto → completo, lleva al usuario a revisar y guardar
  /// en la pestaña Captura.
  bool get isCaptureComplete =>
      GuidedInput.nextGuide(_provider, _guidedFields) == null;

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
          .map(
            (s) => ChatMessage.fromJson(jsonDecode(s) as Map<String, dynamic>),
          )
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
    final toSave = _messages.length > maxMessages
        ? _messages.sublist(_messages.length - maxMessages)
        : _messages;
    await prefs.setStringList(
      'ai_chat_history',
      toSave.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  void _startNewSession() {
    _sessionMessageCount = 0;
    _guidedFields.clear();
    _currentGuideField = null;
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
  ///
  /// [guideField] lo usa un clic en un chip de respuesta rápida: indica el
  /// campo guiado al que pertenece el chip. Así el clic se aplica SIEMPRE a ese
  /// campo (aunque la guía ya haya avanzado a otra pregunta), en lugar de
  /// interpretarse contra el campo guiado activo. `null` = mensaje normal.
  Future<AiResponseResult?> sendMessage(
    String text, {
    String? guideField,
  }) async {
    // ── Clic en un chip de respuesta rápida de una pregunta guiada ──
    // El chip viaja con el campo al que pertenece (suggestionField). Aunque la
    // guía ya haya avanzado a otra pregunta, el clic debe actualizar el campo
    // que el chip representa visualmente (causa raíz del bug "2 hijos → 1 hijo
    // no se actualiza": el "1" se interpretaba contra "padres" en vez de
    // "hijos"). Se aplica localmente, sin llamar a la IA ni consumir cupo.
    if (guideField != null) {
      return _handleGuidedAnswer(guideField, text);
    }
    // ── Inicio del llenado guiado (chip "Ayúdame a llenar mi cálculo") ──
    // Respuesta 100% determinista y local: la app decide qué dato falta y
    // pregunta UNO a la vez (en orden fijo), sin llamar a la IA ni consumir
    // cupo diario/sesión. El usuario puede seguir respondiendo igual que en
    // el flujo guiado normal.
    if (_isGuidedStartIntent(text)) {
      _messages.add(ChatMessage(role: 'user', text: text));
      final guide = GuidedInput.nextGuide(_provider, _guidedFields);
      final String reply;
      final List<String> suggestions;
      if (guide != null) {
        _guidedFields.add(guide.field);
        _currentGuideField = guide.field;
        reply = guide.question;
        suggestions = guide.suggestions;
      } else {
        _currentGuideField = null;
        reply =
            '¡Listo! He guardado tu información. Puedes validarla en la '
            'pestaña Captura o revisar tus resultados en la pestaña Pensión.';
        suggestions = const <String>[];
      }
      _messages.add(
        ChatMessage(
          role: 'assistant',
          text: reply,
          suggestions: suggestions,
          suggestionField: guide?.field,
        ),
      );
      notifyListeners();
      return AiChat(reply);
    }

    // ── Respuesta a la pregunta guiada activa (flujo 100% determinista) ──
    // Mientras haya una pregunta guiada pendiente, la respuesta corta ("Sí",
    // "62", "2") se interpreta y aplica LOCALMENTE: sin llamar a la IA y sin
    // consumir cupo de sesión/día. Causa raíz del error `"type":"fill_fields"`:
    // antes, estas respuestas se enviaban a la IA, que devolvía JSON truncado
    // que se filtraba a la UI como texto visible.
    if (_currentGuideField != null) {
      return _handleGuidedAnswer(_currentGuideField!, text);
    }

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

      // Notify immediately so the user's message and the typing indicator
      // render while the OpenRouter call is in flight. Root fix for the chat
      // not scrolling down / not showing the user's message until the end.
      notifyListeners();

      // Build conversation messages for OpenRouter (OpenAI format)
      final openAiMessages = _buildOpenAiMessages();

      // Call OpenRouter API
      final responseText = await _callOpenRouterApi(openAiMessages);

      // Parse the response
      final result = _parseResponse(responseText);

      // Aplicación determinista de valores, INDEPENDIENTE del tipo de
      // respuesta de la IA. Causa raíz del bug de la edad: antes, los valores
      // SOLO se aplicaban cuando la IA devolvía exactamente un objeto
      // `fill_fields`; con historial de conversación la IA suele responder en
      // texto libre (`AiChat`) y la guardia nunca se ejecutaba.
      //
      // Regla de oro: el número que el usuario escribió SIEMPRE gana.
      final requestedEdits = FieldExtractor.detectRequestedEdits(text);

      final values = <String, dynamic>{};
      if (result is AiFillFields) {
        values.addAll(result.values);
      }
      // Las ediciones explícitas del usuario sobreescriben lo que devuelva
      // la IA (el usuario manda, la IA propone).
      requestedEdits.forEach((k, v) => values[k] = v);
      // Guardia específica de edad: cubre frases como "pensionarme a los 62"
      // (sin la palabra "edad") y agrega la edad si la IA la omite.
      final guarded = FieldExtractor.enforceRequestedAge(values, text);

      final setFields = FieldExtractor.applyValues(_provider, guarded);

      // Sync the "Datos aplicados" notification with the real applied value:
      // setEdadRetiro snaps off-grid ages (e.g. 60.5 → 60), so reflect the
      // snapped value instead of the raw number the AI echoed.
      if (setFields.contains('edadRetiro')) {
        guarded['edadRetiro'] = _provider.edadRetiro;
      }

      // ── Guía determinista: la APP decide qué dato falta y pregunta UNO a
      // la vez (en orden fijo), reemplazando la pregunta vaga "¿Falta algún
      // dato?" de la IA. La IA propone; la app guía. ──
      String displayMessage = _sanitizeMessage(_getDisplayMessage(result));
      List<String> suggestions = const <String>[];
      String? suggestionField;
      if (result is AiFillFields || setFields.isNotEmpty) {
        // Marca como "ya preguntados" los campos que la IA acaba de aplicar,
        // para que la guía pida el SIGUIENTE dato faltante y no repita el que
        // el usuario ya proporcionó (p. ej. no volver a pedir semanas después
        // de que el usuario dijo "tengo 1200 semanas cotizadas").
        _guidedFields.addAll(setFields);
        final guide = GuidedInput.nextGuide(_provider, _guidedFields);
        if (guide != null) {
          _guidedFields.add(guide.field);
          displayMessage = guide.question;
          suggestions = guide.suggestions;
          suggestionField = guide.field;
        } else if (_containsVagueMissingQuestion(displayMessage)) {
          displayMessage =
              '¡Listo! He guardado tu información. Puedes '
              'validarla en la pestaña Captura o revisar tus resultados en la '
              'pestaña Pensión.';
        }
      }

      // Mensaje del asistente con la pregunta guiada y chips de respuesta
      // rápida (si el dato lo permite).
      _messages.add(
        ChatMessage(
          role: 'assistant',
          text: displayMessage,
          suggestions: suggestions,
          suggestionField: suggestionField,
        ),
      );

      // Si la IA no devolvió fill_fields pero el usuario pidió un cambio
      // concreto (y de verdad se aplicó), se envuelve el resultado en
      // AiFillFields para que la UI muestre "✅ Datos aplicados".
      if (result is AiFillFields || setFields.isNotEmpty) {
        final updatedResult = AiFillFields(
          values: guarded,
          message: displayMessage,
          missingFields: result is AiFillFields
              ? result.missingFields
              : const <String>[],
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

  /// Interpreta y aplica LOCALMENTE la [text] como respuesta a la pregunta
  /// guiada de [field] (flujo 100% determinista, sin llamar a la IA ni
  /// consumir cupo de sesión/día).
  ///
  /// Se usa tanto para la pregunta guiada activa ([_currentGuideField]) como
  /// para un clic en un chip de respuesta rápida que pertenece a un campo
  /// concreto ([guideField] en [sendMessage]). Al aplicarlo al campo del chip
  /// (no al campo activo), un re-clic en un chip de una pregunta ya respondida
  /// actualiza el campo correcto.
  Future<AiResponseResult> _handleGuidedAnswer(
    String field,
    String text,
  ) async {
    _messages.add(ChatMessage(role: 'user', text: text));
    final answer = await GuidedInput.applyAnswer(_provider, field, text);
    final String reply;
    final List<String> suggestions;
    String? suggestionField;
    if (answer == null || !answer.ok) {
      // No se pudo interpretar, o la respuesta es legalmente inválida (p. ej.
      // fecha de alta posterior al 1 de julio de 1997) → se vuelve a preguntar
      // el mismo dato SIN avanzar al siguiente campo ni mostrar "¡Listo!". El
      // bloqueo usa el mismo criterio que la pestaña Pensión
      // (PensionConstants.fechaLimiteLey73).
      final guide = GuidedInput.questionFor(_provider, field);
      final String reason;
      if (answer == null) {
        reason = 'No entendí tu respuesta.';
      } else {
        final message = answer.message;
        reason = (message == null || message.isEmpty)
            ? 'No se pudo guardar el dato.'
            : message;
      }
      reply = (answer == null)
          ? '$reason ${guide.question}'
          : '$reason\n\n${guide.question}';
      suggestions = guide.suggestions;
      suggestionField = field;
      _messages.add(
        ChatMessage(
          role: 'assistant',
          text: reply,
          suggestions: suggestions,
          suggestionField: suggestionField,
        ),
      );
      notifyListeners();
      return AiChat(reply);
    }
    if (answer.nextField != null) {
      // Sub-flujo interno (p. ej. semanas de Modalidad 40 "por fechas"):
      // la respuesta interpretada enruta a la siguiente pregunta del
      // sub-flujo (fecha inicio → fecha fin) sin pasar por nextGuide.
      final guide = GuidedInput.questionFor(_provider, answer.nextField!);
      _guidedFields.add(answer.nextField!);
      _currentGuideField = answer.nextField!;
      reply = guide.question;
      suggestions = guide.suggestions;
      suggestionField = answer.nextField;
    } else {
      // Confirmación formateada del dato capturado (p. ej. la fecha de
      // nacimiento se muestra como AAAA-MM-DD (ISO) para que se vea correcta).
      final String confirmacion =
          answer.message ?? _confirmacionCampo(field, answer.setFields);
      final next = GuidedInput.nextGuide(_provider, _guidedFields);
      if (next != null) {
        _guidedFields.add(next.field);
        _currentGuideField = next.field;
        reply = confirmacion.isEmpty
            ? next.question
            : '$confirmacion\n\n${next.question}';
        suggestions = next.suggestions;
        suggestionField = next.field;
      } else {
        _currentGuideField = null;
        reply = confirmacion.isEmpty
            ? '¡Listo! He guardado tu información. Puedes validarla en la '
                  'pestaña Captura o revisar tus resultados en la pestaña '
                  'Pensión.'
            : '$confirmacion\n\n¡Listo! He guardado tu información. Puedes '
                  'validarla en la pestaña Captura o revisar tus resultados en '
                  'la pestaña Pensión.';
        suggestions = const <String>[];
      }
    }
    _messages.add(
      ChatMessage(
        role: 'assistant',
        text: reply,
        suggestions: suggestions,
        suggestionField: suggestionField,
      ),
    );
    await _saveState();
    notifyListeners();
    // Devuelve AiFillFields (en lugar de AiChat) para que la UI muestre la
    // confirmación "✅ Datos aplicados" con el valor capturado. Esto es clave
    // para un re-clic en un chip de una pregunta ya respondida: el usuario ve
    // de inmediato que su clic SÍ se aplicó (p. ej. "2 hijos" → numeroHijos=2).
    return AiFillFields(
      values: _buildValuesFromSetFields(answer.setFields),
      message: reply,
      missingFields: const <String>[],
      setFields: answer.setFields,
    );
  }

  /// Construye un mapa `field → valor actual` a partir de los [setFields]
  /// aplicados por [GuidedInput.applyAnswer], para que la UI pueda mostrar el
  /// valor capturado en la confirmación "✅ Datos aplicados".
  Map<String, dynamic> _buildValuesFromSetFields(List<String> setFields) {
    final values = <String, dynamic>{};
    for (final field in setFields) {
      switch (field) {
        case 'semanasCotizadas':
          values[field] = _provider.semanasCotizadas;
          break;
        case 'salarioDiarioPromedio':
          values[field] = _provider.salarioDiarioPromedio;
          break;
        case 'fechaNacimiento':
          values[field] = _provider.fechaNacimiento;
          break;
        case 'fechaAlta':
          values[field] = _provider.fechaAlta;
          break;
        case 'edadRetiro':
          values[field] = _provider.edadRetiro;
          break;
        case 'tieneEsposa':
          values[field] = _provider.tieneEsposa;
          break;
        case 'numeroHijos':
          values[field] = _provider.numeroHijos;
          break;
        case 'numeroPadres':
          values[field] = _provider.numeroPadres;
          break;
        case 'umaMultiplier':
          values[field] = _provider.umaMultiplier;
          break;
        case 'salarioPromedio250Semanas':
          values[field] = _provider.salarioPromedio250Semanas;
          break;
        case 'semanasEnMod40':
          values[field] = _provider.semanasEnMod40;
          break;
        case 'modalidad40OptOut':
          values[field] = _provider.modalidad40OptOut;
          break;
        case 'startDate':
          values[field] = _provider.startDate;
          break;
        case 'endDate':
          values[field] = _provider.endDate;
          break;
      }
    }
    return values;
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
      // Fuerza JSON estructurado (validado contra OpenRouter/gemini-2.5-flash
      // -lite en el E2E real): reduce que la IA responda en texto libre
      // (`AiChat`) en vez del objeto `fill_fields` esperado por el flujo.
      'response_format': {'type': 'json_object'},
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
        'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
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
  Future<String> callOpenRouterApiForTest(List<Map<String, String>> messages) =>
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
            final message =
                data['message'] as String? ??
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
              message:
                  data['message'] as String? ?? '¿Qué más necesitas saber?',
              expectedField: data['expected_field'] as String?,
            );

          case 'compare':
            final externalValues =
                data['external_values'] as Map<String, dynamic>? ?? {};
            final message =
                data['message'] as String? ??
                'He comparado los valores. Revisa las diferencias.';
            final differences =
                (data['differences'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            return AiCompare(
              externalValues: externalValues,
              message: message,
              differences: differences,
            );

          case 'explain':
            final explainMessage =
                data['message'] as String? ??
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
            return AiChat(
              _cleanText(
                data['message'] as String? ?? data['text'] as String? ?? text,
              ),
            );
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
      if (m != null) return _sanitizeMessage(m.group(1)!.trim());
    }
    return _sanitizeMessage(t.trim());
  }

  /// Evita que JSON crudo (p. ej. `"type":"fill_fields"` truncado) se filtre a
  /// la UI como texto visible. Causa raíz del error que el usuario veía tras
  /// la pregunta del cónyuge: la IA devolvía JSON malformado que se mostraba
  /// tal cual.
  String _sanitizeMessage(String message) {
    if (message.contains('"type"') ||
        message.contains('fill_fields') ||
        message.contains('"values"') ||
        message.contains('missing_fields')) {
      return 'He actualizado los datos que me indicaste. '
          '¿Hay algo más que quieras ajustar?';
    }
    return message;
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

  /// True cuando el mensaje de la IA es la pregunta vaga "¿Falta algún dato?",
  /// que delega en el usuario en lugar de guiarlo. La app la reemplaza por la
  /// guía determinista.
  bool _containsVagueMissingQuestion(String message) {
    final lower = message.toLowerCase();
    return lower.contains('falta alg') ||
        lower.contains('falta algun dato') ||
        lower.contains('te falta');
  }

  /// True cuando el mensaje pide iniciar el llenado guiado ("ayúdame a llenar
  /// mi cálculo", "cuenta conmigo, soy tu IA", ...). La app responde de forma
  /// 100% determinista (preguntando los datos faltantes uno a la vez) sin
  /// llamar a la IA.
  bool _isGuidedStartIntent(String text) {
    final lower = text.toLowerCase();
    return lower.contains('ayudame a llenar') ||
        lower.contains('ayúdame a llenar') ||
        lower.contains('ayudo a llenar') ||
        lower.contains('ayuda a llenar') ||
        lower.contains('llenar mi calculo') ||
        lower.contains('llenar mi cálculo') ||
        lower.contains('llenar tu calculo') ||
        lower.contains('llenar tu cálculo') ||
        lower.contains('llena mi calculo') ||
        lower.contains('llena mi cálculo') ||
        lower.contains('cuenta conmigo') ||
        lower.contains('cuentas conmigo') ||
        lower.contains('soy tu ia') ||
        lower.contains('empieza a preguntarme');
  }

  /// Devuelve una confirmación formateada del dato capturado en el flujo
  /// guiado, o una cadena vacía si no aplica. En particular, la fecha de
  /// nacimiento se muestra como AAAA-MM-DD (ISO) para que se vea correctamente
  /// (el usuario la escribe en formato compacto, p. ej. 30011969).
  String _confirmacionCampo(String field, List<String> setFields) {
    if (field == 'fechaNacimiento' && setFields.contains('fechaNacimiento')) {
      final d = _provider.fechaNacimiento;
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final aaaa = d.year.toString().padLeft(4, '0');
      return 'Perfecto, tu fecha de nacimiento es $aaaa-$mm-$dd.';
    }
    if (field == 'fechaAlta' && setFields.contains('fechaAlta')) {
      final d = _provider.fechaAlta;
      if (d == null) return '';
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final aaaa = d.year.toString().padLeft(4, '0');
      return 'Perfecto, tu fecha de alta en el IMSS es $aaaa-$mm-$dd.';
    }
    return '';
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
    messages.add({'role': 'system', 'content': ChatPrompt.systemPrompt});

    // App state context as a system message (invisible to user but guides AI)
    messages.add({'role': 'system', 'content': _buildAppStateContext()});

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
      '[CONTEXTO ACTUAL DE LA CALCULADORA - Valores actualmente cargados:]',
    );

    buf.writeln(
      'Salario promedio 250 sem. (anterior): ${_provider.salarioPromedio250Semanas}',
    );
    buf.writeln(
      'Nuevo salario promedio 250 sem. (con M40): ${_provider.nuevoSalarioPromedio}',
    );
    buf.writeln('UMA diaria: ${_provider.umaDiaria}');
    buf.writeln('Salario mínimo diario: ${_provider.salarioMinimoDiario}');
    buf.writeln('Año de pensión: ${_provider.pensionYear}');
    buf.writeln('Semanas cotizadas: ${_provider.semanasCotizadas}');
    buf.writeln('Tiene esposa: ${_provider.tieneEsposa}');
    buf.writeln('Número de hijos: ${_provider.numeroHijos}');
    buf.writeln('Número de padres: ${_provider.numeroPadres}');
    buf.writeln('Edad de retiro (con Mod40): ${_provider.edadRetiro}');
    buf.writeln('Salario registrado: ${_provider.salarioRegistrado}');
    buf.writeln('Años retroactivos: ${_provider.retroactiveYears}');
    buf.writeln(
      'Modalidad 40 opt-out (sin M40): ${_provider.modalidad40OptOut}',
    );

    final fact = _provider.factAsigCalculation;
    final pension = _provider.pensionMod40Calculation;
    final costo = _provider.costoMod40Calculation;
    final inversion = _provider.inversionCalculation;
    final financiamiento = _provider.financiamientoCalculation;
    final retroactivo = _provider.retroactiveCalculation;

    if (fact != null) {
      buf.writeln(
        '[RESULTADO] Pensión mensual (Fact+Asig): ${fact.totalPensionMensual}',
      );
      buf.writeln(
        '[RESULTADO] Pensión anual (Fact+Asig): ${fact.totalPensionAnual}',
      );
      buf.writeln(
        '[RESULTADO] Cuantía básica anual: ${fact.totalCuantiaBasicaAnual}',
      );
      buf.writeln(
        '[RESULTADO] Incrementos anuales total: ${fact.totalIncrementosAnuales}',
      );
      buf.writeln(
        '[RESULTADO] Asignaciones familiares total: ${fact.cuantiaTotalAsignaciones}',
      );
      buf.writeln(
        '[RESULTADO] Ayuda asistencial total: ${fact.totalAyudaAsistencial}',
      );
    }
    if (pension != null) {
      buf.writeln(
        '[RESULTADO] Pensión mensual (Mod40): ${pension.pensionMensual}',
      );
      buf.writeln(
        '[RESULTADO] Pensión mínima garantizada (Mod40): ${pension.pensionMinimaGarantizada}',
      );
    }
    if (costo != null) {
      buf.writeln('[RESULTADO] Costo total Modalidad 40: ${costo.costoTotal}');
    }
    if (inversion != null) {
      buf.writeln(
        '[RESULTADO] Ganancia total (Inversión): ${inversion.gananciaTotal}',
      );
      buf.writeln(
        '[RESULTADO] Tasa de rendimiento: ${inversion.tasaRendimiento}',
      );
    }
    if (financiamiento != null) {
      buf.writeln(
        '[RESULTADO] Financiamiento - monto del crédito: ${financiamiento.montoCredito}',
      );
      buf.writeln(
        '[RESULTADO] Financiamiento - costo financiamiento: ${financiamiento.costoFinanciamiento}',
      );
    }
    if (retroactivo != null) {
      buf.writeln(
        '[RESULTADO] Pago retroactivo - costo total: ${retroactivo.costoTotal}',
      );
      buf.writeln(
        '[RESULTADO] Pago retroactivo - inversión total: ${retroactivo.inversionTotal}',
      );
    }

    buf.writeln(
      '[INSTRUCCIÓN] Usa esta información de contexto para responder al usuario. Si el usuario pega un cálculo externo, usa el modo "compare" para comparar contra estos valores. Si el usuario responde "sí" a tu pregunta de explicar diferencias, usa el modo "explain" para dar una explicación detallada.',
    );

    return buf.toString();
  }
}
