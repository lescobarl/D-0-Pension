import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/periodo_salarial.dart';
import '../core/utils/pii_cipher.dart';

/// Service for persisting user input data locally using SharedPreferences.
///
/// Implements the Repository pattern to abstract storage away from business logic.
/// Default values are provided by the caller (from metadata) rather than hardcoded.
///
/// Datos personales (PII) — fechas de nacimiento/cálculo, salarios, periodos
/// salariales, composición familiar y edad de retiro — se guardan ofuscados en
/// reposo mediante [PiiCipher] (base64 + XOR, ver `KEY-PII-OFUSCACION.txt`).
/// Los valores de configuración no personales se mantienen como tipos nativos.
class PersistenceService {
  static const _keyRetroactiveYears = 'retroactive_years';
  static const _keyCostoModalidad40 = 'costo_modalidad_40';
  static const _keySalarioDiario = 'salario_diario';
  static const _keyStartDateYear = 'start_date_year';
  static const _keyStartDateMonth = 'start_date_month';
  static const _keyEndDateYear = 'end_date_year';
  static const _keyEndDateMonth = 'end_date_month';
  static const _keyPensionYear = 'pension_year';
  static const _keyUmaDiaria = 'uma_diaria';
  static const _keySalarioMinimoDiario = 'salario_minimo_diario';

  // ── NEW: Fields that were missing persistence ──
  static const _keySalarioDiarioPromedio = 'salario_diario_promedio';
  static const _keySemanasCotizadas = 'semanas_cotizadas';
  static const _keyTieneEsposa = 'tiene_esposa';
  static const _keyNumeroHijos = 'numero_hijos';
  static const _keyNumeroPadres = 'numero_padres';
  static const _keyEdadRetiro = 'edad_retiro';
  static const _keySalarioRegistrado = 'salario_registrado';
  static const _keyUmaMultiplier = 'uma_multiplier';
  static const _keyParticipacionBancoMax = 'participacion_banco_max';
  static const _keyPensionMensualMejorada = 'pension_mensual_mejorada';

  // Version marker for data format. When bumped, the version stamp is updated
  // but EXISTING user data is NEVER discarded — it is always preserved.
  // v7: defaults updated to match current Excel scenario (61.5 years, 130.29 sem M40, $2897.17)
  // v8: edad_retiro default changed from 61.5 to 61.51 to match dropdown values (60, 60.51, 61, 61.51, ...)
  // v9: hardcoded age range/thresholds in captura_view/formula_evaluator moved
  //     to app_metadata.json (pension_age_dropdown, edad_rounding_rule).
  // v10: fraccion_threshold unified to 0.51 (both con/sin Mod40 dropdowns).
  //      Old persisted values like 60.5, 61.5 are no longer valid.
  // v11: default_values in app_metadata.json changed from person-specific
  //      (ESCOBAR LOPEZ LUIS ADAN) to generic/common defaults.
  // v12: pre-PII-obfuscation data format (plain native types).
  // v13: PII fields (fechas, salarios, periodos, familia, edad) are stored
  //      obfuscated at rest via PiiCipher; legacy plaintext values are
  //      re-written in the obfuscated format — data preserved, never discarded.
  static const _kDataVersion = 13;
  static const _keyDataVersion = 'data_version';

  // ── DATOS GEN. persistence keys ──
  static const _keyFechaCalculoYear = 'fecha_calculo_year';
  static const _keyFechaCalculoMonth = 'fecha_calculo_month';
  static const _keyFechaCalculoDay = 'fecha_calculo_day';
  static const _keyFechaNacimientoYear = 'fecha_nacimiento_year';
  static const _keyFechaNacimientoMonth = 'fecha_nacimiento_month';
  static const _keyFechaNacimientoDay = 'fecha_nacimiento_day';
  static const _keyEdadMinimaPension = 'edad_minima_pension';
  static const _keySemanasDescontadasAfore = 'semanas_descontadas_afore';
  static const _keySalarioPromedio250Semanas = 'salario_promedio_250_semanas';
  static const _keyTotalSemanasSinMod40 = 'total_semanas_sin_mod40';
  static const _keySemanasAntesMod40 = 'semanas_antes_mod40';
  static const _keySemanasEnMod40 = 'semanas_en_mod40';

