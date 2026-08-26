import '../../services/retroactive_provider.dart';
import '../utils/pension_constants.dart';
import 'date_parse.dart';

/// Guía determinista de captura de datos.
///
/// Es LA APP (no la IA) quien decide qué dato falta y pregunta UN dato
/// concreto a la vez, en un orden fijo de prioridad. Así se elimina la
/// pregunta vaga "¿Falta algún dato?" que delegaba en el usuario: en su lugar
/// la app indica exactamente qué debe proporcionar y, cuando el dato admite
/// respuestas cortas, ofrece chips de respuesta rápida.
///
/// ## Orden de prioridad
/// 1. `fechaAlta`                 → clave Ley 73: se pregunta PRIMERO para
///                                  confirmar el régimen antes de capturar
///                                  los datos del cálculo
/// 2. `semanasCotizadas`          → vital: se pregunta SIEMPRE una vez por sesión
/// 3. `salarioPromedio250Semanas` → vital: se pregunta SIEMPRE una vez por sesión
/// 4. `semanasEnMod40`            → vital: se pregunta SIEMPRE una vez por sesión
///                                  (número o "por fechas": inicio/fin)
/// 5. `salarioDiarioPromedio`     → respaldo (solo si sigue en 0)
/// 6. `fechaNacimiento`           → se pregunta una sola vez (clave edad/pensión)
/// 7. `edadRetiro`                → se pregunta una sola vez
/// 8. `tieneEsposa`               → se pregunta una sola vez
/// 9. `numeroHijos`               → se pregunta una sola vez
/// 10. `numeroPadres`             → se pregunta una sola vez
/// 11. `umaMultiplier`            → se pregunta una sola vez (salario Mod40)
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
    // ── Clave Ley 73: la fecha de alta se pregunta PRIMERO, antes que los
    // datos vitales, para confirmar el régimen que ampara el cálculo. Se
    // ignora el valor precargado por defecto: se pregunta una vez por sesión,
    // igual que los datos vitales. ──
    if (!requested.contains('fechaAlta')) {
      return _guideFor('fechaAlta', provider);
    }

    // ── Datos vitales: se preguntan SIEMPRE una vez por sesión, aunque el
    // proveedor ya tenga un valor precargado por defecto (se ignoran los
    // defaults) ──
    for (final field in const [
      'semanasCotizadas',
      'salarioPromedio250Semanas',
      'semanasEnMod40',
      // Multiplicador de UMA: es un dato vital de la aportación voluntaria,
      // se pregunta SIEMPRE (obligatorio) aunque se acepte 0 (sin aportar).
      'umaMultiplier',
    ]) {
      // Opt-out activo: no se pregunta por Modalidad 40 (ni por UMA).
      if (field == 'semanasEnMod40' && provider.modalidad40OptOut) continue;
      if (field == 'umaMultiplier' && provider.modalidad40OptOut) continue;
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
    // `edadRetiro` SÍ se pregunta en la guía: las opciones salen del dropdown
    // de edad de pensión (chips 60-65). Orden según la prioridad documentada.
    for (final field in const [
      'fechaNacimiento',
      'edadRetiro',
      'tieneEsposa',
      'numeroHijos',
      'numeroPadres',
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
          question:
              'Para completar tu cálculo necesito saber: '
              '¿cuántas semanas cotizadas tienes ante el IMSS?',
          suggestions: const <String>[],
        );
      case 'salarioDiarioPromedio':
        return (
          field: field,
          question:
              '¿Cuál es tu salario diario aproximado? '
              '(por ejemplo, \$500)',
          suggestions: const <String>[],
        );
      case 'salarioPromedio250Semanas':
        return (
          field: field,
          question:
              'Para el cálculo necesito tu salario promedio de las '
              'últimas 250 semanas. ¿Cuál es? (por ejemplo, 1300)',
          suggestions: const <String>[],
        );
      case 'semanasEnMod40':
        return (
          field: field,
          question:
              '¿Cuántas semanas planeas cotizar en Modalidad 40? '
              'Responde con un número (por ejemplo, 130).',
          suggestions: const <String>[],
        );
      case 'm40StartDate':
        return (
          field: field,
          question:
              '¿Desde qué fecha estás en Modalidad 40? '
              '(por ejemplo, 2010-01-01)',
          suggestions: const <String>[],
        );
      case 'm40EndDate':
        return (
          field: field,
          question:
              '¿Hasta qué fecha estás en Modalidad 40? '
              '(por ejemplo, 2020-12-31)',
          suggestions: const <String>[],
        );
      case 'fechaNacimiento':
        return (
          field: field,
          question:
              'Para calcular tu edad y elegibilidad necesito tu fecha '
              'de nacimiento. ¿En qué fecha naciste? (por ejemplo, 1975-03-05)',
          suggestions: const <String>[],
        );
      case 'fechaAlta':
        return (
          field: field,
          question:
              'Para confirmar que te ampara la Ley 73 necesito tu fecha '
              'de alta en el IMSS (cuándo empezaste a cotizar). ¿En qué fecha '
              'te diste de alta? (por ejemplo, 1990-06-01)',
          suggestions: const <String>[],
        );
      case 'edadRetiro':
        return (
          field: field,
          question:
              '¿A qué edad quieres pensionarte? '
              'Puede ser entre 60 y 65 años (por ejemplo, 62).',
          suggestions: _edadRetiroSuggestions(provider),
        );
      case 'tieneEsposa':
        return (
          field: field,
          question:
              'Para las asignaciones familiares: '
              '¿tienes esposa o cónyuge?',
          suggestions: const <String>['Sí', 'No'],
        );
      case 'numeroHijos':
        return (
          field: field,
          question: '¿Cuántos hijos tienes?',
          // Incluye "0": el usuario puede no tener hijos.
          suggestions: const <String>['0', '1', '2', '3', '4'],
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
          question:
              '¿Qué multiplicador de UMA quieres usar para tu salario '
              'en Modalidad 40? (de 0 a 25, por ejemplo 25)',
          // Incluye "0": el usuario puede elegir 0 semanas en Modalidad 40.
          suggestions: const <String>['25', '20', '15', '10', '5', '1', '0'],
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
  static ({String field, String question, List<String> suggestions})
  questionFor(RetroactiveProvider provider, String field) =>
      _guideFor(field, provider);

  /// Interpreta y aplica la [text] del usuario como respuesta a la pregunta
  /// guiada de [field].
  ///
  /// Devuelve `null` cuando la respuesta no se pudo interpretar (el llamador
  /// debe volver a preguntar el mismo dato). Devuelve el record con `ok=true`
  /// y la lista de campos aplicados cuando sí se pudo aplicar. El campo
  /// `message` es opcional: cuando el dato requiere un aviso legal (p. ej. la
  /// fecha de alta posterior al límite de la Ley 73) el llamador lo muestra
  /// como confirmación; si es `null`, el llamador genera su propia
  /// confirmación a partir de [setFields].
  static Future<
    ({bool ok, List<String> setFields, String? nextField, String? message})?
  >
  applyAnswer(RetroactiveProvider provider, String field, String text) async {
    switch (field) {
      case 'semanasCotizadas':
        final v = _extractInt(text);
        if (v == null || v <= 0) return null;
        provider.setSemanasCotizadas(v);
        return (
          ok: true,
          setFields: ['semanasCotizadas'],
          nextField: null,
          message: null,
        );

      case 'salarioDiarioPromedio':
        final v = _extractNum(text);
        if (v == null || v <= 0) return null;
        provider.setSalarioDiarioPromedio(v);
        return (
          ok: true,
          setFields: ['salarioDiarioPromedio'],
          nextField: null,
          message: null,
        );

      case 'fechaNacimiento':
        final date = _extractDate(text);
        if (date == null) return null;
        provider.setFechaNacimiento(date);
        return (
          ok: true,
          setFields: ['fechaNacimiento'],
          nextField: null,
          message: null,
        );

      case 'fechaAlta':
        // La fecha de alta puede ser reciente y no debe cumplir la restricción
        // de edad 18-100 (p. ej. alguien pudo darse de alta a los 70+ años), por
        // lo que reutilizamos el parser "Modalidad 40" (sin límite de edad).
        final date = _extractMod40Date(text);
        if (date == null) return null;
        // Fecha de alta posterior o igual al 1 de julio de 1997: el régimen de
        // la Ley 1973 no ampara. NO se guarda la fecha y se devuelve `ok:false`
        // para que el flujo guiado NO avance ni marque ¡Listo!, y vuelva a
        // preguntar el mismo dato con el mensaje legal (patrón
        // ley73BlockingMessage: NO se debe avanzar).
        if (!date.isBefore(PensionConstants.fechaLimiteLey73)) {
          return (
            ok: false,
            setFields: const <String>[],
            nextField: null,
            message: PensionConstants.errorLey73FechaAltaPosterior,
          );
        }
        provider.setFechaAlta(date);
        return (
          ok: true,
          setFields: ['fechaAlta'],
          nextField: null,
          message: null,
        );

      case 'edadRetiro':
        final v = _extractNum(text);
        if (v == null || v < 60 || v > 65) return null;
        await provider.setEdadRetiro(v);
        return (
          ok: true,
          setFields: ['edadRetiro'],
          nextField: null,
          message: null,
        );

      case 'tieneEsposa':
        final lower = text.toLowerCase();
        if (RegExp(r'\bno\b|false|solter|divorci').hasMatch(lower)) {
          provider.setTieneEsposa(false);
          return (
            ok: true,
            setFields: ['tieneEsposa'],
            nextField: null,
            message: null,
          );
        }
        if (RegExp(r's[ií]|true|casad|esposa|c[oó]nyuge').hasMatch(lower)) {
          provider.setTieneEsposa(true);
          return (
            ok: true,
            setFields: ['tieneEsposa'],
            nextField: null,
            message: null,
          );
        }
        return null;

      case 'numeroHijos':
        final v = _extractCount(text);
        if (v == null || v < 0 || v > 20) return null;
        provider.setNumeroHijos(v);
        return (
          ok: true,
          setFields: ['numeroHijos'],
          nextField: null,
          message: null,
        );

      case 'numeroPadres':
        final v = _extractCount(text);
        if (v == null || v < 0 || v > 10) return null;
        provider.setNumeroPadres(v);
        return (
          ok: true,
          setFields: ['numeroPadres'],
          nextField: null,
          message: null,
        );

      case 'umaMultiplier':
        final v = _extractNum(text);
        // Acepta 0 (igual que semanasEnMod40): el usuario puede indicar que no
        // aportará, pero el campo es obligatorio (la guía no avanza sin él).
        if (v == null || v < 0 || v > 25) return null;
        provider.setUmaMultiplier(v);
        return (
          ok: true,
          setFields: ['umaMultiplier'],
          nextField: null,
          message: null,
        );

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
          message: null,
        );

      case 'semanasEnMod40':
        if (provider.modalidad40OptOut) {
          // Opt-out activo: se ignora la respuesta y se avanza sin M40.
          return (
            ok: true,
            setFields: const <String>[],
            nextField: null,
            message: null,
          );
        }
        final lower = text.toLowerCase();
        if (RegExp(r'por\s+fechas?|fechas').hasMatch(lower)) {
          // El usuario prefiere capturar las semanas con fecha inicio/fin.
          return (
            ok: true,
            setFields: const <String>[],
            nextField: 'm40StartDate',
            message: null,
          );
        }
        final n = _extractNum(text);
        if (n == null || n < 0) return null;
        provider.setSemanasEnMod40(n);
        return (
          ok: true,
          setFields: ['semanasEnMod40'],
          nextField: null,
          message: null,
        );

      case 'm40StartDate':
        if (provider.modalidad40OptOut) {
          return (
            ok: true,
            setFields: const <String>[],
            nextField: null,
            message: null,
          );
        }
        final start = _extractMod40Date(text);
        if (start == null) return null;
        provider.setStartDate(start);
        return (
          ok: true,
          setFields: ['startDate'],
          nextField: 'm40EndDate',
          message: null,
        );

      case 'm40EndDate':
        if (provider.modalidad40OptOut) {
          return (
            ok: true,
            setFields: const <String>[],
            nextField: null,
            message: null,
          );
        }
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
          message: null,
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
    final raw = rawDate(text);
    if (raw == null) return null;
    return _validDate(raw.$1, raw.$2, raw.$3);
  }

  /// Fecha válida, en el pasado y con edad plausible (18-100), o `null`.
  static DateTime? _validDate(int? year, int? month, int? day) {
    // isRealDate rechaza componentes nulos y fechas normalizadas (31/02).
    if (!isRealDate(year, month, day)) return null;
    final y = year!;
    final m = month!;
    final d = day!;
    final date = DateTime(y, m, d);
    final now = DateTime.now();
    if (date.isAfter(now)) return null;
    var age = now.year - y;
    if (now.month < m || (now.month == m && now.day < d)) {
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
    final raw = rawDate(text);
    if (raw == null) return null;
    return _mod40Date(raw.$1, raw.$2, raw.$3);
  }

  /// Fecha real (no normalizada) para Modalidad 40: entre 1900 y el año
  /// siguiente al actual, o `null` si es imposible o fuera de rango.
  static DateTime? _mod40Date(int? year, int? month, int? day) {
    // isRealDate rechaza componentes nulos y fechas normalizadas (31/02).
    if (!isRealDate(year, month, day)) return null;
    final y = year!;
    final date = DateTime(y, month!, day!);
    final now = DateTime.now();
    if (y < 1900 || date.isAfter(now.add(const Duration(days: 366)))) {
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
