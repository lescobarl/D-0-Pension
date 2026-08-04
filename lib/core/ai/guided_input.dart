import '../../services/retroactive_provider.dart';

/// Guía determinista de captura de datos.
///
/// Es LA APP (no la IA) quien decide qué dato falta y pregunta UN dato
/// concreto a la vez, en un orden fijo de prioridad. Así se elimina la
/// pregunta vaga "¿Falta algún dato?" que delegaba en el usuario: en su lugar
/// la app indica exactamente qué debe proporcionar y, cuando el dato admite
/// respuestas cortas, ofrece chips de respuesta rápida.
///
/// ## Orden de prioridad
/// 1. `semanasCotizadas`  → obligatorio (sentinel 0 = falta)
/// 2. `salarioDiarioPromedio` → obligatorio (sentinel 0 = falta)
/// 3. `edadRetiro`        → se pregunta una sola vez
/// 4. `tieneEsposa`       → se pregunta una sola vez
/// 5. `numeroHijos`       → se pregunta una sola vez
/// 6. `numeroPadres`      → se pregunta una sola vez
///
/// Los campos obligatorios se vuelven a preguntar mientras sigan en 0; los
/// opcionales solo una vez (marcados en [requested] por el servicio).
class GuidedInput {
  GuidedInput._();

  /// Pregunta guiada para el siguiente dato faltante, o `null` cuando ya no
  /// falta ningún dato del conjunto capturable.
  ///
  /// [requested] contiene los campos opcionales que ya se han preguntado en
  /// esta sesión (para no repetirlos). Los campos obligatorios se ignoran en
  /// este set porque se re-preguntan hasta que se llenan.
  static ({String field, String question, List<String> suggestions})? nextGuide(
    RetroactiveProvider provider,
    Set<String> requested,
  ) {
    // ── Obligatorios (sentinel > 0) ──
    if (provider.semanasCotizadas <= 0) {
      return _guideFor('semanasCotizadas', provider);
    }
    if (provider.salarioDiarioPromedio <= 0) {
      return _guideFor('salarioDiarioPromedio', provider);
    }

    // ── Opcionales (se preguntan una sola vez) ──
    for (final field
        in const ['edadRetiro', 'tieneEsposa', 'numeroHijos', 'numeroPadres']) {
      if (!requested.contains(field)) {
        return _guideFor(field, provider);
      }
    }

    return null;
  }

  static ({String field, String question, List<String> suggestions}) _guideFor(
    String field,
    RetroactiveProvider provider,
  ) {
    switch (field) {
      case 'semanasCotizadas':
        return (
          field: field,
          question: 'Para completar tu cálculo necesito saber: '
              '¿cuántas semanas cotizadas tienes ante el IMSS?',
          suggestions: const <String>[],
        );
      case 'salarioDiarioPromedio':
        return (
          field: field,
          question: '¿Cuál es tu salario diario aproximado? '
              '(por ejemplo, \$500)',
          suggestions: const <String>[],
        );
      case 'edadRetiro':
        return (
          field: field,
          question: '¿A qué edad quieres pensionarte? '
              'Puede ser entre 60 y 65 años (por ejemplo, 62).',
          suggestions: _edadRetiroSuggestions(provider),
        );
      case 'tieneEsposa':
        return (
          field: field,
          question: 'Para las asignaciones familiares: '
              '¿tienes esposa o cónyuge?',
          suggestions: const <String>['Sí', 'No'],
        );
      case 'numeroHijos':
        return (
          field: field,
          question: '¿Cuántos hijos tienes?',
          suggestions: const <String>['1', '2', '3', '4'],
        );
      case 'numeroPadres':
        return (
          field: field,
          question: '¿Cuántos padres dependen de ti?',
          suggestions: const <String>['0', '1', '2'],
        );
      default:
        return (
          field: field,
          question: 'Por favor proporciona el dato faltante.',
          suggestions: const <String>[],
        );
    }
  }

  /// Pregunta guiada para un [field] concreto (usada para volver a preguntar
  /// el mismo dato cuando la respuesta del usuario no se pudo interpretar).
  static ({String field, String question, List<String> suggestions}) questionFor(
    RetroactiveProvider provider,
    String field,
  ) =>
      _guideFor(field, provider);