  // ── PII keys obfuscated at rest (v13+) ──
  // Keys that hold personal numeric data (doubles and ints).
  static const List<String> _piiNumericKeys = [
    _keySalarioDiario,
    _keyStartDateYear,
    _keyStartDateMonth,
    _keyEndDateYear,
    _keyEndDateMonth,
    _keySalarioMinimoDiario,
    _keySalarioDiarioPromedio,
    _keyEdadRetiro,
    _keySalarioRegistrado,
    _keyFechaCalculoYear,
    _keyFechaCalculoMonth,
    _keyFechaCalculoDay,
    _keyFechaNacimientoYear,
    _keyFechaNacimientoMonth,
    _keyFechaNacimientoDay,
    _keySalarioPromedio250Semanas,
    _keyNumeroHijos,
    _keyNumeroPadres,
  ];

  // Keys that hold personal boolean data.
  static const List<String> _piiBoolKeys = [
    _keyTieneEsposa,
  ];

  static const _keyPeriodos = 'periodos_salariales';

  final SharedPreferences _prefs;

  PersistenceService(this._prefs) {
    _migrateIfNeeded();
  }

  /// If the persisted data version doesn't match the current version,
  /// update the version stamp but PRESERVE all existing data.
  /// Data is only lost if the user explicitly clears it or on first install.
  void _migrateIfNeeded() {
    final stored = _prefs.getInt(_keyDataVersion);
    if (stored != _kDataVersion) {
      debugPrint('[PERSIST] Data version mismatch: stored=$stored, expected=$_kDataVersion — updating version, preserving data');
      _prefs.setInt(_keyDataVersion, _kDataVersion);
      _encryptLegacyPii();
    }
  }

  /// v13 migration: rewrites legacy plaintext PII values into the obfuscated
  /// format. Legacy formats are native double/int/bool (numeric/date/family
  /// fields) and a plain JSON string (periodos, which starts with '[').
  /// Already-obfuscated values are left untouched — the operation is
  /// idempotent and never discards data.
  void _encryptLegacyPii() {
    for (final key in _piiNumericKeys) {
      final raw = _prefs.get(key);
      if (raw == null) continue;
      if (raw is double) {
        _prefs.setString(key, PiiCipher.encodeDouble(raw));
      } else if (raw is int) {
        _prefs.setString(key, PiiCipher.encodeInt(raw));
      }
    }
    for (final key in _piiBoolKeys) {
      final raw = _prefs.get(key);
      if (raw is bool) {
        _prefs.setString(key, PiiCipher.encodeBool(raw));
      }
    }
    final rawPeriodos = _prefs.get(_keyPeriodos);
    if (rawPeriodos is String &&
        rawPeriodos.isNotEmpty &&
        rawPeriodos.startsWith('[')) {
      _prefs.setString(_keyPeriodos, PiiCipher.encode(rawPeriodos));
    }
  }

  /// Safely load a double value, returning [defaultValue] if the stored
  /// value is missing or of a different type (e.g. int stored by older versions).
  double _safeGetDouble(String key, double defaultValue) {
    try {
      final val = _prefs.get(key);
      if (val == null) return defaultValue;
      if (val is double) return val;
      if (val is int) return val.toDouble();
      // Fallback: try getDouble anyway
      return _prefs.getDouble(key) ?? defaultValue;
    } catch (e) {
      debugPrint('[PERSIST] Error reading double key=$key: $e — using default=$defaultValue');
      return defaultValue;
    }
  }

  /// Safely load an obfuscated double (PII). Transparently accepts legacy
  /// plaintext (native double/int from versions <= 12) and v13+ obfuscated
  /// strings. Returns [defaultValue] when the value is missing or corrupt.
  double _safeGetEncryptedDouble(String key, double defaultValue) {
    try {
      final raw = _prefs.get(key);
      if (raw == null) return defaultValue;
      if (raw is double) return raw; // legacy plain
      if (raw is int) return raw.toDouble(); // legacy plain
      if (raw is String) return PiiCipher.decodeDouble(raw); // v13+ obfuscated
      return defaultValue;
    } catch (e) {
      debugPrint('[PERSIST] Error reading obfuscated double key=$key: $e — using default=$defaultValue');
      return defaultValue;
    }
  }

