import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/periodo_salarial.dart';

/// Service for persisting user input data locally using SharedPreferences.
///
/// Implements the Repository pattern to abstract storage away from business logic.
/// Default values are provided by the caller (from metadata) rather than hardcoded.
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
  static const _kDataVersion = 12;
  static const _keyDataVersion = 'data_version';

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

  /// Save salario diario.
  Future<void> saveSalarioDiario(double salario) async {
    await _prefs.setDouble(_keySalarioDiario, salario);
  }

  /// Load salario diario. Returns [defaultValue] if no saved value.
  double loadSalarioDiario({required double defaultValue}) {
    return _safeGetDouble(_keySalarioDiario, defaultValue);
  }

  /// Save start date.
  Future<void> saveStartDate(DateTime date) async {
    await _prefs.setInt(_keyStartDateYear, date.year);
    await _prefs.setInt(_keyStartDateMonth, date.month);
  }

  /// Load start date. Returns [defaultValue] if no saved value.
  DateTime loadStartDate({required DateTime defaultValue}) {
    final year = _prefs.getInt(_keyStartDateYear);
    final month = _prefs.getInt(_keyStartDateMonth);
    if (year == null || month == null) {
      return defaultValue;
    }
    return DateTime(year, month, 1);
  }

  /// Save end date.
  Future<void> saveEndDate(DateTime date) async {
    await _prefs.setInt(_keyEndDateYear, date.year);
    await _prefs.setInt(_keyEndDateMonth, date.month);
  }

  /// Load end date. Returns [defaultValue] if no saved value.
  DateTime loadEndDate({required DateTime defaultValue}) {
    final year = _prefs.getInt(_keyEndDateYear);
    final month = _prefs.getInt(_keyEndDateMonth);
    if (year == null || month == null) {
      return defaultValue;
    }
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

  /// Save salario minimo diario.
  Future<void> saveSalarioMinimoDiario(double value) async {
    await _prefs.setDouble(_keySalarioMinimoDiario, value);
  }

  /// Load salario minimo diario. Returns [defaultValue] if no saved value.
  double loadSalarioMinimoDiario({required double defaultValue}) {
    return _safeGetDouble(_keySalarioMinimoDiario, defaultValue);
  }

  // ═══════════════════════════════════════════════
  // NEW: Persistence for previously missing fields
  // ═══════════════════════════════════════════════

  /// Save salario diario promedio.
  Future<void> saveSalarioDiarioPromedio(double value) async {
    await _prefs.setDouble(_keySalarioDiarioPromedio, value);
  }

  /// Load salario diario promedio. Returns [defaultValue] if no saved value.
  double loadSalarioDiarioPromedio({required double defaultValue}) {
    return _safeGetDouble(_keySalarioDiarioPromedio, defaultValue);
  }

  /// Save semanas cotizadas.
  Future<void> saveSemanasCotizadas(int value) async {
    await _prefs.setInt(_keySemanasCotizadas, value);
  }

  /// Load semanas cotizadas. Returns [defaultValue] if no saved value.
  int loadSemanasCotizadas({required int defaultValue}) {
    return _prefs.getInt(_keySemanasCotizadas) ?? defaultValue;
  }

  /// Save tiene esposa.
  Future<void> saveTieneEsposa(bool value) async {
    await _prefs.setBool(_keyTieneEsposa, value);
  }

  /// Load tiene esposa. Returns [defaultValue] if no saved value.
  bool loadTieneEsposa({required bool defaultValue}) {
    return _prefs.getBool(_keyTieneEsposa) ?? defaultValue;
  }

  /// Save numero de hijos.
  Future<void> saveNumeroHijos(int value) async {
    await _prefs.setInt(_keyNumeroHijos, value);
  }

  /// Load numero de hijos. Returns [defaultValue] if no saved value.
  int loadNumeroHijos({required int defaultValue}) {
    return _prefs.getInt(_keyNumeroHijos) ?? defaultValue;
  }

  /// Save numero de padres.
  Future<void> saveNumeroPadres(int value) async {
    await _prefs.setInt(_keyNumeroPadres, value);
  }

  /// Load numero de padres. Returns [defaultValue] if no saved value.
  int loadNumeroPadres({required int defaultValue}) {
    return _prefs.getInt(_keyNumeroPadres) ?? defaultValue;
  }

  /// Save edad de retiro (unified: con M40 and sin M40 use the same value).
  Future<void> saveEdadRetiro(double value) async {
    await _prefs.setDouble(_keyEdadRetiro, value);
  }

  /// Load edad de retiro. Returns [defaultValue] if no saved value.
  double loadEdadRetiro({required double defaultValue}) {
    return _safeGetDouble(_keyEdadRetiro, defaultValue);
  }

  /// Save salario registrado.
  Future<void> saveSalarioRegistrado(double value) async {
    await _prefs.setDouble(_keySalarioRegistrado, value);
  }

  /// Load salario registrado. Returns [defaultValue] if no saved value.
  double loadSalarioRegistrado({required double defaultValue}) {
    return _safeGetDouble(_keySalarioRegistrado, defaultValue);
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

  /// Save fecha de cálculo.
  Future<void> saveFechaCalculo(DateTime value) async {
    await _prefs.setInt(_keyFechaCalculoYear, value.year);
    await _prefs.setInt(_keyFechaCalculoMonth, value.month);
    await _prefs.setInt(_keyFechaCalculoDay, value.day);
  }

  /// Load fecha de cálculo. Returns [defaultValue] if no saved value.
  DateTime loadFechaCalculo({required DateTime defaultValue}) {
    final year = _prefs.getInt(_keyFechaCalculoYear);
    final month = _prefs.getInt(_keyFechaCalculoMonth);
    final day = _prefs.getInt(_keyFechaCalculoDay);
    if (year == null || month == null || day == null) {
      return defaultValue;
    }
    return DateTime(year, month, day);
  }

  /// Save fecha de nacimiento.
  Future<void> saveFechaNacimiento(DateTime value) async {
    await _prefs.setInt(_keyFechaNacimientoYear, value.year);
    await _prefs.setInt(_keyFechaNacimientoMonth, value.month);
    await _prefs.setInt(_keyFechaNacimientoDay, value.day);
  }

  /// Load fecha de nacimiento. Returns [defaultValue] if no saved value.
  DateTime loadFechaNacimiento({required DateTime defaultValue}) {
    final year = _prefs.getInt(_keyFechaNacimientoYear);
    final month = _prefs.getInt(_keyFechaNacimientoMonth);
    final day = _prefs.getInt(_keyFechaNacimientoDay);
    if (year == null || month == null || day == null) {
      return defaultValue;
    }
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

  /// Save salario promedio 250 semanas.
  Future<void> saveSalarioPromedio250Semanas(double value) async {
    await _prefs.setDouble(_keySalarioPromedio250Semanas, value);
  }

  /// Load salario promedio 250 semanas. Returns [defaultValue] if no saved value.
  double loadSalarioPromedio250Semanas({required double defaultValue}) {
    return _safeGetDouble(_keySalarioPromedio250Semanas, defaultValue);
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

  static const _keyPeriodos = 'periodos_salariales';

  /// Save the list of salary periods as a JSON string.
  Future<void> savePeriodos(List<PeriodoSalarial> periodos) async {
    final jsonList = periodos.map((p) => p.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await _prefs.setString(_keyPeriodos, jsonString);
  }

  /// Load the list of salary periods from JSON string.
  /// Returns an empty list if no saved data.
  List<PeriodoSalarial> loadPeriodos() {
    final jsonString = _prefs.getString(_keyPeriodos);
    if (jsonString == null || jsonString.isEmpty) return [];
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
