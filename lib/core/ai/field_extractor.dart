import '../../services/retroactive_provider.dart';
import '../utils/pension_constants.dart';
import 'date_parse.dart';

/// Maps AI-extracted JSON values to [RetroactiveProvider] setters.
///
/// This is the bridge between the AI's structured JSON response
/// and the app's state management. It only sets fields that are
/// present and non-null in the AI response.
///
/// ## Synonym tolerance
/// The AI may return field keys in natural language (e.g. `edad`, `salario`,
/// `hijos`) instead of the exact canonical keys. [applyValues] normalizes
/// every key (lowercase, no accents, no spaces) and resolves it against a
/// synonym table before applying.
///
/// ## Application order (important)
/// Setters that force-project other values MUST run first so that explicitly
/// provided AI values override the projections:
/// - [RetroactiveProvider.setFechaNacimiento] and
///   [RetroactiveProvider.setEdadRetiro] recalculate `pensionYear` and
///   force-project UMA / salario mínimo / salario registrado.
/// - [RetroactiveProvider.setPensionYear] force-projects UMA / SM too.
/// Therefore `fechaNacimiento` → `edadRetiro` → `pensionYear` are applied
/// before `umaDiaria` / `salarioMinimoDiario` / `umaMultiplier` /
/// `salarioRegistrado`, guaranteeing that explicit AI values win over the
/// forced projections.
class FieldExtractor {
  FieldExtractor._();

