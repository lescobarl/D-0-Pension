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
/// 1. `semanasCotizadas`          → vital: se pregunta SIEMPRE una vez por sesión
/// 2. `salarioPromedio250Semanas` → vital: se pregunta SIEMPRE una vez por sesión
/// 3. `semanasEnMod40`            → vital: se pregunta SIEMPRE una vez por sesión
///                                  (número o "por fechas": inicio/fin)
/// 4. `salarioDiarioPromedio`     → respaldo (solo si sigue en 0)
/// 5. `fechaNacimiento`           → se pregunta una sola vez (clave edad/pensión)
/// 6. `edadRetiro`                → se pregunta una sola vez
/// 7. `tieneEsposa`               → se pregunta una sola vez
/// 8. `numeroHijos`               → se pregunta una sola vez
/// 9. `numeroPadres`              → se pregunta una sola vez
/// 10. `umaMultiplier`            → se pregunta una sola vez (salario Mod40)
///
/// Todos los campos se preguntan una sola vez por sesión (marcados en
/// [requested] por el servicio). Los datos vitales se preguntan SIEMPRE aunque
/// el proveedor ya tenga un valor precargado por defecto (se ignoran los
/// defaults sembrados).
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
    // ── Datos vitales: se preguntan SIEMPRE una vez por sesión, aunque el
    // proveedor ya tenga un valor precargado por defecto (se ignoran los
    // defaults) ──
    for (final field
        in const [
      'semanasCotizadas',
      'salarioPromedio250Semanas',
      'semanasEnMod40',
    ]) {
      if (!requested.contains(field)) {
        return _guideFor(field, provider);
      }
    }

    // ── Respaldo: salario diario promedio (solo si sigue en 0 y aún no se ha
    // preguntado) ──
    if (provider.salarioDiarioPromedio <= 0 &&
        !requested.contains('salarioDiarioPromedio')) {
      return _guideFor('salarioDiarioPromedio', provider);
    }

    // ── Opcionales (se preguntan una sola vez) ──
    // NOTA: `edadRetiro` NO se pregunta en la guía: la edad se deja con su
    // valor por defecto y el usuario puede ajustarla después en la calculadora.
    for (final field
        in const [
      'fechaNacimiento',
      'tieneEsposa',
      'numeroHijos',
      'numeroPadres',
      'umaMultiplier',
    ]) {
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
      case 'salarioPromedio250Semanas':
        return (
          field: field,
          question: 'Para el cálculo necesito tu salario promedio de las '
              'últimas 250 semanas. ¿Cuál es? (por ejemplo, 1300)',
          suggestions: const <String>[],
        );
      case 'semanasEnMod40':
        return (
          field: field,
          question: '¿Cuántas semanas estás cotizando en Modalidad 40? '
              'Responde con un número (por ejemplo, 130).',
          suggestions: const <String>[],
        );
      case 'm40StartDate':
        return (
          field: field,
          question: '¿Desde qué fecha estás en Modalidad 40? '
              '(por ejemplo, 01/01/2010)',
          suggestions: const <String>[],
        );
      case 'm40EndDate':
        return (
          field: field,
          question: '¿Hasta qué fecha estás en Modalidad 40? '
              '(por ejemplo, 31/12/2020)',
          suggestions: const <String>[],
        );
      case 'fechaNacimiento':
        return (
          field: field,
          question: 'Para calcular tu edad y elegibilidad necesito tu fecha '
              'de nacimiento. ¿En qué fecha naciste? (por ejemplo, 05/03/1975)',
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
      case 'umaMultiplier':
        return (
          field: field,
          question: '¿Qué multiplicador de UMA quieres usar para tu salario '
              'en Modalidad 40? (de 1 a 25, por ejemplo 25)',
          suggestions: const <String>['25', '20', '15', '10', '5', '1'],
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
  static Future<({bool ok, List<String> setFields, String? nextField})?>
      applyAnswer(
    RetroactiveProvider provider,
    String field,
    String text,
  ) async {
    switch (field) {
      case 'semanasCotizadas':
        final v = _extractInt(text);
        if (v == null || v <= 0) return null;
        provider.setSemanasCotizadas(v);
        return (ok: true, setFields: ['semanasCotizadas'], nextField: null);

      case 'salarioDiarioPromedio':
        final v = _extractNum(text);
        if (v == null || v <= 0) return null;
        provider.setSalarioDiarioPromedio(v);
        return (
          ok: true,
          setFields: ['salarioDiarioPromedio'],
          nextField: null,
        );

      case 'fechaNacimiento':
        final date = _extractDate(text);
        if (date == null) return null;
        provider.setFechaNacimiento(date);
        return (ok: true, setFields: ['fechaNacimiento'], nextField: null);

      case 'edadRetiro':
        final v = _extractNum(text);
        if (v == null || v < 60 || v > 65) return null;
        await provider.setEdadRetiro(v);
        return (ok: true, setFields: ['edadRetiro'], nextField: null);

      case 'tieneEsposa':
        final lower = text.toLowerCase();
        if (RegExp(r'\bno\b|false|solter|divorci').hasMatch(lower)) {
          provider.setTieneEsposa(false);
          return (ok: true, setFields: ['tieneEsposa'], nextField: null);
        }
        if (RegExp(r's[ií]|true|casad|esposa|c[oó]nyuge').hasMatch(lower)) {
          provider.setTieneEsposa(true);
          return (ok: true, setFields: ['tieneEsposa'], nextField: null);
        }
        return null;

      case 'numeroHijos':
        final v = _extractCount(text);
        if (v == null || v < 0 || v > 20) return null;
        provider.setNumeroHijos(v);
        return (ok: true, setFields: ['numeroHijos'], nextField: null);

      case 'numeroPadres':
        final v = _extractCount(text);
        if (v == null || v < 0 || v > 10) return null;
        provider.setNumeroPadres(v);
        return (ok: true, setFields: ['numeroPadres'], nextField: null);

      case 'umaMultiplier':
        final v = _extractNum(text);
        if (v == null || v < 1 || v > 25) return null;
        provider.setUmaMultiplier(v);
        return (ok: true, setFields: ['umaMultiplier'], nextField: null);

      case 'salarioPromedio250Semanas':
        final v = _extractNum(text);
        if (v == null || v <= 0) return null;
        // El usuario ya conoce su promedio: se colapsa el desglose "antes de
        // Mod40" en un único registro de 250 semanas con ese promedio,
        // conservando los periodos de Modalidad 40.
        provider.setSalarioPromedio250SemanasConDesglose(v);
        return (
          ok: true,
          setFields: ['salarioPromedio250Semanas'],
          nextField: null,
        );

      case 'semanasEnMod40':
        final lower = text.toLowerCase();
        if (RegExp(r'por\s+fechas?|fechas').hasMatch(lower)) {
          // El usuario prefiere capturar las semanas con fecha inicio/fin.
          return (
            ok: true,
            setFields: const <String>[],
            nextField: 'm40StartDate',
          );
        }
        final n = _extractNum(text);
        if (n == null || n < 0) return null;
        provider.setSemanasEnMod40(n);
        return (ok: true, setFields: ['semanasEnMod40'], nextField: null);

      case 'm40StartDate':
        final start = _extractMod40Date(text);
        if (start == null) return null;
        provider.setStartDate(start);
        return (ok: true, setFields: ['startDate'], nextField: 'm40EndDate');

      case 'm40EndDate':
        final end = _extractMod40Date(text);
        if (end == null) return null;
        final dias = end.difference(provider.startDate).inDays;
        if (dias <= 0) return null;
        provider.setEndDate(end);
        provider.setSemanasEnMod40(dias / 7.0);
        return (
          ok: true,
          setFields: ['endDate', 'semanasEnMod40'],
          nextField: null,
        );

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

  /// Fecha en [text] admitiendo dd/mm/aaaa, dd-mm-aaaa, dd.mm.aaaa, aaaa-mm-dd
  /// y nombres de mes en español ("5 de marzo de 1975"). Devuelve `null` si no
  /// se reconoce una fecha válida, en el pasado y con edad plausible (18-100).
  static DateTime? _extractDate(String text) {
    final trimmed = text.trim();

    // aaaa-mm-dd (ISO) PRIMERO: evita que "1975-03-05" se malinterprete como
    // dd/mm/aaaa (el patrón dd/mm leería día 19, mes 75 y rechazaría la fecha).
    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$')
        .firstMatch(trimmed);
    if (iso != null) {
      return _validDate(
        int.tryParse(iso.group(1)!),
        int.tryParse(iso.group(2)!),
        int.tryParse(iso.group(3)!),
      );
    }

    // 8 dígitos sin separadores: se infiere el orden. Si los primeros 4 forman
    // un año plausible (1900-2010) se interpreta como AAAAMMDD (19750305);
    // de lo contrario como DDMMAAAA (30011969 → 30/01/1969).
    final compact = RegExp(r'^(\d{8})$').firstMatch(trimmed);
    if (compact != null) {
      final s = compact.group(1)!;
      final first4 = int.tryParse(s.substring(0, 4));
      if (first4 != null && first4 >= 1900 && first4 <= 2010) {
        // AAAAMMDD
        return _validDate(
          first4,
          int.tryParse(s.substring(4, 6)),
          int.tryParse(s.substring(6, 8)),
        );
      }
      // DDMMAAAA
      return _validDate(
        int.tryParse(s.substring(4, 8)),
        int.tryParse(s.substring(2, 4)),
        int.tryParse(s.substring(0, 2)),
      );
    }

    // dd/mm/aaaa, dd-mm-aaaa, dd.mm.aaaa
    // Los grupos del patrón son (día, mes, año); _validDate espera
    // (año, mes, día), por lo que se reordenan.
    final dmy =
        RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(trimmed);
    if (dmy != null) {
      return _validDate(
        int.tryParse(dmy.group(3)!),
        int.tryParse(dmy.group(2)!),
        int.tryParse(dmy.group(1)!),
      );
    }

    // "5 de marzo de 1975", "5 de Marzo del 1975"
    const months = <String, int>{
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'setiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    final named = RegExp(
      r'(\d{1,2})\s+(?:de\s+)?([a-záéíóúñ]+)(?:\s+de\s+|\s+del\s+)?(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (named != null) {
      final month = months[named.group(2)!.toLowerCase()];
      if (month != null) {
        // Los grupos del patrón son (día, mes, año); _validDate espera
        // (año, mes, día), por lo que se reordenan.
        return _validDate(
          int.tryParse(named.group(3)!),
          month,
          int.tryParse(named.group(1)!),
        );
      }
    }

    return null;
  }

  /// Fecha válida, en el pasado y con edad plausible (18-100), o `null`.
  static DateTime? _validDate(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // DateTime normaliza fechas inválidas (p. ej. 31/02 → 03/03); se verifica
    // que el día y mes coincidan con lo ingresado.
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    final now = DateTime.now();
    if (date.isAfter(now)) return null;
    var age = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      age--;
    }
    if (age < 18 || age > 100) return null;
    return date;
  }

  /// Fecha en [text] para Modalidad 40 (inicio/fin) admitiendo dd/mm/aaaa,
  /// dd-mm-aaaa, dd.mm.aaaa, aaaa-mm-dd y nombres de mes en español
  /// ("5 de marzo de 2010"). A diferencia de [_extractDate] NO impone "en el
  /// pasado" ni "edad 18-100", porque las fechas de M40 pueden ser recientes
  /// (p. ej. 01/01/2020) o apenas anteriores al año en curso.
  static DateTime? _extractMod40Date(String text) {
    final trimmed = text.trim();

    // aaaa-mm-dd (ISO) primero.
    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$')
        .firstMatch(trimmed);
    if (iso != null) {
      return _mod40Date(
        int.tryParse(iso.group(1)!),
        int.tryParse(iso.group(2)!),
        int.tryParse(iso.group(3)!),
      );
    }

    // dd/mm/aaaa, dd-mm-aaaa, dd.mm.aaaa → (año, mes, día).
    final dmy =
        RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(trimmed);
    if (dmy != null) {
      return _mod40Date(
        int.tryParse(dmy.group(3)!),
        int.tryParse(dmy.group(2)!),
        int.tryParse(dmy.group(1)!),
      );
    }

    // "5 de marzo de 2010".
    const months = <String, int>{
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'setiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    final named = RegExp(
      r'(\d{1,2})\s+(?:de\s+)?([a-záéíóúñ]+)(?:\s+de\s+|\s+del\s+)?(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (named != null) {
      final month = months[named.group(2)!.toLowerCase()];
      if (month != null) {
        return _mod40Date(
          int.tryParse(named.group(3)!),
          month,
          int.tryParse(named.group(1)!),
        );
      }
    }

    return null;
  }

  /// Fecha real (no normalizada) para Modalidad 40: entre 1900 y el año
  /// siguiente al actual, o `null` si es imposible o fuera de rango.
  static DateTime? _mod40Date(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // DateTime normaliza fechas inválidas (p. ej. 31/02 → 03/03).
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    final now = DateTime.now();
    if (year < 1900 || date.isAfter(now.add(const Duration(days: 366)))) {
      return null;
    }
    return date;
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
