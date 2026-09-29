/// Fair Use Policy for the AI Chat feature.
///
/// These limits prevent abuse by advisors (asesores) who might use a single
/// license to serve multiple clients. Each license is for one person only.
///
/// Limits are intentionally generous for legitimate personal use but prevent
/// systematic use across many clients.
class FairUsePolicy {
  FairUsePolicy._();

  // ──────────────────────────────────────────────
  // Per-session limits
  // ──────────────────────────────────────────────

  /// Maximum messages per conversation session.
  /// After this, the user must start a new consultation.
  /// Set to 30: enough for a full pension scenario description,
  /// follow-up questions, and external calculation comparison.
  static const int maxMessagesPerSession = 30;

  /// Maximum characters per user message.
  /// 3000 chars is enough for a detailed pension scenario or pasted
  /// external calculation text.
  static const int maxCharsPerMessage = 3000;

  /// Maximum characters for pasting an external calculation.
  /// Slightly larger to accommodate formatted calculation tables.
  static const int maxCharsForExternalCalc = 4000;

  // ──────────────────────────────────────────────
  // Daily limits (per device)
  // ──────────────────────────────────────────────

  /// Maximum AI chat sessions per day.
  /// 999 sessions/day while in testing ("dejado abierto") para que nunca
  /// bloquee durante las pruebas. Each session counts ONLY when the user
  /// actually sends its first message — NOT on page load or "Limpiar
  /// conversación" (those used to consume a daily slot and blocked the user
  /// after a few page loads).
  static const int maxSessionsPerDay = 999;

  /// Maximum total AI messages per day across all sessions.
  /// 9999 msgs/day = 999 sessions × 30 msgs each (nunca bloquea en pruebas).
  static const int maxMessagesPerDay = 9999;

  // ──────────────────────────────────────────────
  // Storage limits
  // ──────────────────────────────────────────────

  /// Maximum chat history entries to keep in local storage.
  /// Only the most recent sessions are preserved.
  static const int maxSavedChats = 5;

  /// Auto-clear chat history after this many hours of inactivity.
  static const int historyClearHours = 24;

  // ──────────────────────────────────────────────
  // UI Messages
  // ──────────────────────────────────────────────

  static const String limitSessionMessages =
      'Has alcanzado el límite de mensajes para esta conversación. '
      'Inicia una nueva consulta para continuar.';

  static const String limitDailySessions =
      'Has alcanzado el límite diario de consultas. '
      'Vuelve mañana para una nueva consulta.';

  static const String limitDailyMessages =
      'Has alcanzado el límite diario de mensajes. '
      'Vuelve mañana para continuar.';

  static const String limitMessageLength =
      'El mensaje es demasiado largo. '
      'Por favor, escribe un texto más corto (máximo 3000 caracteres).';

  static const String limitExternalCalcLength =
      'El cálculo externo es demasiado largo. '
      'Por favor, pégalo en partes más cortas (máximo 4000 caracteres).';
}