  /// Safely load an obfuscated int (PII). Accepts legacy plaintext and v13+
  /// obfuscated strings. Returns [defaultValue] when missing or corrupt.
  int _safeGetEncryptedInt(String key, int defaultValue) {
    try {
      final raw = _prefs.get(key);
      if (raw == null) return defaultValue;
      if (raw is int) return raw; // legacy plain
      if (raw is double) return raw.toInt(); // legacy plain
      if (raw is String) return PiiCipher.decodeInt(raw); // v13+ obfuscated
      return defaultValue;
    } catch (e) {
      debugPrint('[PERSIST] Error reading obfuscated int key=$key: $e — using default=$defaultValue');
      return defaultValue;
    }
  }

  /// Safely load an obfuscated bool (PII). Accepts legacy plaintext and v13+
  /// obfuscated strings. Returns [defaultValue] when missing or corrupt.
  bool _safeGetEncryptedBool(String key, bool defaultValue) {
    try {
      final raw = _prefs.get(key);
      if (raw == null) return defaultValue;
      if (raw is bool) return raw; // legacy plain
      if (raw is String) return PiiCipher.decodeBool(raw); // v13+ obfuscated
      return defaultValue;
    } catch (e) {
      debugPrint('[PERSIST] Error reading obfuscated bool key=$key: $e — using default=$defaultValue');
      return defaultValue;
    }
  }

  /// Returns true if any persisted data exists (i.e. user has saved before).
  bool hasAnyData() {
    // The data version key is always set after migration, so check a real field.
    return _prefs.containsKey(_keySalarioDiarioPromedio);
  }

  /// Clears all persisted data and re-applies the data version stamp.
  Future<void> clearAll() async {
    await _prefs.clear();
    await _prefs.setInt(_keyDataVersion, _kDataVersion);
  }

  /// Save retroactive years value.
  Future<void> saveRetroactiveYears(double years) async {
    await _prefs.setDouble(_keyRetroactiveYears, years);
  }

  /// Load retroactive years value. Returns [defaultValue] if no saved value.
  double loadRetroactiveYears({required double defaultValue}) {
    return _safeGetDouble(_keyRetroactiveYears, defaultValue);
  }

  /// Save costo modalidad 40.
  Future<void> saveCostoModalidad40(double costo) async {
    await _prefs.setDouble(_keyCostoModalidad40, costo);
  }

  /// Load costo modalidad 40. Returns [defaultValue] if no saved value.
  double loadCostoModalidad40({required double defaultValue}) {
    return _safeGetDouble(_keyCostoModalidad40, defaultValue);
  }

  /// Save salario diario (obfuscated at rest — PII).
  Future<void> saveSalarioDiario(double salario) async {
    await _prefs.setString(_keySalarioDiario, PiiCipher.encodeDouble(salario));
  }

  /// Load salario diario. Returns [defaultValue] if no saved value.
  double loadSalarioDiario({required double defaultValue}) {
    return _safeGetEncryptedDouble(_keySalarioDiario, defaultValue);
  }

  /// Save start date (obfuscated at rest — PII).
  Future<void> saveStartDate(DateTime date) async {
    await _prefs.setString(_keyStartDateYear, PiiCipher.encodeInt(date.year));
    await _prefs.setString(_keyStartDateMonth, PiiCipher.encodeInt(date.month));
  }

  /// Load start date. Returns [defaultValue] if no saved value.
  DateTime loadStartDate({required DateTime defaultValue}) {
    if (!_prefs.containsKey(_keyStartDateYear) ||
        !_prefs.containsKey(_keyStartDateMonth)) {
      return defaultValue;
    }
    final year = _safeGetEncryptedInt(_keyStartDateYear, defaultValue.year);
    final month = _safeGetEncryptedInt(_keyStartDateMonth, defaultValue.month);
    return DateTime(year, month, 1);
  }

  /// Save end date (obfuscated at rest — PII).
  Future<void> saveEndDate(DateTime date) async {
    await _prefs.setString(_keyEndDateYear, PiiCipher.encodeInt(date.year));
    await _prefs.setString(_keyEndDateMonth, PiiCipher.encodeInt(date.month));
  }