  /// Apply extracted values from AI JSON to the provider.
  ///
  /// [values] is a `Map<String, dynamic>` from the AI's "values" field.
  /// Only non-null, parseable values are applied. Returns a list of canonical
  /// field names that were successfully set.
  static List<String> applyValues(
    RetroactiveProvider provider,
    Map<String, dynamic> values,
  ) {
    final setFields = <String>[];

    // Resolve synonyms to canonical keys (first non-null value wins).
    final resolved = <String, dynamic>{};
    values.forEach((rawKey, rawValue) {
      final canonical = _resolveKey(rawKey);
      if (canonical == null || rawValue == null) return;
      resolved.putIfAbsent(canonical, () => rawValue);
    });

    // Apply a canonical field only if present AND successfully parsed.
    // The setter returns true when the value was actually applied.
    void apply(String key, bool Function(dynamic) setter) {
      if (!resolved.containsKey(key)) return;
      if (setter(resolved[key]!)) {
        setFields.add(key);
      }
    }

    // ── Force-projection setters FIRST (so later explicit values win) ──
    // Opt-out primero: si la IA entiende que el usuario NO quiere Modalidad 40,
    // los campos de M40 que lleguen después se ignoran.
    apply('modalidad40OptOut', (v) {
      final b = _tryBool(v);
      if (b == null) return false;
      provider.setModalidad40OptOut(b);
      return true;
    });
    apply('fechaNacimiento', (v) {
      final d = _toDate(v);
      if (d == null) return false;
      provider.setFechaNacimiento(d);
      return true;
    });
    apply('fechaAlta', (v) {
      final d = _toDate(v);
      if (d == null) return false;
      // La Ley 73 NO ampara a quien se dio de alta en el IMSS a partir del
      // 1 de julio de 1997: se rechaza la fecha para no dejar avanzar el
      // cálculo con un valor legalmente inválido. Mismo criterio que
      // guided_input.dart y la pestaña Pensión (sin hardcode).
      if (!d.isBefore(PensionConstants.fechaLimiteLey73)) return false;
      provider.setFechaAlta(d);
      return true;
    });
    apply('edadRetiro', (v) {
      final n = _tryDouble(v);
      if (n == null || n <= 0) return false;
      provider.setEdadRetiro(n);
      return true;
    });
    apply('pensionYear', (v) {
      final n = _tryInt(v);
      if (n == null || n <= 0) return false;
      provider.setPensionYear(n);
      return true;
    });

    // ── Explicit UMA / SM / multiplier / registered salary (override) ──
    apply('umaDiaria', (v) {
      final n = _tryDouble(v);
      if (n == null || n <= 0) return false;
      provider.setUmaDiaria(n);
      return true;
    });
    apply('salarioMinimoDiario', (v) {
      final n = _tryDouble(v);
      if (n == null || n <= 0) return false;
      provider.setSalarioMinimoDiario(n);
      return true;
    });
    apply('umaMultiplier', (v) {
      if (provider.modalidad40OptOut) return false;
      final n = _tryDouble(v);
      if (n == null || n <= 0) return false;
      provider.setUmaMultiplier(n);
      return true;
    });
    apply('salarioRegistrado', (v) {
      final n = _tryDouble(v);
      if (n == null || n <= 0) return false;
      provider.setSalarioRegistrado(n);
      return true;
    });

    // ── Salaries ──
    // salarioPromedio250Semanas first: its setter recomputes
    // salarioDiarioPromedio from the periodos, so an explicit
    // salarioDiarioPromedio below must win over that recompute.
    apply('salarioPromedio250Semanas', (v) {
      final n = _tryDouble(v);
      if (n == null || n <= 0) return false;
      provider.setSalarioPromedio250Semanas(n);
      return true;
    });
    apply('salarioDiarioPromedio', (v) {
      final n = _tryDouble(v);
      if (n == null || n <= 0) return false;
      provider.setSalarioDiarioPromedio(n);
      return true;
    });

    // ── Semanas (desglose first, explicit totals after so they win) ──
    apply('semanasAntesMod40', (v) {
      final n = _tryDouble(v);
      if (n == null || n < 0) return false;
      provider.setSemanasAntesMod40(n);
      return true;
    });
    apply('semanasEnMod40', (v) {
      if (provider.modalidad40OptOut) return false;
      final n = _tryDouble(v);
      if (n == null || n < 0) return false;
      provider.setSemanasEnMod40(n);
      return true;
    });
    apply('totalSemanasSinMod40', (v) {
      final n = _tryInt(v);
      if (n == null || n < 0) return false;
      provider.setTotalSemanasSinMod40(n);
      return true;
    });
    apply('semanasCotizadas', (v) {
      final n = _tryInt(v);
      if (n == null || n < 0) return false;
      provider.setSemanasCotizadas(n);
      return true;
    });

    // ── Dependientes ──
    apply('tieneEsposa', (v) {
      final b = _tryBool(v);
      if (b == null) return false;
      provider.setTieneEsposa(b);
      return true;
    });
    apply('numeroHijos', (v) {
      final n = _tryInt(v);
      if (n == null || n < 0) return false;
      provider.setNumeroHijos(n);
      return true;
    });
    apply('numeroPadres', (v) {
      final n = _tryInt(v);
      if (n == null || n < 0) return false;
      provider.setNumeroPadres(n);
      return true;
    });

    // ── Fechas de Modalidad 40 ──
    apply('startDate', (v) {
      if (provider.modalidad40OptOut) return false;
      final d = _toDate(v);
      if (d == null) return false;
      provider.setStartDate(d);
      return true;
    });
    apply('endDate', (v) {
      if (provider.modalidad40OptOut) return false;
      final d = _toDate(v);
      if (d == null) return false;
      provider.setEndDate(d);
      return true;
    });

    // ── Costos / retroactivo / mejoras ──
    apply('costoModalidad40', (v) {
      final n = _tryDouble(v);
      if (n == null || n < 0) return false;
      provider.setCostoModalidad40(n);
      return true;
    });
    apply('retroactiveYears', (v) {
      final n = _tryDouble(v);
      if (n == null || n < 0) return false;
      provider.setRetroactiveYears(n);
      return true;
    });
    apply('pensionMensualMejorada', (v) {
      final n = _tryDouble(v);
      if (n == null || n < 0) return false;
      provider.setPensionMensualMejorada(n);
      return true;
    });
    apply('fechaCalculo', (v) {
      final d = _toDate(v);
      if (d == null) return false;
      provider.setFechaCalculo(d);
      return true;
    });

    return setFields;
  }

