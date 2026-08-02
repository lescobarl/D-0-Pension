import '../../services/retroactive_provider.dart';

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
    apply('fechaNacimiento', (v) {
      final d = _toDate(v);
      if (d == null) return false;
      provider.setFechaNacimiento(d);
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
      final d = _toDate(v);
      if (d == null) return false;
      provider.setStartDate(d);
      return true;
    });
    apply('endDate', (v) {
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
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
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
      if (s == 'true' || s == 'si' || s == 'sí' || s == 'verdadero' || s == '1') {
        return true;
      }
      if (s == 'false' || s == 'no' || s == 'falso' || s == '0') {
        return false;
      }
    }
    return null;
  }

  /// Parse a date from common string formats: `YYYY-MM-DD`, `YYYY/MM/DD`,
  /// `DD-MM-YYYY`, `DD/MM/YYYY` (Mexican day-first). Returns `null` if the
  /// value cannot be parsed.
  static DateTime? _toDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is! String) return null;
    final s = value.trim();
    if (s.isEmpty) return null;

    // YYYY-MM-DD or YYYY/MM/DD
    var m = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$').firstMatch(s);
    if (m != null) {
      return _buildDate(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    // DD-MM-YYYY or DD/MM/YYYY
    m = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(s);
    if (m != null) {
      return _buildDate(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      );
    }
    return null;
  }

  static DateTime? _buildDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }
}