  /// Load end date. Returns [defaultValue] if no saved value.
  DateTime loadEndDate({required DateTime defaultValue}) {
    if (!_prefs.containsKey(_keyEndDateYear) ||
        !_prefs.containsKey(_keyEndDateMonth)) {
      return defaultValue;
    }
    final year = _safeGetEncryptedInt(_keyEndDateYear, defaultValue.year);
    final month = _safeGetEncryptedInt(_keyEndDateMonth, defaultValue.month);
    return DateTime(year, month, 31);
  }

  /// Save pension year.
  Future<void> savePensionYear(int year) async {
    await _prefs.setInt(_keyPensionYear, year);
  }

  /// Load pension year. Returns [defaultValue] if no saved value.
  int loadPensionYear({required int defaultValue}) {
    return _prefs.getInt(_keyPensionYear) ?? defaultValue;
  }

  /// Save UMA diaria.
  Future<void> saveUmaDiaria(double value) async {
    await _prefs.setDouble(_keyUmaDiaria, value);
  }

  /// Load UMA diaria. Returns [defaultValue] if no saved value.
  double loadUmaDiaria({required double defaultValue}) {
    return _safeGetDouble(_keyUmaDiaria, defaultValue);
  }

  /// Save salario minimo diario (obfuscated at rest — PII).
  Future<void> saveSalarioMinimoDiario(double value) async {
    await _prefs.setString(
        _keySalarioMinimoDiario, PiiCipher.encodeDouble(value));
  }

  /// Load salario minimo diario. Returns [defaultValue] if no saved value.
  double loadSalarioMinimoDiario({required double defaultValue}) {
    return _safeGetEncryptedDouble(_keySalarioMinimoDiario, defaultValue);
  }

  // ═══════════════════════════════════════════════
  // NEW: Persistence for previously missing fields
  // ═══════════════════════════════════════════════

  /// Save salario diario promedio (obfuscated at rest — PII).
  Future<void> saveSalarioDiarioPromedio(double value) async {
    await _prefs.setString(
        _keySalarioDiarioPromedio, PiiCipher.encodeDouble(value));
  }

  /// Load salario diario promedio. Returns [defaultValue] if no saved value.
  double loadSalarioDiarioPromedio({required double defaultValue}) {
    return _safeGetEncryptedDouble(_keySalarioDiarioPromedio, defaultValue);
  }

  /// Save semanas cotizadas.
  Future<void> saveSemanasCotizadas(int value) async {
    await _prefs.setInt(_keySemanasCotizadas, value);
  }

  /// Load semanas cotizadas. Returns [defaultValue] if no saved value.
  int loadSemanasCotizadas({required int defaultValue}) {
    return _prefs.getInt(_keySemanasCotizadas) ?? defaultValue;
  }

  /// Save tiene esposa (obfuscated at rest — PII).
  Future<void> saveTieneEsposa(bool value) async {
    await _prefs.setString(_keyTieneEsposa, PiiCipher.encodeBool(value));
  }

  /// Load tiene esposa. Returns [defaultValue] if no saved value.
  bool loadTieneEsposa({required bool defaultValue}) {
    return _safeGetEncryptedBool(_keyTieneEsposa, defaultValue);
  }

  /// Save numero de hijos (obfuscated at rest — PII).
  Future<void> saveNumeroHijos(int value) async {
    await _prefs.setString(_keyNumeroHijos, PiiCipher.encodeInt(value));
  }

  /// Load numero de hijos. Returns [defaultValue] if no saved value.
  int loadNumeroHijos({required int defaultValue}) {
    return _safeGetEncryptedInt(_keyNumeroHijos, defaultValue);
  }

  /// Save numero de padres (obfuscated at rest — PII).
  Future<void> saveNumeroPadres(int value) async {
    await _prefs.setString(_keyNumeroPadres, PiiCipher.encodeInt(value));
  }

  /// Load numero de padres. Returns [defaultValue] if no saved value.
  int loadNumeroPadres({required int defaultValue}) {
    return _safeGetEncryptedInt(_keyNumeroPadres, defaultValue);
  }

  /// Save edad de retiro (obfuscated at rest — PII, derivada de la fecha de
  /// nacimiento; unified: con M40 and sin M40 use the same value).
  Future<void> saveEdadRetiro(double value) async {
    await _prefs.setString(_keyEdadRetiro, PiiCipher.encodeDouble(value));
  }