  /// If the user's message explicitly asks to change the retirement age to a
  /// specific value (e.g. "mueve la edad de pensión a 62 años", "quiero
  /// pensionarme a los 62 años", "cambia la edad a 61"), returns that age.
  /// Returns `null` when the message does not contain an explicit
  /// retirement-age edit.
  static double? extractRequestedRetirementAge(String text) {
    final normalized = _stripAccents(text.toLowerCase());
    final match = _requestedRetirementAgePattern.firstMatch(normalized);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  /// Corrects the retirement-age value(s) in [values] to the exact number the
  /// user explicitly requested in [userText]. If the user did not explicitly
  /// request an age, returns [values] unchanged.
  ///
  /// Deterministic safety net against the AI model echoing a number from its
  /// prompt example instead of the user's own number (e.g. the model returning
  /// 63 when the user asked for 62), AND against the AI omitting the field
  /// entirely: if [values] has no key that resolves to `edadRetiro`, the
  /// requested age is ADDED so the field always ends with the exact number the
  /// user asked for.
  static Map<String, dynamic> enforceRequestedAge(
    Map<String, dynamic> values,
    String userText,
  ) {
    final requested = extractRequestedRetirementAge(userText);
    if (requested == null) return values;

    final corrected = Map<String, dynamic>.from(values);
    var resolved = false;
    corrected.forEach((rawKey, rawValue) {
      if (_resolveKey(rawKey) == 'edadRetiro') {
        corrected[rawKey] = requested;
        resolved = true;
      }
    });
    // La IA omitió (o mandó null) la edad de retiro → se agrega el número
    // exacto que el usuario pidió.
    if (!resolved) {
      corrected['edadRetiro'] = requested;
    }
    return corrected;
  }

  /// Detect explicit value edits for ANY canonical field, derived entirely
  /// from the [_canonicalAliases] synonym table (no per-field hardcoding).
  ///
  /// Matches both phrasing directions on accent-stripped lowercase text:
  /// - `<campo> ... <conector> <número>` ("mueve la edad de pensión a 62",
  ///   "pon el salario en 500", "cambia las semanas a 1300")
  /// - `<número> <campo>` ("tengo 1300 semanas cotizadas", "pon 1300 semanas")
  ///
  /// Returns `{canonicalField: value}` with `value` as a plain `double`;
  /// [applyValues] performs the per-field type conversion, keeping this
  /// detector fully generic. Boolean (`tieneEsposa`) and date fields have no
  /// numeric target, so they are not detected here (they stay AI-handled).
  static Map<String, dynamic> detectRequestedEdits(String text) {
    final normalized = _stripAccents(text.toLowerCase());

    // Recopila (campo canónico, sinónimo, rango) de TODOS los sinónimos que
    // aparecen en el texto, ordenados del sinónimo más largo al más corto.
    // Así el más específico ("salario diario promedio") gana sobre el genérico
    // ("salario") cuando ambos coinciden, y "semanas en mod 40" gana sobre
    // "semanas".
    final found = <({String canonical, String synonym, int start, int end})>[];
    _canonicalAliases.forEach((synonym, canonical) {
      // Permite espacios entre letras manteniendo límites de palabra
      // (evita que 'uma' case dentro de 'consuma' o 'fin' dentro de 'definir').
      final phrase = synonym.split('').join(r'\s*');
      for (final m in RegExp(
        r'\b(?:' + phrase + r')\b',
      ).allMatches(normalized)) {
        found.add((
          canonical: canonical,
          synonym: synonym,
          start: m.start,
          end: m.end,
        ));
      }
    });
    found.sort((a, b) => b.synonym.length.compareTo(a.synonym.length));

    // Conectores que anuncian el valor objetivo.
    const connectors = r'(?:a\s+los|a|en|hasta|al)';

    // Un solo valor por campo, del sinónimo más específico que no solape a
    // otro ya aceptado.
    final valueFor = <String, dynamic>{};
    final usedRanges = <({int start, int end})>[];
    for (final m in found) {
      final overlaps = usedRanges.any(
        (r) => m.start < r.end && m.end > r.start,
      );
      if (overlaps) continue;
      usedRanges.add((start: m.start, end: m.end));

      // Dirección 1: campo → conector → número. Se toma el ÚLTIMO par
      // "conector + número" tras el campo: "semanas en mod 40 a 1300"
      // → "a 1300" (no "en 40").
      final after = normalized.substring(m.end);
      final valueMatches = RegExp(
        connectors + r'\s*(\d+(?:\.\d+)?)',
      ).allMatches(after).toList();
      if (valueMatches.isNotEmpty) {
        final value = _tryDouble(valueMatches.last.group(1)!);
        if (value != null && value > 0) {
          valueFor[m.canonical] = value;
          continue;
        }
      }

      // Dirección 1b: campo → número directo, sin conector explícito
      // ("semanas cotizadas 1900", "salario 500", "hijos 2"). Es la forma
      // coloquial más común y antes se perdía (dependía de la IA). Se acepta
      // un conector opcional para "semanas cotizadas en 1900".
      final direct = RegExp(
        r'^\s*(?:' + connectors + r'\s*)?(\d+(?:\.\d+)?)',
      ).firstMatch(after);
      if (direct != null) {
        final value = _tryDouble(direct.group(1)!);
        if (value != null && value > 0) {
          valueFor[m.canonical] = value;
          continue;
        }
      }

      // Dirección 2: número → campo ("tengo 1300 semanas cotizadas",
      // "250 en modalidad 40"). Se permite un conector opcional entre el
      // número y el campo ("250 en modalidad 40", "1300 a semanas").
      final before = normalized.substring(0, m.start);
      final beforeMatch = RegExp(
        r'(\d+(?:\.\d+)?)\s*(?:' + connectors + r')?\s*$',
      ).firstMatch(before);
      if (beforeMatch != null) {
        final value = _tryDouble(beforeMatch.group(1)!);
        if (value != null && value > 0) {
          valueFor[m.canonical] = value;
        }
      }
    }

    return valueFor;
  }

  /// Matches explicit retirement-age edit commands in Spanish. The regex runs
  /// on accent-stripped, lowercased text. Triggers: "edad de pensión/retiro/
  /// jubilación", "edad", "pensionar(me)". Requires a connector (a/en/hasta/
  /// al) followed by the age the user explicitly requested.
  static final RegExp _requestedRetirementAgePattern = RegExp(
    r'(?:edad\s+de\s+(?:pension|retiro|jubilacion)|edad\s+de\s+pensionarse|edad|pensionar(?:me)?)'
    r'[^\d]{0,25}?'
    r'(?:a|en|hasta|al)\s+(?:los\s+)?(\d{2}(?:\.\d+)?)'
    r'\s*(?:a\w+os)?',
    caseSensitive: false,
  );

  /// Lowercase-safe accent stripping (mirrors [_normalizeKey] but preserves
  /// word boundaries for full-sentence matching).
  static String _stripAccents(String input) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var s = input;
    accents.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }

  /// Return the raw AI value for a canonical field, resolving synonyms.
  ///
  /// Used by the UI to display what value was applied (e.g. after an edit
  /// instruction), without re-deriving it from the provider state.
  static dynamic valueFor(Map<String, dynamic> values, String canonicalKey) {
    for (final entry in values.entries) {
      if (_resolveKey(entry.key) == canonicalKey) {
        return entry.value;
      }
    }
    return null;
  }

  /// Get a human-readable label for a canonical field name.
  static String fieldLabel(String fieldName) {
    switch (fieldName) {
      case 'fechaNacimiento':
        return 'Fecha de nacimiento';
      case 'fechaAlta':
        return 'Fecha de alta (IMSS)';
      case 'fechaCalculo':
        return 'Fecha de cálculo';
      case 'edadRetiro':
        return 'Edad de retiro (con Modalidad 40)';
      case 'umaDiaria':
        return 'UMA diaria';
      case 'salarioMinimoDiario':
        return 'Salario mínimo diario';
      case 'pensionYear':
        return 'Año de pensión';
      case 'umaMultiplier':
        return 'Multiplicador de UMA';
      case 'salarioRegistrado':
        return 'Salario registrado';
      case 'salarioDiarioPromedio':
        return 'Salario diario promedio';
      case 'salarioPromedio250Semanas':
        return 'Salario promedio 250 semanas';
      case 'semanasCotizadas':
        return 'Semanas cotizadas';
      case 'semanasAntesMod40':
        return 'Semanas antes de Modalidad 40';
      case 'semanasEnMod40':
        return 'Semanas en Modalidad 40';
      case 'totalSemanasSinMod40':
        return 'Total de semanas sin Modalidad 40';
      case 'tieneEsposa':
        return '¿Tiene esposa?';
      case 'numeroHijos':
        return 'Número de hijos';
      case 'numeroPadres':
        return 'Número de padres';
      case 'startDate':
        return 'Fecha de inicio (Modalidad 40)';
      case 'endDate':
        return 'Fecha de término (Modalidad 40)';
      case 'costoModalidad40':
        return 'Costo de Modalidad 40';
      case 'retroactiveYears':
        return 'Años retroactivos';
      case 'pensionMensualMejorada':
        return 'Pensión mensual mejorada';
      default:
        return fieldName;
    }
  }