  /// Interpreta y aplica la [text] del usuario como respuesta a la pregunta
  /// guiada de [field].
  ///
  /// Devuelve `null` cuando la respuesta no se pudo interpretar (el llamador
  /// debe volver a preguntar el mismo dato). Devuelve el record con `ok=true`
  /// y la lista de campos aplicados cuando sí se pudo aplicar.
  static Future<({bool ok, List<String> setFields})?> applyAnswer(
    RetroactiveProvider provider,
    String field,
    String text,
  ) async {
    switch (field) {
      case 'semanasCotizadas':
        final v = _extractInt(text);
        if (v == null || v <= 0) return null;
        provider.setSemanasCotizadas(v);
        return (ok: true, setFields: ['semanasCotizadas']);

      case 'salarioDiarioPromedio':
        final v = _extractNum(text);
        if (v == null || v <= 0) return null;
        provider.setSalarioDiarioPromedio(v);
        return (ok: true, setFields: ['salarioDiarioPromedio']);

      case 'edadRetiro':
        final v = _extractNum(text);
        if (v == null || v < 60 || v > 65) return null;
        await provider.setEdadRetiro(v);
        return (ok: true, setFields: ['edadRetiro']);

      case 'tieneEsposa':
        final lower = text.toLowerCase();
        if (RegExp(r'\bno\b|false|solter|divorci').hasMatch(lower)) {
          provider.setTieneEsposa(false);
          return (ok: true, setFields: ['tieneEsposa']);
        }
        if (RegExp(r's[ií]|true|casad|esposa|c[oó]nyuge').hasMatch(lower)) {
          provider.setTieneEsposa(true);
          return (ok: true, setFields: ['tieneEsposa']);
        }
        return null;

      case 'numeroHijos':
        final v = _extractCount(text);
        if (v == null || v < 0 || v > 20) return null;
        provider.setNumeroHijos(v);
        return (ok: true, setFields: ['numeroHijos']);

      case 'numeroPadres':
        final v = _extractCount(text);
        if (v == null || v < 0 || v > 10) return null;
        provider.setNumeroPadres(v);
        return (ok: true, setFields: ['numeroPadres']);

      default:
        return null;
    }
  }

  /// Lista de edades del dropdown de retiro como texto (p. ej. "60", "60.51"),
  /// para los chips de la pregunta guiada. Si el proveedor aún no tiene
  /// metadata (no inicializado) cae a una lista de respaldo 60..65.
  static List<String> _edadRetiroSuggestions(RetroactiveProvider provider) {
    try {
      final ages = provider.availableAgesRetiro;
      return [
        for (final a in ages)
          a == a.roundToDouble() ? a.toInt().toString() : a.toStringAsFixed(2),
      ];
    } catch (_) {
      return const ['60', '61', '62', '63', '64', '65'];
    }
  }

  /// Primer número (entero o decimal, con coma o punto) en [text], o `null`.
  static double? _extractNum(String text) {
    final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(text);
    return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

  /// Primer entero en [text], o `null`.
  static int? _extractInt(String text) {
    final m = RegExp(r'-?\d+').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  /// Conteo en [text] admitiendo dígitos y palabras en español: primero dígito,
  /// luego palabra positiva ("dos", "un"), luego negación/cero ("no", "ninguno").
  ///
  /// Las palabras positivas se comparan con límites de palabra (`\b`) para que
  /// "ninguno"/"ninguna" no se interpreten como "uno" (colisión de subcadena).
  static int? _extractCount(String text) {
    final lower = text.toLowerCase();
    final digit = _extractInt(lower);
    if (digit != null) return digit;
    const positives = <String, int>{
      'uno': 1,
      'una': 1,
      'un': 1,
      'dos': 2,
      'tres': 3,
      'cuatro': 4,
      'cinco': 5,
      'seis': 6,
      'siete': 7,
      'ocho': 8,
      'nueve': 9,
      'diez': 10,
    };
    for (final entry in positives.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(lower)) return entry.value;
    }
    if (RegExp(r'\bno\b|ning[uú]n|nada|cero').hasMatch(lower)) return 0;
    return null;
  }
}
