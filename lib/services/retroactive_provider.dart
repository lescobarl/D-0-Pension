import 'package:flutter/foundation.dart';
import '../core/engine/formula_evaluator.dart';
import '../core/models/pension_calculation.dart';
import '../core/models/periodo_salarial.dart';
import '../core/models/retroactive_calculation.dart';
import '../core/utils/error_handler.dart';
import 'persistence_service.dart';

/// Provider for managing the Pensión CON Modalidad 40 (Ley 73) calculation
/// pipeline.
///
/// Orchestrates the full calculation chain:
///   1. [calculateFactAsig]        → FactAsgCalculation (pension base)
///   2. [calculatePensionMod40]    → PensionMod40Calculation (M40 pension)
///   3. [calculateCostoMod40]      → CostoMod40Calculation (M40 cost)
///   4. [calculateRetroactivo]     → RetroactiveCalculation (retroactive cost)
///   5. [calculateInversion]       → InversionCalculation (M40 vs no-M40)
///   6. [calculateFinanciamiento]  → FinanciamientoCalculation (financing)
///
/// Exposes setters for every input. Each setter calls the appropriate
/// `_recalculateXxx()` method to keep derived state consistent.
class RetroactiveProvider extends ChangeNotifier {
  // ===========================================================================
  // INPUTS
  // ===========================================================================

  // --- Fact. + Asig. (shared) ---
  double _salarioDiarioPromedio = 0;
  double _umaDiaria = 0;
  double _salarioMinimoDiario = 0;
  int _pensionYear = DateTime.now().year + 1;
  int _semanasCotizadas = 0;
  bool _tieneEsposa = false;
  int _numeroHijos = 0;
  int _numeroPadres = 0;

  // --- Pensión SIN M40 (used for comparison) ---
  double _salarioPromedio250Semanas = 0;
  int _totalSemanasSinMod40 = 0;
  
  // --- Pensión (unified: con M40 and sin M40 use the same edad retiro) ---
  double _edadRetiro = 65;