  /// Load edad de retiro. Returns [defaultValue] if no saved value.
  double loadEdadRetiro({required double defaultValue}) {
    return _safeGetEncryptedDouble(_keyEdadRetiro, defaultValue);
  }

  /// Save salario registrado (obfuscated at rest — PII).
  Future<void> saveSalarioRegistrado(double value) async {
    await _prefs.setString(_keySalarioRegistrado, PiiCipher.encodeDouble(value));
  }

  /// Load salario registrado. Returns [defaultValue] if no saved value.
  double loadSalarioRegistrado({required double defaultValue}) {
    return _safeGetEncryptedDouble(_keySalarioRegistrado, defaultValue);
  }

  /// Save participacion banco max.
  Future<void> saveParticipacionBancoMax(double value) async {
    await _prefs.setDouble(_keyParticipacionBancoMax, value);
  }

  /// Load participacion banco max. Returns [defaultValue] if no saved value.
  double loadParticipacionBancoMax({required double defaultValue}) {
    return _safeGetDouble(_keyParticipacionBancoMax, defaultValue);
  }

  /// Save pension mensual mejorada.
  Future<void> savePensionMensualMejorada(double value) async {
    await _prefs.setDouble(_keyPensionMensualMejorada, value);
  }

  /// Load pension mensual mejorada. Returns [defaultValue] if no saved value.
  double loadPensionMensualMejorada({required double defaultValue}) {
    return _safeGetDouble(_keyPensionMensualMejorada, defaultValue);
  }

  /// Save semanas antes Mod40.
  Future<void> saveSemanasAntesMod40(double value) async {
    await _prefs.setDouble(_keySemanasAntesMod40, value);
  }

  /// Load semanas antes Mod40. Returns [defaultValue] if no saved value.
  double loadSemanasAntesMod40({required double defaultValue}) {
    return _safeGetDouble(_keySemanasAntesMod40, defaultValue);
  }

  /// Save semanas en Mod40.
  Future<void> saveSemanasEnMod40(double value) async {
    await _prefs.setDouble(_keySemanasEnMod40, value);
  }

  /// Load semanas en Mod40. Returns [defaultValue] if no saved value.
  double loadSemanasEnMod40({required double defaultValue}) {
    return _safeGetDouble(_keySemanasEnMod40, defaultValue);
  }

  /// Save UMA multiplier (1-25, default 25).
  Future<void> saveUmaMultiplier(double value) async {
    await _prefs.setDouble(_keyUmaMultiplier, value);
  }

  /// Load UMA multiplier. Returns [defaultValue] if no saved value.
  double loadUmaMultiplier({required double defaultValue}) {
    return _safeGetDouble(_keyUmaMultiplier, defaultValue);
  }

  // ═══════════════════════════════════════════════
  // DATOS GEN. persistence
  // ═══════════════════════════════════════════════

  /// Save fecha de cálculo (obfuscated at rest — PII).
  Future<void> saveFechaCalculo(DateTime value) async {
    await _prefs.setString(_keyFechaCalculoYear, PiiCipher.encodeInt(value.year));
    await _prefs.setString(
        _keyFechaCalculoMonth, PiiCipher.encodeInt(value.month));
    await _prefs.setString(_keyFechaCalculoDay, PiiCipher.encodeInt(value.day));
  }

  /// Load fecha de cálculo. Returns [defaultValue] if no saved value.
  DateTime loadFechaCalculo({required DateTime defaultValue}) {
    if (!_prefs.containsKey(_keyFechaCalculoYear) ||
        !_prefs.containsKey(_keyFechaCalculoMonth) ||
        !_prefs.containsKey(_keyFechaCalculoDay)) {
      return defaultValue;
    }
    final year = _safeGetEncryptedInt(_keyFechaCalculoYear, defaultValue.year);
    final month =
        _safeGetEncryptedInt(_keyFechaCalculoMonth, defaultValue.month);
    final day = _safeGetEncryptedInt(_keyFechaCalculoDay, defaultValue.day);
    return DateTime(year, month, day);
  }

