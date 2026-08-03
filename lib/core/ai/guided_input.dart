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
      return _guideFor('semanasCotizadas');
    }
    if (provider.salarioDiarioPromedio <= 0) {
      return _guideFor('salarioDiarioPromedio');
    }

    // ── Opcionales (se preguntan una sola vez) ──
    for (final field
        in const ['edadRetiro', 'tieneEsposa', 'numeroHijos', 'numeroPadres']) {
      if (!requested.contains(field)) {
        return _guideFor(field);
      }
    }

    return null;
  }

  static ({String field, String question, List<String> suggestions}) _guideFor(
    String field,
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
          suggestions: const <String>['60', '62', '65'],
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
}