  // --- COSTO MOD. 40 ---
  double _umaMultiplier = 25.0; // 1-25, configurable by user
  double _salarioRegistrado = 0;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 365));

  // --- PAGO RETROACTIVO ---
  double _costoModalidad40 = 0;
  double _retroactiveYears = 0;

  // --- FINANCIAMIENTO ---
  double _pensionMensualMejorada = 0;

  // --- Internal derived state ---
  final double _pensionSinMod40 = 0;

  // --- Auto-projection flag for UMA / Salario Mínimo ---
  // When true, UMA and SM are automatically projected from pensionYear.
  // When the user manually edits UMA or SM, this flag is set to false.
  bool _umaSmAutoCalculated = true;

  // --- Auto-projection flag for Salario Promedio (con Mod40) ---
  // When true, Salario Promedio (con Mod40) is automatically calculated
  // as the weighted average of SalarioPromedio250Semanas and SalarioDiarioPromedio
  // using the semanas distribution. When the user manually edits the field,
  // this flag is set to false.
  bool _salarioPromAutoCalculado = true;

  // --- Periodos (SAL. PROM MOD 40 desglose) ---
  // Mirrors the Excel SAL. PROM MOD 40 sheet where each row has:
  //   fechaInicio, fechaTermino, salarioDiario, semanas
  // The first period (esMod40=true) is auto-filled from _salarioRegistrado.
  // Remaining periods are auto-filled from _salarioPromedio250Semanas.
  // Total weeks across all periods must sum to totalSemanasPromedio (250).
  //
  // The user can edit any period directly. Changes recalculate in real time
  // (same pattern as UMA/SM auto-projection).
  List<PeriodoSalarial> _periodos = [];

  // --- UI state ---
  bool _isLoading = false;
  String? _errorMessage;

  /// True when initialize() loaded data from persistence (not defaults).
  /// Used by CapturaView to show a "Configuración recuperada" SnackBar.
  bool _loadedFromPersistence = false;

  // --- Fechas ---
  DateTime _fechaCalculo = DateTime.now();
  DateTime _fechaNacimiento = DateTime.now();

  // --- Semanas (desglose) ---
  double _semanasAntesMod40 = 0;
  double _semanasEnMod40 = 0;

  // ===========================================================================
  // CALCULATIONS (derived state)
  // ===========================================================================

  FactAsigCalculation? _factAsigCalculation;
  PensionMod40Calculation? _pensionMod40Calculation;
  CostoMod40Calculation? _costoMod40Calculation;
  RetroactiveCalculation? _retroactiveCalculation;
  InversionCalculation? _inversionCalculation;
  FinanciamientoCalculation? _financiamientoCalculation;
  FactAsigCalculation? _factAsigSinMod40Calculation;

  // ===========================================================================
  // GETTERS — INPUTS
  // ===========================================================================

  double get salarioDiarioPromedio => _salarioDiarioPromedio;
  double get umaDiaria => _umaDiaria;
  double get salarioMinimoDiario => _salarioMinimoDiario;
  bool get umaSmAutoCalculated => _umaSmAutoCalculated;
  bool get salarioPromAutoCalculado => _salarioPromAutoCalculado;
  List<PeriodoSalarial> get periodos => List.unmodifiable(_periodos);
  int get pensionYear => _pensionYear;
  int get semanasCotizadas => _semanasCotizadas;
  bool get tieneEsposa => _tieneEsposa;
  int get numeroHijos => _numeroHijos;
  int get numeroPadres => _numeroPadres;

  double get salarioPromedio250Semanas => _salarioPromedio250Semanas;
  int get totalSemanasSinMod40 => _totalSemanasSinMod40;
  double get edadRetiro => _edadRetiro;

  double get umaMultiplier => _umaMultiplier;
  double get salarioRegistrado => _salarioRegistrado;
  DateTime get startDate => _startDate;
  DateTime get endDate => _endDate;

  double get costoModalidad40 => _costoModalidad40;
  double get retroactiveYears => _retroactiveYears;

  double get pensionMensualMejorada => _pensionMensualMejorada;

  double get pensionSinMod40 => _pensionSinMod40;

  // --- UI state getters ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get loadedFromPersistence => _loadedFromPersistence;

  // --- Fechas ---
  DateTime get fechaCalculo => _fechaCalculo;
  DateTime get fechaNacimiento => _fechaNacimiento;

  // --- Semanas (desglose) ---
  double get semanasAntesMod40 => _semanasAntesMod40;
  double get semanasEnMod40 => _semanasEnMod40;

  /// Nuevo salario promedio calculado desde el desglose de periodos.
  ///
  /// Regla operativa para pensión con Mod40:
  /// - Considerar como máximo 250 semanas efectivas del desglose.
  /// - Si hay más de 250, recortar las semanas excedentes empezando por
  ///   los periodos más antiguos (se consume secuencialmente y el último
  ///   periodo puede quedar parcial).
  /// - El promedio se normaliza a base 250.
  ///
  /// Si no hay periodos definidos, retorna [_salarioPromedio250Semanas].
  double get nuevoSalarioPromedio {
    return _calculateSalarioPromedioFromPeriodos();
  }

  /// Available ages for the retirement dropdown (from metadata).
  /// Both con-Mod40 and sin-Mod40 calculations use the same unified list.
  /// e.g. [60, 60.51, 61, 61.51, ..., 65]
  List<double> get availableAgesRetiro =>
      evaluator.metadata.financialRules.pensionAgeDropdown.availableAges;

  // ===========================================================================
  // GETTERS — DERIVED
  // ===========================================================================

  FactAsigCalculation? get factAsigCalculation => _factAsigCalculation;
  PensionMod40Calculation? get pensionMod40Calculation =>
      _pensionMod40Calculation;
  CostoMod40Calculation? get costoMod40Calculation => _costoMod40Calculation;
  RetroactiveCalculation? get retroactiveCalculation =>
      _retroactiveCalculation;
  InversionCalculation? get inversionCalculation => _inversionCalculation;
  FinanciamientoCalculation? get financiamientoCalculation =>
      _financiamientoCalculation;
  FactAsigCalculation? get factAsigSinMod40Calculation =>
      _factAsigSinMod40Calculation;

  // ===========================================================================
  // DEPENDENCIES
  // ===========================================================================

  final FormulaEvaluator evaluator;
  final PersistenceService persistence;

  RetroactiveProvider({
    required this.evaluator,
    required this.persistence,
  });

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  /// Load persisted data and apply defaults from metadata.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!evaluator.isInitialized) {
        await evaluator.initialize();
      }

      final rules = evaluator.metadata.financialRules;
      final defaults = rules.defaultValues;

      // Detect if user has previously saved data
      _loadedFromPersistence = persistence.hasAnyData();

      // Load from persistence or fall back to metadata defaults
      _salarioDiarioPromedio = persistence.loadSalarioDiarioPromedio(
        defaultValue: defaults.salarioDiarioPromedio,
      );
      _umaDiaria = persistence.loadUmaDiaria(
        defaultValue: defaults.umaDiaria,
      );
      _salarioMinimoDiario = persistence.loadSalarioMinimoDiario(
        defaultValue: defaults.salarioMinimoDiario,
      );
      _pensionYear = persistence.loadPensionYear(
        defaultValue: defaults.pensionYear,
      );
      _semanasCotizadas = persistence.loadSemanasCotizadas(
        defaultValue: defaults.semanasCotizadas,
      );
      _tieneEsposa = persistence.loadTieneEsposa(
        defaultValue: defaults.tieneEsposa,
      );
      _numeroHijos = persistence.loadNumeroHijos(
        defaultValue: defaults.numeroHijos,
      );
      _numeroPadres = persistence.loadNumeroPadres(
        defaultValue: defaults.numeroPadres,
      );

      // Load persisted values with metadata defaults
      _salarioPromedio250Semanas = persistence.loadSalarioPromedio250Semanas(
        defaultValue: defaults.salarioPromedio250Semanas,
      );
      _totalSemanasSinMod40 = persistence.loadTotalSemanasSinMod40(
        defaultValue: defaults.totalSemanasSinMod40,
      );
      _edadRetiro = persistence.loadEdadRetiro(
        defaultValue: defaults.edadRetiro,
      );
      _umaMultiplier = persistence.loadUmaMultiplier(
        defaultValue: 25.0,
      );
      _salarioRegistrado = persistence.loadSalarioRegistrado(
        defaultValue: defaults.salarioRegistrado,
      );
      // Ensure salarioRegistrado is never 0; fall back to metadata default
      if (_salarioRegistrado <= 0) {
        _salarioRegistrado = defaults.salarioRegistrado;
        persistence.saveSalarioRegistrado(_salarioRegistrado);
      }
      _startDate = persistence.loadStartDate(
        defaultValue: DateTime(2027, 2, 1),
      );
      _endDate = persistence.loadEndDate(
        defaultValue: DateTime.now().add(const Duration(days: 365)),
      );
      // Ensure startDate/endDate are valid (endDate > startDate)
      if (_endDate.isBefore(_startDate) || _endDate.isAtSameMomentAs(_startDate)) {
        _endDate = _startDate.add(const Duration(days: 365));
        persistence.saveEndDate(_endDate);
      }

      _costoModalidad40 = persistence.loadCostoModalidad40(
        defaultValue: defaults.retroactiveYears,
      );

      // Load semanas desglose (semanasEnMod40 needed before retroactiveYears default)
      _semanasAntesMod40 = persistence.loadSemanasAntesMod40(
        defaultValue: defaults.semanasAntesMod40,
      );
      _semanasEnMod40 = persistence.loadSemanasEnMod40(
        defaultValue: defaults.semanasEnMod40,
      );

      // RetroactiveYears: default = semanasEnMod40 converted to years (e.g. 130 sem = 2.5 años)
      _retroactiveYears = persistence.loadRetroactiveYears(
        defaultValue: _semanasEnMod40 / 52,
      );

      // Migration guard: semanasAntesMod40 is a user-captured input (Excel DATOS GEN)
      // and must stay aligned with totalSemanasSinMod40.
      // Older versions could overwrite semanasAntesMod40 from SAL. PROM periodos,
      // causing values around ~250 after app updates/reinstalls.
      // We only align both fields; we do not force business thresholds here
      // so user-captured values are always respected.
      final semanasAntesCanonicas = _totalSemanasSinMod40.toDouble();
      if (_semanasAntesMod40 != semanasAntesCanonicas) {
        _semanasAntesMod40 = semanasAntesCanonicas;
        persistence.saveSemanasAntesMod40(_semanasAntesMod40);
      }

      ErrorHandler.logDebug('Semanas antes Mod40 loaded: $_semanasAntesMod40 (default was: ${defaults.semanasAntesMod40})');
      ErrorHandler.logDebug('Salario Promedio 250 Semanas loaded: $_salarioPromedio250Semanas (default was: ${defaults.salarioPromedio250Semanas})');

      // Load fechas
      _fechaCalculo = persistence.loadFechaCalculo(
        defaultValue: DateTime.now(),
      );
      _fechaNacimiento = persistence.loadFechaNacimiento(
        defaultValue: defaults.fechaNacimiento,
      );

      // Load periodos from persistence
      _periodos = persistence.loadPeriodos();

      // Always project UMA/SM to ensure they match the current pensionYear.
      // When loaded from persistence, the saved UMA/SM values may be stale
      // if the user changed edadRetiro or fechaNacimiento since last save.
      _projectUmaSm(force: true);

      // Project salario registrado from UMAs (like Excel cell C12 = 25 × UMA)
      _projectSalarioRegistrado(force: true);

      // Seed periodos from Excel baseline data if there are no saved periodos.
      // The user EXPLICITLY requested that periodos should NEVER be lost.
      // If there are no periodos in persistence, we seed them from the Excel
      // baseline so the Desglose Sal. Prom is always populated.
      //
      // If the user has previously saved periodos (via "Guardar" button),
      // those are loaded from persistence above and MUST be preserved.
      if (_periodos.isEmpty) {
        _periodos = _createBaselinePeriodos();
        persistence.savePeriodos(_periodos);
        // Recalculate _salarioDiarioPromedio from seeded periods (Excel E19).
        _salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
        persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
        // Recalculate _salarioPromedio250Semanas from NON-Mod40 periods only
        final totalSemanasSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
        final totalResultadosSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
        _salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
        persistence.saveSalarioPromedio250Semanas(_salarioPromedio250Semanas);
        ErrorHandler.logDebug('Salario Promedio 250 Semanas calculated from seeded periodos: $_salarioPromedio250Semanas (totalSemanasSinMod40: $totalSemanasSinMod40, totalResultadosSinMod40: $totalResultadosSinMod40)');
        _salarioPromAutoCalculado = true;
      } else {
        // Recalculate _salarioDiarioPromedio from saved periods (Excel E19).
        _salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
        persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
        // Recalculate _salarioPromedio250Semanas from NON-Mod40 periods only
        final totalSemanasSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
        final totalResultadosSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
        _salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
        persistence.saveSalarioPromedio250Semanas(_salarioPromedio250Semanas);
        ErrorHandler.logDebug('Salario Promedio 250 Semanas calculated from saved periodos: $_salarioPromedio250Semanas (totalSemanasSinMod40: $totalSemanasSinMod40, totalResultadosSinMod40: $totalResultadosSinMod40)');
        // Periods were loaded from persistence (user's saved data).
        // Set auto-calculated to false so that _recalculatePromedioFromPeriodos
        // does NOT overwrite the user's manually-edited period values when
        // inputs like UMA, SM, edadRetiro, etc. change later.
        // The user's custom desglose de periodos must be preserved.
        _salarioPromAutoCalculado = false;
      }

        // IMPORTANT: semanasAntesMod40 is a user-captured input (Excel DATOS GEN).
        // Never derive it from SAL. PROM periodos.
        // Only keep semanasEnMod40 synchronized from Mod40-tagged periods.
        final semanasEnMod40 =
          _periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
        _semanasEnMod40 = semanasEnMod40;
        persistence.saveSemanasEnMod40(_semanasEnMod40);
      _semanasCotizadas = (_semanasAntesMod40 + _semanasEnMod40).toInt();
      persistence.saveSemanasCotizadas(_semanasCotizadas);

      // Auto-calculate endDate from startDate + semanasEnMod40
      if (_semanasEnMod40 > 0) {
        _endDate = _startDate.add(Duration(days: (_semanasEnMod40 * 7).round()));
        persistence.saveEndDate(_endDate);
      }

      // Recalculate all
      _recalculateFactAsig();
      _recalculateFactAsigSinMod40();
      _recalculatePensionMod40();
      _recalculateCostoMod40();
      _recalculateRetroactivo();
      _recalculateInversion();
      _recalculateFinanciamiento();

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Error al inicializar: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  // ===========================================================================
  // SETTERS — Each one triggers the appropriate recalculation chain
  // ===========================================================================

  void setSalarioDiarioPromedio(double v) {
    if (v == _salarioDiarioPromedio) return;
    _salarioDiarioPromedio = v;
    // User manually edited → disable auto-projection
    _salarioPromAutoCalculado = false;
    persistence.saveSalarioDiarioPromedio(v);
    _recalculateFactAsig();
    _recalculatePensionMod40();
    _recalculateInversion();
    notifyListeners();
  }

  void setUmaDiaria(double v) {
    if (v == _umaDiaria) return;
    _umaDiaria = v;
    // User manually edited → disable auto-projection
    _umaSmAutoCalculated = false;
    persistence.saveUmaDiaria(v);
    // Recalculate salario registrado from the new UMA value (25 × UMA)
    _projectSalarioRegistrado(force: true);
    // Recalculate Salario Promedio (con Mod40) with the new salarioRegistrado
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    notifyListeners();
  }

  void setSalarioMinimoDiario(double v) {
    if (v == _salarioMinimoDiario) return;
    _salarioMinimoDiario = v;
    // User manually edited → disable auto-projection
    _umaSmAutoCalculated = false;
    persistence.saveSalarioMinimoDiario(v);
    _recalculateFactAsig();
    _recalculatePensionMod40();
    notifyListeners();
  }

  void setPensionYear(int v) {
    if (v == _pensionYear) return;
    _pensionYear = v;
    persistence.savePensionYear(v);
    // Project UMA/SM for the new pension year (same as setEdadRetiro)
    _projectUmaSm(force: true);
    // Project salario registrado from UMAs (like Excel cell C12 = 25 × UMA)
    _projectSalarioRegistrado(force: true);
    // Recalculate Salario Promedio (con Mod40) with the new salarioRegistrado
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    // Recalculate Costo Mod40 with the new salarioRegistrado
    _recalculateCostoMod40();
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void setSemanasCotizadas(int v) {
    if (v == _semanasCotizadas) return;
    _semanasCotizadas = v;
    persistence.saveSemanasCotizadas(v);
    _recalculateFactAsig();
    _recalculatePensionMod40();
    _recalculateInversion();
    notifyListeners();
  }

  void setTieneEsposa(bool v) {
    if (v == _tieneEsposa) return;
    _tieneEsposa = v;
    persistence.saveTieneEsposa(v);
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    notifyListeners();
  }

  void setNumeroHijos(int v) {
    if (v == _numeroHijos) return;
    _numeroHijos = v;
    persistence.saveNumeroHijos(v);
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    notifyListeners();
  }

  void setNumeroPadres(int v) {
    if (v == _numeroPadres) return;
    _numeroPadres = v;
    persistence.saveNumeroPadres(v);
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    notifyListeners();
  }

  void setSalarioPromedio250Semanas(double v) {
    if (v == _salarioPromedio250Semanas) return;
    _salarioPromedio250Semanas = v;
    persistence.saveSalarioPromedio250Semanas(v);
    // Update all non-Mod40 periods to use this new salary value
    bool anyChanged = false;
    for (int i = 0; i < _periodos.length; i++) {
      final p = _periodos[i];
      if (!p.esMod40) {
        final nuevoSalario = _salarioPromedio250Semanas;
        if (p.salarioDiario != nuevoSalario) {
          _periodos[i] = PeriodoSalarial(
            fechaInicio: p.fechaInicio,
            fechaTermino: p.fechaTermino,
            salarioDiario: nuevoSalario,
            semanas: p.semanas,
            esMod40: p.esMod40,
          );
          anyChanged = true;
        }
      }
    }
    if (anyChanged) {
      persistence.savePeriodos(_periodos);
      // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
      final semanasEnMod40 =
          _periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
      _semanasEnMod40 = semanasEnMod40;
      persistence.saveSemanasEnMod40(_semanasEnMod40);
      _semanasCotizadas = (_semanasAntesMod40 + _semanasEnMod40).toInt();
      persistence.saveSemanasCotizadas(_semanasCotizadas);
      _salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
      persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
    }
    // Recalculate all dependent values
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateInversion();
    notifyListeners();
  }

  /// Setter for the periodos list.
  ///
  /// When the user manually sets the full periodos list (e.g. from persistence
  /// or manual edit), auto-projection is disabled so that
  /// [_recalculatePromedioFromPeriodos] does NOT overwrite the user's custom
  /// period values later (e.g. when [setSalarioPromedio250Semanas] is called).
  void setPeriodos(List<PeriodoSalarial> periodos) {
    _periodos = List.from(periodos);
    persistence.savePeriodos(_periodos);
    // User manually set periods → disable auto-projection
    _salarioPromAutoCalculado = false;
    // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
    final semanasEnMod40 =
      _periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
    _semanasEnMod40 = semanasEnMod40;
    persistence.saveSemanasEnMod40(_semanasEnMod40);
    // Update total cotizadas semanas
    _semanasCotizadas = (_semanasAntesMod40 + _semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_semanasCotizadas);
    // Recalculate Salario Promedio from the new periods (Excel E19).
    _salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
    persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
    // Recalculate Salario Promedio 250 Semanas from NON-Mod40 periods only
    final totalSemanasSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
    final totalResultadosSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
    _salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
    persistence.saveSalarioPromedio250Semanas(_salarioPromedio250Semanas);
    
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateInversion();
    notifyListeners();
  }

  /// Update a single period at [index].
  ///
  /// When the user manually edits a period (salarioDiario or semanas),
  /// auto-projection is disabled so that [_recalculatePromedioFromPeriodos]
  /// does NOT overwrite the user's manual edits later (e.g. when
  /// [setSalarioPromedio250Semanas] is called).
  void updatePeriodo(int index, PeriodoSalarial periodo) {
    if (index < 0 || index >= _periodos.length) return;
    _periodos[index] = periodo;
    persistence.savePeriodos(_periodos);
    // User manually edited → disable auto-projection so _recalculatePromedioFromPeriodos
    // won't overwrite the user's custom period values later.
    _salarioPromAutoCalculado = false;
    // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
    final semanasEnMod40 =
      _periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
    _semanasEnMod40 = semanasEnMod40;
    persistence.saveSemanasEnMod40(_semanasEnMod40);
    ErrorHandler.logDebug('Semanas Mod40 actualizadas:');
    ErrorHandler.logDebug('  - Valor calculado: $semanasEnMod40');
    ErrorHandler.logDebug('  - Valor asignado: $_semanasEnMod40');
    // Update total cotizadas semanas
    _semanasCotizadas = (_semanasAntesMod40 + _semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_semanasCotizadas);
    // Recalculate Salario Promedio from the updated periods (Excel E19).
    _salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
    persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
    // Calculate Salario Promedio 250 Semanas from NON-Mod40 periods only (per user request: Desglose Sal. Prom without M40)
    if (_periodos.isNotEmpty) {
      final totalSemanasSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
      final totalResultadosSinMod40 = _periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
      _salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
      persistence.saveSalarioPromedio250Semanas(_salarioPromedio250Semanas);
    }
    
    ErrorHandler.logDebug('  - Semanas en Mod40: $_semanasEnMod40');
    ErrorHandler.logDebug('  - Salario Promedio 250 Semanas: $_salarioPromedio250Semanas');
    ErrorHandler.logDebug('  - Salario Diario Promedio: $_salarioDiarioPromedio');
    
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateInversion();
    notifyListeners();
  }

  /// Add a new empty period to the list.
  ///
  /// When the user manually adds a period, auto-projection is disabled so that
  /// [_recalculatePromedioFromPeriodos] does NOT overwrite the user's custom
  /// period values later (e.g. when [setSalarioPromedio250Semanas] is called).
  void addPeriodo() {
    _periodos.add(PeriodoSalarial(
      salarioDiario: 0.0,
      semanas: 0.0,
      esMod40: false,
    ));
    persistence.savePeriodos(_periodos);
    // User manually added a period → disable auto-projection
    _salarioPromAutoCalculado = false;
    notifyListeners();
  }

  /// Remove a period at [index].
  ///
  /// When the user manually removes a period, auto-projection is disabled so
  /// that [_recalculatePromedioFromPeriodos] does NOT overwrite the user's
  /// custom period values later (e.g. when [setSalarioPromedio250Semanas] is
  /// called).
  void removePeriodo(int index) {
    if (index < 0 || index >= _periodos.length) return;
    _periodos.removeAt(index);
    persistence.savePeriodos(_periodos);
    // User manually removed a period → disable auto-projection
    _salarioPromAutoCalculado = false;
    // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
    final semanasEnMod40 =
      _periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
    _semanasEnMod40 = semanasEnMod40;
    persistence.saveSemanasEnMod40(_semanasEnMod40);
    // Update total cotizadas semanas
    _semanasCotizadas = (_semanasAntesMod40 + _semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_semanasCotizadas);
    // Recalculate Salario Promedio after removal
    _salarioDiarioPromedio = nuevoSalarioPromedio;
    persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateInversion();
    notifyListeners();
  }

  void setTotalSemanasSinMod40(int v) {
    if (v == _totalSemanasSinMod40) return;
    _totalSemanasSinMod40 = v;
    persistence.saveTotalSemanasSinMod40(v);
    _recalculateFactAsigSinMod40();
    _recalculateInversion();
    notifyListeners();
  }

  Future<void> setEdadRetiro(double v) async {
    if (v == _edadRetiro) return;
    _edadRetiro = v;
    persistence.saveEdadRetiro(v);

    // Recalculate pensionYear from fechaNacimiento + edadRetiro
    _pensionYear = _fechaNacimiento.year + _edadRetiro.floor();
    persistence.savePensionYear(_pensionYear);

    // Always project UMA and Salario Mínimo when edad changes, regardless
    // of _umaSmAutoCalculated. The flag only prevents overwriting when the
    // user is actively typing in the UMA/SM fields (setUmaDiaria/setSalarioMinimoDiario).
    // When edad changes, the pension year changes, so UMA/SM must be updated
    // to match the new projection year.
    _projectUmaSm(force: true);

    // Salario registrado must always be reprojected from UMA when edad changes.
    // The desglose protection is handled inside _recalculatePromedioFromPeriodos().
    _projectSalarioRegistrado(force: true);

    // Allow one event loop cycle for projections to complete.
    await Future.delayed(Duration.zero);

    // Recalculate Salario Promedio (con Mod40). This updates Mod40 rows from
    // _salarioRegistrado while preserving user-entered non-Mod40 salaries.
    _recalculatePromedioFromPeriodos();
    
    // Recalculate all dependent values
    _recalculateCostoMod40();
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    
    notifyListeners();
  }

  /// Set UMA multiplier (1-25). Recalculates salario registrado and all
  /// downstream calculations.
  void setUmaMultiplier(double v) {
    final clamped = v.clamp(1.0, 25.0);
    if (clamped == _umaMultiplier) return;
    _umaMultiplier = clamped;
    persistence.saveUmaMultiplier(clamped);
    // Force re-project salario registrado from new multiplier × UMA
    _projectSalarioRegistrado(force: true);
    // Recalculate all downstream values
    _recalculatePromedioFromPeriodos();
    _recalculateCostoMod40();
    _recalculateFactAsig();
    _recalculatePensionMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void setSalarioRegistrado(double v) {
    if (v == _salarioRegistrado) return;
    _salarioRegistrado = v;
    // User manually edited → disable auto-projection
    _salarioPromAutoCalculado = false;
    persistence.saveSalarioRegistrado(v);
    // Recalculate Salario Promedio (con Mod40) when the registered salary changes
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _recalculateCostoMod40();
    _recalculateFactAsig();
    _recalculatePensionMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void setStartDate(DateTime v) {
    if (v == _startDate) return;
    _startDate = v;
    persistence.saveStartDate(v);
    // Auto-calculate endDate from new startDate + semanasEnMod40
    if (_semanasEnMod40 > 0) {
      _endDate = _startDate.add(Duration(days: (_semanasEnMod40 * 7).round()));
      persistence.saveEndDate(_endDate);
    }
    _recalculateCostoMod40();
    _recalculateRetroactivo();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void setEndDate(DateTime v) {
    if (v == _endDate) return;
    _endDate = v;
    persistence.saveEndDate(v);
    _recalculateCostoMod40();
    _recalculateRetroactivo();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void setCostoModalidad40(double v) {
    if (v == _costoModalidad40) return;
    _costoModalidad40 = v;
    persistence.saveCostoModalidad40(v);
    _recalculateRetroactivo();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void setRetroactiveYears(double v) {
    if (v == _retroactiveYears) return;
    _retroactiveYears = v;
    persistence.saveRetroactiveYears(v);
    _recalculateRetroactivo();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void setPensionMensualMejorada(double v) {
    if (v == _pensionMensualMejorada) return;
    _pensionMensualMejorada = v;
    _recalculateFinanciamiento();
    notifyListeners();
  }

  // --- Fecha setters ---
  void setFechaCalculo(DateTime v) {
    _fechaCalculo = v;
    persistence.saveFechaCalculo(v);
    notifyListeners();
  }

  void setFechaNacimiento(DateTime v) {
    _fechaNacimiento = v;
    persistence.saveFechaNacimiento(v);

    // Recalculate pensionYear from fechaNacimiento + edadRetiro
    _pensionYear = _fechaNacimiento.year + _edadRetiro.floor();
    persistence.savePensionYear(_pensionYear);

    // Always project UMA and Salario Mínimo when fechaNacimiento changes,
    // regardless of _umaSmAutoCalculated (same reasoning as setEdadRetiro).
    _projectUmaSm(force: true);
    // Project salario registrado from UMAs (like Excel cell C12 = 25 × UMA)
    _projectSalarioRegistrado(force: true);
    // Recalculate Salario Promedio (con Mod40) with the new salarioRegistrado
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    // Recalculate Costo Mod40 with the new salarioRegistrado
    _recalculateCostoMod40();

    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  // --- Semanas (desglose) setters ---
  // --- Semanas (desglose) setters ---
  void setSemanasAntesMod40(double v) {
    if (v == _semanasAntesMod40) return;
    _semanasAntesMod40 = v;
    persistence.saveSemanasAntesMod40(v);
    // Recalculate total semanas sin Mod40
    _totalSemanasSinMod40 = v.toInt();
    persistence.saveTotalSemanasSinMod40(_totalSemanasSinMod40);
    // Recalculate total semanas con Mod40 (semanasCotizadas = antes + en)
    _semanasCotizadas = (v + _semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_semanasCotizadas);
    // Recalculate Salario Promedio (con Mod40) when the weight distribution changes
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _recalculateFactAsig();
    _recalculatePensionMod40();
    _recalculateFactAsigSinMod40();
    _recalculateInversion();
    notifyListeners();
  }

  void setSemanasEnMod40(double v) {
    if (v == _semanasEnMod40) return;
    _semanasEnMod40 = v;
    persistence.saveSemanasEnMod40(v);
    // Recalculate total semanas con Mod40
    _semanasCotizadas = (_semanasAntesMod40 + v).toInt();
    persistence.saveSemanasCotizadas(_semanasCotizadas);
    // Auto-calculate endDate from startDate + semanasEnMod40
    if (v > 0) {
      _endDate = _startDate.add(Duration(days: (v * 7).round()));
      persistence.saveEndDate(_endDate);
    }
    // Recalculate Salario Promedio (con Mod40) when the weight distribution changes
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _recalculateFactAsig();
    _recalculatePensionMod40();
    _recalculateCostoMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  // ===========================================================================
  // RECALCULATION CHAIN
  // ===========================================================================

  void _recalculateFactAsig() {
    if (!evaluator.isInitialized) return;
    try {
      // Use the user-entered salario diario promedio directly.
      // The user enters the "NUEVO SALARIO PROMEDIO DE 250 SEMANAS" value
      // (calculated externally, e.g. from the Excel's SAL. PROM MOD 40 sheet),
      // which is the weighted average of the last 250 weeks including Mod40.
      // Using _salarioDiarioPromedio directly ensures the App matches the
      // user's expected input without re-deriving it from _salarioPromedio250Semanas
      // and _salarioRegistrado (which can produce a different result when the
      // registered Mod40 salary differs from the actual weighted average).
      _factAsigCalculation = evaluator.calculateFactAsig(
        salarioDiarioPromedio: _salarioDiarioPromedio,
        umaDiaria: _umaDiaria,
        salarioMinimoDiario: _salarioMinimoDiario,
        pensionYear: _pensionYear,
        semanasCotizadas: _semanasCotizadas,
        tieneEsposa: _tieneEsposa,
        numeroHijos: _numeroHijos,
        numeroPadres: _numeroPadres,
        edadRetiro: _edadRetiro,
      );
    } catch (e) {
      _factAsigCalculation = null;
    }
  }

  void _recalculateFactAsigSinMod40() {
    if (!evaluator.isInitialized) return;
    try {
      // Redondear edad usando la regla de metadata (edad_rounding_rule.six_months_threshold)
      // que implementa Art. 167 LSS 1973: "6 meses y un día o más = siguiente año"
      // Excel: =IF(MOD(E6,1)<0.501, FLOOR(E6,1), CEILING(E6,1))
      // Usamos el threshold de metadata para que 0.5 → floor y 0.51 → ceil
      final rules = evaluator.metadata.financialRules;
      // Redondear la edad a entero usando la regla de metadata (roundToInteger),
      // que implementa Art. 167 LSS 1973: "6 meses y un día o más = siguiente año".
      // roundToInteger(60.51) = 61 → porcentaje 0.80 (igual que Excel).
      final edadEntera = rules.edadRoundingRule.roundToInteger(_edadRetiro);

      _factAsigSinMod40Calculation = evaluator.calculateFactAsig(
        salarioDiarioPromedio: _salarioPromedio250Semanas,
        umaDiaria: _umaDiaria,
        salarioMinimoDiario: _salarioMinimoDiario,
        pensionYear: _pensionYear,
        semanasCotizadas: _totalSemanasSinMod40,
        tieneEsposa: _tieneEsposa,
        numeroHijos: _numeroHijos,
        numeroPadres: _numeroPadres,
        edadRetiro: edadEntera.toDouble(),
      );
    } catch (e) {
      _factAsigSinMod40Calculation = null;
    }
  }

  void _recalculatePensionMod40() {
    if (!evaluator.isInitialized) return;
    try {
      // Forzar recálculo de factAsig con nuevo salario promedio
      _recalculateFactAsig();
      
      _pensionMod40Calculation = evaluator.calculatePensionMod40(
        pensionAnual100: _factAsigCalculation?.cuantiaTotalPensionVejez ?? 0,
        edadRetiro: _edadRetiro,
        salarioMinimoDiario: _salarioMinimoDiario,
        pensionYear: _pensionYear,
        cuantiaTotalAsignaciones:
            _factAsigCalculation?.cuantiaTotalAsignaciones ?? 0,
        totalAyudaAsistencial:
            _factAsigCalculation?.totalAyudaAsistencial ?? 0,
      );
      
      // Debug: Registrar valores clave
      ErrorHandler.logDebug(
        'SalarioPromedio: $_salarioDiarioPromedio, '
        'PensiónAnual100: ${_pensionMod40Calculation?.pensionAnual100}, '
        'PorcentajeEdad: ${_pensionMod40Calculation?.porcentajePorEdad}');
    } catch (e) {
      _pensionMod40Calculation = null;
    }
  }

  void _recalculateCostoMod40() {
    if (!evaluator.isInitialized) return;
    try {
      _costoMod40Calculation = evaluator.calculateCostoMod40(
        salarioRegistrado: _salarioRegistrado,
        startDate: _startDate,
        endDate: _endDate,
      );
    } catch (e) {
      _costoMod40Calculation = null;
    }
  }

  void _recalculateRetroactivo() {
    if (!evaluator.isInitialized) return;
    try {
      _retroactiveCalculation = evaluator.calculateRetroactivo(
        costoModalidad40: _costoMod40Calculation?.inversionTotal ?? 0,
        retroactiveYears: _retroactiveYears,
        startDate: _startDate,
        endDate: _endDate,
      );
    } catch (e) {
      _retroactiveCalculation = null;
    }
  }

  void _recalculateInversion() {
    if (!evaluator.isInitialized) return;
    try {
      // edadRetiroSinMod40: edad de retiro SIN Modalidad 40
      // Without Mod40, the person would have retired 1 year earlier.
      // Excel INVERSION: D4 (sin Mod40) = 60, F4 (con Mod40) = 61 = D4+1
      // F4 = roundToInteger(_edadRetiro) = 61 (misma regla que PENSIÓN ACTUAL),
      // D4 = F4 - 1 = 60. Usar floor() daba 60/59 (desfasado 1 año vs Excel).
      final rules = evaluator.metadata.financialRules;
      final edadConMod40 = rules.edadRoundingRule.roundToInteger(_edadRetiro);
      final edadSinMod40 = (edadConMod40 - 1).clamp(55, 65);

      _inversionCalculation = evaluator.calculateInversion(
        pensionMensualSinMod40: _factAsigSinMod40Calculation?.totalPensionMensual ?? 0,
        pensionMensualConMod40: _pensionMod40Calculation?.pensionMensual ?? 0,
        edadRetiroSinMod40: edadSinMod40,
        edadRetiroConMod40: edadConMod40,
        inversionTotalMod40: _costoMod40Calculation?.inversionNeta ?? 0,
        inversionTotal: _costoMod40Calculation?.inversionTotal ?? 0,
      );
    } catch (e) {
      _inversionCalculation = null;
    }
  }

  /// Auto-project UMA and Salario Mínimo from the current pensionYear.
  ///
  /// When [force] is `false` (default), only projects if the user has NOT
  /// manually overridden the values (i.e. [_umaSmAutoCalculated] is true).
  /// When [force] is `true`, always projects regardless of the flag — this
  /// is used when the pension year itself has changed (via [setEdadRetiro]
  /// or [setFechaNacimiento]), because the projected values must match the
  /// new year. The flag is also reset to `true` so subsequent auto-projection
  /// continues to work.
  void _projectUmaSm({bool force = false}) {
    if (!force && !_umaSmAutoCalculated) return;
    if (!evaluator.isInitialized) return;
    final rules = evaluator.metadata.financialRules;
    _umaDiaria = evaluator.getProjectedUma(_pensionYear, rules);
    _salarioMinimoDiario = evaluator.getProjectedMinWage(_pensionYear, rules);
    persistence.saveUmaDiaria(_umaDiaria);
    persistence.saveSalarioMinimoDiario(_salarioMinimoDiario);
    // Re-enable auto-projection so future changes keep working
    _umaSmAutoCalculated = true;
  }

  /// Project salario registrado as [umaMultiplier] × UMA diaria (like Excel cell C12).
  /// Called after _projectUmaSm() to ensure _umaDiaria is current.
  void _projectSalarioRegistrado({bool force = false}) {
    if (!force && !_salarioPromAutoCalculado) return;
    final nuevoSalario = _umaMultiplier * _umaDiaria;
    if (nuevoSalario != _salarioRegistrado) {
      _salarioRegistrado = nuevoSalario;
      persistence.saveSalarioRegistrado(_salarioRegistrado);
      if (_periodos.isNotEmpty) {
        _updateMod40PeriodsWithNewSalary();
      }
    }
  }

  void _updateMod40PeriodsWithNewSalary() {
    bool anyChanged = false;
    for (int i = 0; i < _periodos.length; i++) {
      final p = _periodos[i];
      if (p.esMod40 && p.salarioDiario != _salarioRegistrado) {
        _periodos[i] = PeriodoSalarial(
          fechaInicio: p.fechaInicio,
          fechaTermino: p.fechaTermino,
          salarioDiario: _salarioRegistrado,
          semanas: p.semanas,
          esMod40: true,
        );
        anyChanged = true;
        ErrorHandler.logDebug('Periodo Mod40 actualizado con salario: $_salarioRegistrado');
      }
    }
    if (anyChanged) {
      persistence.savePeriodos(_periodos);
      _recalculatePromedioFromPeriodos();
      notifyListeners();
    }
  }

  /// Calculate Salario Promedio (con Mod40) from periodos using a 250-week cap.
  ///
  /// The calculation consumes period weeks in order and only takes up to
  /// totalSemanasPromedio (250 by metadata). Extra historical periods are
  /// ignored for the pension base.
  double _calculateSalarioPromedioFromPeriodos() {
    if (_periodos.isEmpty) return _salarioPromedio250Semanas;

    final totalSemanasPromedio =
        evaluator.metadata.financialRules.totalSemanasPromedio.toDouble();

    double semanasConsumidas = 0;
    double sumaResultados = 0;

    for (final p in _periodos) {
      if (semanasConsumidas >= totalSemanasPromedio) break;
      final semanasDisponibles = totalSemanasPromedio - semanasConsumidas;
      final semanasUsadas = p.semanas <= semanasDisponibles
          ? p.semanas
          : semanasDisponibles;
      if (semanasUsadas <= 0) continue;
      sumaResultados += p.salarioDiario * semanasUsadas;
      semanasConsumidas += semanasUsadas;
    }

    return sumaResultados / totalSemanasPromedio;
  }

  /// Recalculate _salarioDiarioPromedio from the current periodos list
  /// WITHOUT overwriting the periodos themselves.
  ///
  /// This is the ONLY method used by setters to update the weighted average.
  /// It NEVER overwrites _periodos — it only recalculates _salarioDiarioPromedio
  /// from whatever periods already exist. This guarantees the user's manually
  /// captured desglose de periodos is NEVER destroyed by an input change.
  ///
  /// If _periodos is empty (no periods defined yet), falls back to
  /// _salarioPromedio250Semanas as the promedio.
  ///
  /// If the user has manually edited _salarioDiarioPromedio
  /// (_salarioPromAutoCalculado == false), the manual value is preserved
  /// and this method does nothing.
  ///
  /// When _salarioPromAutoCalculado is true (auto-calculated mode), this
  /// method also UPDATES the salarioDiario of each existing period to reflect
  /// the current _salarioRegistrado (for Mod40 periods) and
  /// _salarioPromedio250Semanas (for non-Mod40 periods). This ensures that
  /// when inputs like UMA change, the desglose periodos update accordingly.
  ///
  /// The period structure (dates, semanas, esMod40) is PRESERVED — only the
  /// salarioDiario values are updated. Once the user manually edits any period
  /// (via setPeriodos/updatePeriodo/removePeriodo), _salarioPromAutoCalculado
  /// becomes false and this auto-update stops.
  ///
  /// Even when _salarioPromAutoCalculado is false, Mod40 periods are always updated
  /// to reflect the current _salarioRegistrado, since these are automatically
  /// calculated from UMA and should not be manually edited by the user.
  void _recalculatePromedioFromPeriodos() {
    if (_periodos.isNotEmpty) {
      // Update salarios using these rules:
      // - Mod40 periods always follow _salarioRegistrado (derived from UMA).
      // - non-Mod40 periods are NEVER updated by this method when called from age changes.
      //   They are only updated when the user explicitly changes _salarioPromedio250Semanas.
      bool anyChanged = false;
      
      for (int i = 0; i < _periodos.length; i++) {
        final p = _periodos[i];
        
        double nuevoSalario;
        if (p.esMod40) {
          // Periodos Mod40 siempre siguen _salarioRegistrado
          nuevoSalario = _salarioRegistrado;
        } else {
          // Periodos NO Mod40: NUNCA se actualizan automáticamente
          // Mantener el valor actual del periodo
          nuevoSalario = p.salarioDiario;
        }
        
        if (p.salarioDiario != nuevoSalario) {
          _periodos[i] = PeriodoSalarial(
            fechaInicio: p.fechaInicio,
            fechaTermino: p.fechaTermino,
            salarioDiario: nuevoSalario,
            semanas: p.semanas,
            esMod40: p.esMod40,
          );
          anyChanged = true;
        }
      }
      
      if (anyChanged) {
        persistence.savePeriodos(_periodos);
      }

      // Recalculate weighted average from periods using Excel E19.
      _salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
      persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
      
      // Recalculate Semanas en Mod40 (always)
      _semanasEnMod40 = _periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
      persistence.saveSemanasEnMod40(_semanasEnMod40);
    } else {
      // No periods defined — use the base 250-week average
      _salarioDiarioPromedio = _salarioPromedio250Semanas;
      persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
    }
    
    // Trigger recalculations for dependent fields
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    notifyListeners();
  }

  /// Create the baseline periodos list from Excel "SAL. PROM MOD 40" data.
  ///
  /// These values match the Excel spreadsheet:
  ///   SAL. PROM MOD 40 Row 22: Mod40 period (2027-02-01 to 2029-08-31,
  ///     [calculated salary], 134.7142857143 sem)
  ///   CAL. PROM. 250 SEM Row 7:  2026-02-01 to 2026-02-10 (2932.75, 1.43 sem)
  ///   CAL. PROM. 250 SEM Row 8:  2025-02-01 to 2026-02-01 (2714.25, 52.29 sem)
  ///   CAL. PROM. 250 SEM Row 9:  2024-02-01 to 2025-02-01 (2500.00, 52.43 sem)
  ///   CAL. PROM. 250 SEM Row 10: 2023-02-01 to 2024-02-01 (2200.00, 52.29 sem)
  ///   CAL. PROM. 250 SEM Row 11: 2022-02-01 to 2023-02-01 (2000.00, 52.29 sem)
  ///   CAL. PROM. 250 SEM Row 12: 2021-07-15 to 2022-02-01 (1900.00, 28.86 sem)
  ///   CAL. PROM. 250 SEM Row 13: 2021-01-01 to 2021-07-15 (1800.50, 10.43 sem)
  ///
  /// Total semanas = 134.71 (Mod40) + 1.43 + 52.29 + 52.43 + 52.29 + 52.29 +
  ///   28.86 + 10.43 = ~384.71 (exceeds 250 because Mod40 semanas are added
  ///   on top of the original 250-week base).
  ///
  /// This is used on FIRST load (no saved data) to populate the Desglose
  /// Sal. Prom with real data from the Excel spreadsheet.
  List<PeriodoSalarial> _createBaselinePeriodos() {
    return [
      // Mod40 period (SAL. PROM MOD 40 Row 22)
      PeriodoSalarial(
        fechaInicio: DateTime(2027, 2, 1),
        fechaTermino: DateTime(2029, 8, 31),
        salarioDiario: _salarioRegistrado,
        semanas: 134.7142857143,
        esMod40: true,
      ),
      // Original 250-week periods (CAL. PROM. 250 SEM Rows 7-13)
      PeriodoSalarial(
        fechaInicio: DateTime(2026, 2, 1),
        fechaTermino: DateTime(2026, 2, 10),
        salarioDiario: 2932.75,
        semanas: 1.4285714286,
        esMod40: false,
      ),
      PeriodoSalarial(
        fechaInicio: DateTime(2025, 2, 1),
        fechaTermino: DateTime(2026, 2, 1),
        salarioDiario: 2714.25,
        semanas: 52.2857142857,
        esMod40: false,
      ),
      PeriodoSalarial(
        fechaInicio: DateTime(2024, 2, 1),
        fechaTermino: DateTime(2025, 2, 1),
        salarioDiario: 2500.0,
        semanas: 52.4285714286,
        esMod40: false,
      ),
      PeriodoSalarial(
        fechaInicio: DateTime(2023, 2, 1),
        fechaTermino: DateTime(2024, 2, 1),
        salarioDiario: 2200.0,
        semanas: 52.2857142857,
        esMod40: false,
      ),
      PeriodoSalarial(
        fechaInicio: DateTime(2022, 2, 1),
        fechaTermino: DateTime(2023, 2, 1),
        salarioDiario: 2000.0,
        semanas: 52.2857142857,
        esMod40: false,
      ),
      PeriodoSalarial(
        fechaInicio: DateTime(2021, 7, 15),
        fechaTermino: DateTime(2022, 2, 1),
        salarioDiario: 1900.0,
        semanas: 28.8571428571,
        esMod40: false,
      ),
      PeriodoSalarial(
        fechaInicio: DateTime(2021, 1, 1),
        fechaTermino: DateTime(2021, 7, 15),
        salarioDiario: 1800.5,
        semanas: 10.4285714286,
        esMod40: false,
      ),
    ];
  }

  /// Reset periodos to the Excel baseline data.
  ///
  /// This replaces the current periodos with the baseline from
  /// [_createBaselinePeriodos] and recalculates all derived values.
  /// Use this when the user wants to reload the original Excel data.
  void resetPeriodosToBaseline() {
    // Ensure salario registrado is up-to-date before creating baseline periodos
    _projectSalarioRegistrado(force: true);
    _periodos = _createBaselinePeriodos();
    persistence.savePeriodos(_periodos);
    // Recalculate _salarioDiarioPromedio from baseline periods (Excel E19).
    _salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
    persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
    // Re-enable auto-projection since we're back to baseline
    _salarioPromAutoCalculado = true;
    // Recalculate all downstream values
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateCostoMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  // ===========================================================================
  // PERSIST ALL (explicit save button)
  // ===========================================================================

  /// Persist all current input values to SharedPreferences.
  ///
  /// Each individual setter already auto-saves its own field, but this method
  /// provides an explicit "save" action that guarantees ALL fields are persisted
  /// at once, useful as a user-facing confirmation button.
  Future<void> persistAll() async {
    persistence.saveFechaCalculo(_fechaCalculo);
    persistence.saveFechaNacimiento(_fechaNacimiento);
    persistence.saveSalarioDiarioPromedio(_salarioDiarioPromedio);
    persistence.saveUmaDiaria(_umaDiaria);
    persistence.saveSalarioMinimoDiario(_salarioMinimoDiario);
    persistence.savePensionYear(_pensionYear);
    persistence.saveSemanasCotizadas(_semanasCotizadas);
    persistence.saveTieneEsposa(_tieneEsposa);
    persistence.saveNumeroHijos(_numeroHijos);
    persistence.saveNumeroPadres(_numeroPadres);
    persistence.saveSalarioPromedio250Semanas(_salarioPromedio250Semanas);
    persistence.saveTotalSemanasSinMod40(_totalSemanasSinMod40);
    persistence.saveEdadRetiro(_edadRetiro);
    persistence.saveUmaMultiplier(_umaMultiplier);
    persistence.saveSalarioRegistrado(_salarioRegistrado);
    persistence.saveStartDate(_startDate);
    persistence.saveEndDate(_endDate);
    persistence.saveCostoModalidad40(_costoModalidad40);
    persistence.saveRetroactiveYears(_retroactiveYears);
    persistence.saveSemanasAntesMod40(_semanasAntesMod40);
    persistence.saveSemanasEnMod40(_semanasEnMod40);
    persistence.savePeriodos(_periodos);
  }

  /// Recalculate ALL calculations in the correct dependency order.
  ///
  /// This chains the results properly:
  /// 1. factAsig → pensionMod40
  /// 2. factAsigSinMod40 (separate sin Mod40 inputs)
  /// 3. costoMod40 → retroactivo (auto-chains inversionTotal)
  /// 4. inversion (uses threshold 0.501 rounding for edadRetiroSinMod40)
  /// 5. financiamiento (calculates SegundoFondeador internally)
  void recalculateAll() {
    _recalculateFactAsig();
    _recalculateFactAsigSinMod40();
    _recalculatePensionMod40();
    _recalculateCostoMod40();
    _recalculateRetroactivo();
    _recalculateInversion();
    _recalculateFinanciamiento();
    notifyListeners();
  }

  void _recalculateFinanciamiento() {
    if (!evaluator.isInitialized) return;
    try {
      // Calculate SegundoFondeador values internally (same as test does)
      final inversionTotal = _retroactiveCalculation?.costoTotal ?? 0;
      final aforeRecovery = _retroactiveCalculation?.recuperacionAfore ?? 0;
      final pensionMensualMejorada = _pensionMod40Calculation?.pensionMensual ?? 0;
      final sf = evaluator.calculateSegundoFondeador(
        inversionTotal: inversionTotal,
        pensionMensualMejorada: pensionMensualMejorada,
        aforeRecovery: aforeRecovery,
      );

      // edadRetiroSinMod40: edad de retiro SIN Modalidad 40 (for INVERSION D46 formula)
      // Without Mod40, the person would have retired 1 year earlier.
      // Excel INVERSION: D4 (sin Mod40) = 60, F4 (con Mod40) = 61 = D4+1
      final rules = evaluator.metadata.financialRules;
      // CORRECTED: Pass _edadRetiro as double (decimal value, e.g., 60.5) instead of
      // truncating to int (60). Excel FINANCIAMIENTO F7 formula uses the decimal
      // edad_retiro from 'DATOS GEN. MOD 40'!C12 in (80 - C12) calculation.
      // edadRetiroSinMod40 = roundToInteger(_edadRetiro) - 1 = 60 (igual que INVERSION D4).
      final edadSinMod40 = (rules.edadRoundingRule.roundToInteger(_edadRetiro) - 1).clamp(55, 65);

      _financiamientoCalculation = evaluator.calculateFinanciamiento(
        inversionTotal: inversionTotal,
        pensionMensualMejorada: pensionMensualMejorada,
        edadRetiro: _edadRetiro,
        pensionSinMod40: _factAsigSinMod40Calculation?.totalPensionMensual ?? 0,
        edadRetiroSinMod40: edadSinMod40,
        segundoFondeadorMontoCredito: sf.montoCredito,
        segundoFondeadorCostoFinanciamiento: sf.costoFinanciamiento,
        segundoFondeadorMontoMaximoPagar: sf.montoMaximoPagar,
        segundoFondeadorInversionRequerida: sf.inversionRequerida,
        segundoFondeadorAforeRecovery: sf.aforeRecovery,
      );
    } catch (e) {
      _financiamientoCalculation = null;
    }
  }
}