  /// Save fecha de nacimiento (obfuscated at rest — PII).
  Future<void> saveFechaNacimiento(DateTime value) async {
    await _prefs.setString(
        _keyFechaNacimientoYear, PiiCipher.encodeInt(value.year));
    await _prefs.setString(
        _keyFechaNacimientoMonth, PiiCipher.encodeInt(value.month));
    await _prefs.setString(
        _keyFechaNacimientoDay, PiiCipher.encodeInt(value.day));
  }

  /// Load fecha de nacimiento. Returns [defaultValue] if no saved value.
  DateTime loadFechaNacimiento({required DateTime defaultValue}) {
    if (!_prefs.containsKey(_keyFechaNacimientoYear) ||
        !_prefs.containsKey(_keyFechaNacimientoMonth) ||
        !_prefs.containsKey(_keyFechaNacimientoDay)) {
      return defaultValue;
    }
    final year =
        _safeGetEncryptedInt(_keyFechaNacimientoYear, defaultValue.year);
    final month =
        _safeGetEncryptedInt(_keyFechaNacimientoMonth, defaultValue.month);
    final day = _safeGetEncryptedInt(_keyFechaNacimientoDay, defaultValue.day);
    return DateTime(year, month, day);
  }

  /// Save edad mínima pensión.
  Future<void> saveEdadMinimaPension(int value) async {
    await _prefs.setInt(_keyEdadMinimaPension, value);
  }

  /// Load edad mínima pensión. Returns [defaultValue] if no saved value.
  int loadEdadMinimaPension({required int defaultValue}) {
    return _prefs.getInt(_keyEdadMinimaPension) ?? defaultValue;
  }

  /// Save semanas descontadas AFORE.
  Future<void> saveSemanasDescontadasAfore(int value) async {
    await _prefs.setInt(_keySemanasDescontadasAfore, value);
  }

  /// Load semanas descontadas AFORE. Returns [defaultValue] if no saved value.
  int loadSemanasDescontadasAfore({required int defaultValue}) {
    return _prefs.getInt(_keySemanasDescontadasAfore) ?? defaultValue;
  }

  /// Save salario promedio 250 semanas (obfuscated at rest — PII).
  Future<void> saveSalarioPromedio250Semanas(double value) async {
    await _prefs.setString(
        _keySalarioPromedio250Semanas, PiiCipher.encodeDouble(value));
  }

  /// Load salario promedio 250 semanas. Returns [defaultValue] if no saved value.
  double loadSalarioPromedio250Semanas({required double defaultValue}) {
    return _safeGetEncryptedDouble(_keySalarioPromedio250Semanas, defaultValue);
  }

  /// Save total semanas sin Mod40.
  Future<void> saveTotalSemanasSinMod40(int value) async {
    await _prefs.setInt(_keyTotalSemanasSinMod40, value);
  }

  /// Load total semanas sin Mod40. Returns [defaultValue] if no saved value.
  int loadTotalSemanasSinMod40({required int defaultValue}) {
    return _prefs.getInt(_keyTotalSemanasSinMod40) ?? defaultValue;
  }

  // ═══════════════════════════════════════════════
  // PERIODOS SALARIALES (SAL. PROM MOD 40 desglose)
  // ═══════════════════════════════════════════════

  /// Save the list of salary periods as an obfuscated JSON string (PII).
  Future<void> savePeriodos(List<PeriodoSalarial> periodos) async {
    final jsonList = periodos.map((p) => p.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await _prefs.setString(_keyPeriodos, PiiCipher.encode(jsonString));
  }

  /// Load the list of salary periods from an obfuscated JSON string.
  /// Transparently accepts legacy plain JSON (versions <= 12) and v13+
  /// obfuscated strings. Returns an empty list if no saved data or on corruption.
  List<PeriodoSalarial> loadPeriodos() {
    final raw = _prefs.get(_keyPeriodos);
    if (raw == null) return [];

    String jsonString;
    if (raw is String && raw.startsWith('[')) {
      jsonString = raw; // legacy plain JSON
    } else if (raw is String) {
      try {
        jsonString = PiiCipher.decode(raw); // v13+ obfuscated
      } catch (e) {
        debugPrint('[PERSIST] Error decoding periodos: $e — returning empty list');
        return [];
      }
    } else {
      jsonString = raw.toString();
    }

    if (jsonString.isEmpty) return [];
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((e) => PeriodoSalarial.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[PERSIST] Error loading periodos: $e — returning empty list');
      return [];
    }
  }
}