  /// Resolve a raw AI key to a canonical field name via synonym table.
  ///
  /// Returns `null` for empty keys; unknown keys are passed through unchanged
  /// (they are simply ignored by [applyValues], which only applies a fixed set
  /// of canonical fields).
  static String? _resolveKey(String rawKey) {
    final normalized = _normalizeKey(rawKey);
    if (normalized.isEmpty) return null;
    return _canonicalAliases[normalized] ?? normalized;
  }

  /// Normalize a key: lowercase, strip accents, remove spaces/underscores.
  static String _normalizeKey(String key) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var s = key.toLowerCase();
    accents.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'[\s_\-]'), '');
  }

  /// Synonym table: normalized key → canonical field name.
  static const Map<String, String> _canonicalAliases = {
    // Fechas
    'fechanacimiento': 'fechaNacimiento',
    'fechadenacimiento': 'fechaNacimiento',
    'nacimiento': 'fechaNacimiento',
    'fechanacer': 'fechaNacimiento',
    'fechacalculo': 'fechaCalculo',
    'fechadecalculo': 'fechaCalculo',
    'fechaalta': 'fechaAlta',
    'fechadealta': 'fechaAlta',
    'fechadealtaseguro': 'fechaAlta',
    'fechadealtaimss': 'fechaAlta',
    'alta': 'fechaAlta',
    // Edad de retiro
    'edadretiro': 'edadRetiro',
    'edad': 'edadRetiro',
    'edadpension': 'edadRetiro',
    'edadpensionamiento': 'edadRetiro',
    'edadpensionarse': 'edadRetiro',
    'edadderetiro': 'edadRetiro',
    'edaddejubilacion': 'edadRetiro',
    'edadretirosinmod40': 'edadRetiro',
    'edadretiroconmod40': 'edadRetiro',
    'edadretiroconm40': 'edadRetiro',
    // UMA / Salario mínimo
    'umadiaria': 'umaDiaria',
    'uma': 'umaDiaria',
    'valorumadiario': 'umaDiaria',
    'umamensual': 'umaDiaria',
    'salariominimodiario': 'salarioMinimoDiario',
    'salariominimo': 'salarioMinimoDiario',
    'smdiario': 'salarioMinimoDiario',
    'salariominimogeneral': 'salarioMinimoDiario',
    // Año de pensión
    'pensionyear': 'pensionYear',
    'aniopension': 'pensionYear',
    'aniodepension': 'pensionYear',
    'aniodejubilacion': 'pensionYear',
    // Multiplicador de UMA
    'umamultiplier': 'umaMultiplier',
    'multiplicadoruma': 'umaMultiplier',
    'multiplicadordeuma': 'umaMultiplier',
    'vecesuma': 'umaMultiplier',
    'multiplicador': 'umaMultiplier',
    // "X Umas" (plural) = X veces la UMA → multiplicador. El singular "UMA"
    // (arriba) sigue siendo el valor diario en pesos (umaDiaria).
    'umas': 'umaMultiplier',
    // Salarios
    'salariodiopromedio': 'salarioDiarioPromedio',
    'salariodiariopromedio': 'salarioDiarioPromedio',
    'salariopromediodiario': 'salarioDiarioPromedio',
    'salariopromedio': 'salarioDiarioPromedio',
    'salariodiario': 'salarioDiarioPromedio',
    'salario': 'salarioDiarioPromedio',
    'sueldo': 'salarioDiarioPromedio',
    'salariopromedio250semanas': 'salarioPromedio250Semanas',
    'salarioprom250sem': 'salarioPromedio250Semanas',
    'salario250semanas': 'salarioPromedio250Semanas',
    'promedio250semanas': 'salarioPromedio250Semanas',
    'salarioregistrado': 'salarioRegistrado',
    'salarioregistradom40': 'salarioRegistrado',
    'salariodecotizacion': 'salarioRegistrado',
    'sueldoregistrado': 'salarioRegistrado',
    // Semanas
    'semanascotizadas': 'semanasCotizadas',
    'semanas': 'semanasCotizadas',
    'semanascotizadasimss': 'semanasCotizadas',
    'semanasantesmod40': 'semanasAntesMod40',
    'semanasantemod40': 'semanasAntesMod40',
    'semanasanteriores': 'semanasAntesMod40',
    'semanasantes': 'semanasAntesMod40',
    'semanasenmod40': 'semanasEnMod40',
    'semanasenm40': 'semanasEnMod40',
    'semanasconmod40': 'semanasEnMod40',
    // "250 en modalidad 40" / "250 en mod 40" → semanas en Modalidad 40.
    // El sinónimo más específico ("semanas en mod 40") gana por longitud;
    // "costo modalidad 40" gana por su alias propio (costomodalidad40).
    'modalidad40': 'semanasEnMod40',
    'mod40': 'semanasEnMod40',
    'm40': 'semanasEnMod40',
    // Opt-out Modalidad 40: expresiones de "no quiero / sin Modalidad 40".
    'modalidad40optout': 'modalidad40OptOut',
    'sinmodalidad40': 'modalidad40OptOut',
    'sinmod40': 'modalidad40OptOut',
    'noquieromodalidad40': 'modalidad40OptOut',
    'noquieromod40': 'modalidad40OptOut',
    'nosermod40': 'modalidad40OptOut',
    'totalsemanassinmod40': 'totalSemanasSinMod40',
    'semanassinmod40': 'totalSemanasSinMod40',
    'semanastotalsinmod40': 'totalSemanasSinMod40',
    // Dependientes
    'tieneesposa': 'tieneEsposa',
    'esposa': 'tieneEsposa',
    'casado': 'tieneEsposa',
    'casada': 'tieneEsposa',
    'concubina': 'tieneEsposa',
    'numerohijos': 'numeroHijos',
    'hijos': 'numeroHijos',
    'numerodehijos': 'numeroHijos',
    'numeropadres': 'numeroPadres',
    'numerodepadres': 'numeroPadres',
    'padres': 'numeroPadres',
    'padresdependientes': 'numeroPadres',
    'numerodepadresdependientes': 'numeroPadres',
    // Fechas de Modalidad 40
    'startdate': 'startDate',
    'fechainicio': 'startDate',
    'fechadeinicio': 'startDate',
    'fechainiciom40': 'startDate',
    'inicio': 'startDate',
    'enddate': 'endDate',
    'fechafin': 'endDate',
    'fechadefin': 'endDate',
    'fechatermino': 'endDate',
    'fechadetermino': 'endDate',
    'fin': 'endDate',
    // Costos / retroactivo / mejoras
    'costomodalidad40': 'costoModalidad40',
    'costom40': 'costoModalidad40',
    'costodemodalidad40': 'costoModalidad40',
    'costototal': 'costoModalidad40',
    'retroactiveyears': 'retroactiveYears',
    'anosretroactivos': 'retroactiveYears',
    'anosretroactivo': 'retroactiveYears',
    'retroactivo': 'retroactiveYears',
    'pensionmensualmejorada': 'pensionMensualMejorada',
    'pensionmejorada': 'pensionMensualMejorada',
    'mejorapension': 'pensionMensualMejorada',
  };

  static double? _tryDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _tryInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool? _tryBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final s = value.trim().toLowerCase();
      if (s == 'true' ||
          s == 'si' ||
          s == 'sí' ||
          s == 'verdadero' ||
          s == '1') {
        return true;
      }
      if (s == 'false' || s == 'no' || s == 'falso' || s == '0') {
        return false;
      }
    }
    return null;
  }

  /// Parse a date from common string formats using the SAME parser as the
  /// guided flow ([rawDate] + [isRealDate]): ISO `YYYY-MM-DD`, compact
  /// `AAAAMMDD` / `DDMMAAAA`, `DD-MM-YYYY` / `DD/MM/YYYY` (día primero) y
  /// nombres de mes en español. Returns `null` if the value cannot be parsed.
  static DateTime? _toDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is! String) return null;
    final raw = rawDate(value);
    if (raw == null || !isRealDate(raw.$1, raw.$2, raw.$3)) return null;
    return DateTime(raw.$1!, raw.$2!, raw.$3!);
  }
}
