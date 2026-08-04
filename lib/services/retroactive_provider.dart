import 'package:flutter/foundation.dart';
import '../core/engine/formula_evaluator.dart';
import '../core/models/pension_calculation.dart';
import '../core/models/periodo_salarial.dart';
import '../core/models/retroactive_calculation.dart';
import '../core/utils/error_handler.dart';
import '../core/utils/input_validator.dart';
import '../core/utils/pension_constants.dart';
import 'persistence_service.dart';
import 'retroactive/periodos_engine.dart';
import 'retroactive/retroactive_calculator.dart';
import 'retroactive/retroactive_inputs.dart';

/// Provider para el pipeline de cálculo de Pensión CON Modalidad 40 (Ley 73).
///
/// Responsabilidad única: **orquestar la fachada** — persistencia, proyecciones,
/// setters y notificaciones. La lógica de dominio está dividida por
/// responsabilidad única en:
///   1. [RetroactiveInputs]  — estado de inputs y valores derivados.
///   2. [PeriodosEngine]     — matemática pura del desglose de periodos.
///   3. [RetroactiveCalculator] — cadena de recálculo (resultados derivados).
///
/// Exposición pública preservada:
///   - Todos los getters y setters de inputs.
///   - `nuevoSalarioPromedio`, `availableAgesRetiro`, getters derivados.
///   - `initialize()`, `persistAll()`, `recalculateAll()`,
///     `resetPeriodosToBaseline()`, `setPeriodos()`, `updatePeriodo()`,
///     `addPeriodo()`, `removePeriodo()`.
class RetroactiveProvider extends ChangeNotifier {
  // ===========================================================================
  // DEPENDENCIAS
  // ===========================================================================

  final FormulaEvaluator evaluator;
  final PersistenceService persistence;

  /// Estado de inputs y valores derivados (módulo SRP 1).
  final RetroactiveInputs _inputs = RetroactiveInputs();

  /// Motor de matemática pura de periodos (módulo SRP 2).
  final PeriodosEngine _periodosEngine = PeriodosEngine();

  /// Cadena de recálculo (módulo SRP 3).
  late final RetroactiveCalculator _calculator = RetroactiveCalculator(
    evaluator: evaluator,
    inputs: _inputs,
  );

  /// Pensión sin M40 (constante de comparación).
  final double _pensionSinMod40 = 0;

  /// Tolerancia numérica para comparar la edad actual contra la edad de retiro
  /// (equivale a menos de 1 día y evita falsos negativos por punto flotante).
  static const double _edadRetiroEpsilon = 0.001;

  // --- UI state ---
  bool _isLoading = false;
  String? _errorMessage;

  /// True cuando initialize() cargó datos desde persistencia (no defaults).
  /// Lo usa CapturaView para mostrar un SnackBar "Configuración recuperada".
  bool _loadedFromPersistence = false;

  /// True cuando el desglose "antes Mod40" se fijó explícitamente (vía
  /// [setSemanasAntesMod40] / [setTotalSemanasSinMod40]); false cuando el
  /// TOTAL (semanasCotizadas) es la fuente primaria (vía [setSemanasCotizadas]).
  ///
  /// Reconciliar total vs. desglose (invariante total = antes + en):
  /// [setSemanasCotizadas] trata el total como primario (antes = total - en),
  /// mientras que [setSemanasEnMod40] trata "antes" como primario. El flag
  /// decide cuál gana dentro de [setSemanasEnMod40]:
  ///   - false (total primario): se PRESERVA el total tecleado y se re-deriva
  ///     antes (= total - v), de modo que el usuario vea el total exacto que
  ///     escribió (p. ej. 1300, no 1295 ni 1430).
  ///   - true (antes explícito): se conserva antes y total = antes + v.
  bool _semanasAntesMod40Explicit = false;

  RetroactiveProvider({
    required this.evaluator,
    required this.persistence,
  });

  // ===========================================================================
  // GETTERS — INPUTS
  // ===========================================================================

  double get salarioDiarioPromedio => _inputs.salarioDiarioPromedio;
  double get umaDiaria => _inputs.umaDiaria;
  double get salarioMinimoDiario => _inputs.salarioMinimoDiario;
  bool get umaSmAutoCalculated => _inputs.umaSmAutoCalculated;
  bool get salarioPromAutoCalculado => _inputs.salarioPromAutoCalculado;
  List<PeriodoSalarial> get periodos => List.unmodifiable(_inputs.periodos);
  int get pensionYear => _inputs.pensionYear;
  int get semanasCotizadas => _inputs.semanasCotizadas;
  bool get tieneEsposa => _inputs.tieneEsposa;
  int get numeroHijos => _inputs.numeroHijos;
  int get numeroPadres => _inputs.numeroPadres;

  double get salarioPromedio250Semanas => _inputs.salarioPromedio250Semanas;
  int get totalSemanasSinMod40 => _inputs.totalSemanasSinMod40;
  double get edadRetiro => _inputs.edadRetiro;

  double get umaMultiplier => _inputs.umaMultiplier;
  double get salarioRegistrado => _inputs.salarioRegistrado;
  DateTime get startDate => _inputs.startDate;
  DateTime get endDate => _inputs.endDate;

  double get costoModalidad40 => _inputs.costoModalidad40;
  double get retroactiveYears => _inputs.retroactiveYears;

  double get pensionMensualMejorada => _inputs.pensionMensualMejorada;

  double get pensionSinMod40 => _pensionSinMod40;

  // --- UI state getters ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get loadedFromPersistence => _loadedFromPersistence;

  // --- Fechas ---
  DateTime get fechaCalculo => _inputs.fechaCalculo;
  DateTime get fechaNacimiento => _inputs.fechaNacimiento;

  // --- Elegibilidad legal (Ley 73) ---

  /// Edad actual del usuario (años con fracción decimal), calculada entre
  /// [fechaNacimiento] y [fechaCalculo].
  double get edadActual =>
      InputValidator.calcularEdadActual(_inputs.fechaNacimiento, _inputs.fechaCalculo);

  /// Total de semanas cotizadas (antes Mod40 + en Mod40).
  int get totalSemanasCotizadas => _inputs.semanasCotizadas;

  /// True si se cumple el mínimo legal de 500 semanas (Art. 154/162 LSS 1973).
  bool get cumpleMinimoSemanas =>
      totalSemanasCotizadas >= PensionConstants.minSemanasLey73;

  /// True si el usuario ya alcanzó la edad de retiro seleccionada
  /// (la edad actual ya es >= a la edad de pensión elegida en el dropdown).
  ///
  /// Es únicamente informativo: la app es una herramienta de PROYECCIÓN, la
  /// pensión SIEMPRE se proyecta a la edad de retiro sin importar la edad
  /// actual.
  bool get cumpleEdadRetiro => edadActual >= _inputs.edadRetiro - _edadRetiroEpsilon;

  /// Años (con fracción decimal) que faltan para alcanzar la edad de retiro
  /// seleccionada (negativo si ya se superó). Se usa en los mensajes de
  /// proyección, p. ej. "Proyección a los 63 años (faltan 5.51 años)".
  double get anosFaltantesEdadRetiro => _inputs.edadRetiro - edadActual;

  /// Advertencias NO bloqueantes para la proyección de la pensión.
  ///
  /// Como la pensión se proyecta SIEMPRE a la edad de retiro, la edad actual
  /// nunca genera un requisito faltante. La única advertencia informativa
  /// (que NO impide calcular) es cuando no se alcanzan las 500 semanas
  /// mínimas (Arts. 154/162 LSS 1973), mismas que pueden cubrirse vía
  /// Modalidad 40.
  List<String> get requisitosPensionFaltantes {
    final faltantes = <String>[];
    if (!cumpleMinimoSemanas) {
      faltantes.add(
        'Mínimo 500 semanas cotizadas (actual: $totalSemanasCotizadas). '
        'Te faltan ${PensionConstants.minSemanasLey73 - totalSemanasCotizadas} semanas.',
      );
    }
    return faltantes;
  }

  // --- Semanas (desglose) ---
  double get semanasAntesMod40 => _inputs.semanasAntesMod40;
  double get semanasEnMod40 => _inputs.semanasEnMod40;

  /// Nuevo salario promedio calculado desde el desglose de periodos.
  ///
  /// Regla operativa para pensión con Mod40:
  /// - Considerar como máximo 250 semanas efectivas del desglose.
  /// - Si hay más de 250, recortar las semanas excedentes empezando por
  ///   los periodos más antiguos (se consume secuencialmente y el último
  ///   periodo puede quedar parcial).
  /// - El promedio se normaliza a base 250.
  ///
  /// Si no hay periodos definidos, retorna [salarioPromedio250Semanas].
  double get nuevoSalarioPromedio {
    return _calculateSalarioPromedioFromPeriodos();
  }

  /// Edades disponibles para el dropdown de retiro (desde metadata).
  /// Tanto el cálculo con-Mod40 como sin-Mod40 usan la misma lista unificada.
  /// p. ej. [60, 60.51, 61, 61.51, ..., 65]
  List<double> get availableAgesRetiro =>
      evaluator.metadata.financialRules.pensionAgeDropdown.availableAges;

  // ===========================================================================
  // GETTERS — DERIVED
  // ===========================================================================

  FactAsigCalculation? get factAsigCalculation => _calculator.factAsigCalculation;
  PensionMod40Calculation? get pensionMod40Calculation =>
      _calculator.pensionMod40Calculation;
  CostoMod40Calculation? get costoMod40Calculation =>
      _calculator.costoMod40Calculation;
  RetroactiveCalculation? get retroactiveCalculation =>
      _calculator.retroactiveCalculation;
  InversionCalculation? get inversionCalculation =>
      _calculator.inversionCalculation;
  FinanciamientoCalculation? get financiamientoCalculation =>
      _calculator.financiamientoCalculation;
  FactAsigCalculation? get factAsigSinMod40Calculation =>
      _calculator.factAsigSinMod40Calculation;

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
      _inputs.salarioDiarioPromedio = persistence.loadSalarioDiarioPromedio(
        defaultValue: defaults.salarioDiarioPromedio,
      );
      _inputs.umaDiaria = persistence.loadUmaDiaria(
        defaultValue: defaults.umaDiaria,
      );
      _inputs.salarioMinimoDiario = persistence.loadSalarioMinimoDiario(
        defaultValue: defaults.salarioMinimoDiario,
      );
      _inputs.pensionYear = persistence.loadPensionYear(
        defaultValue: defaults.pensionYear,
      );
      _inputs.semanasCotizadas = persistence.loadSemanasCotizadas(
        defaultValue: defaults.semanasCotizadas,
      );
      _inputs.tieneEsposa = persistence.loadTieneEsposa(
        defaultValue: defaults.tieneEsposa,
      );
      _inputs.numeroHijos = persistence.loadNumeroHijos(
        defaultValue: defaults.numeroHijos,
      );
      _inputs.numeroPadres = persistence.loadNumeroPadres(
        defaultValue: defaults.numeroPadres,
      );

      // Load persisted values with metadata defaults
      _inputs.salarioPromedio250Semanas = persistence.loadSalarioPromedio250Semanas(
        defaultValue: defaults.salarioPromedio250Semanas,
      );
      _inputs.totalSemanasSinMod40 = persistence.loadTotalSemanasSinMod40(
        defaultValue: defaults.totalSemanasSinMod40,
      );
      _inputs.edadRetiro = persistence.loadEdadRetiro(
        defaultValue: defaults.edadRetiro,
      );
      // Normalize any persisted off-grid age (e.g. legacy 60.5) onto the
      // legal grid [60, 60.51, ..., 65] so the dropdown never renders blank.
      final snappedAge =
          rules.pensionAgeDropdown.nearestAge(_inputs.edadRetiro);
      if (snappedAge != _inputs.edadRetiro) {
        _inputs.edadRetiro = snappedAge;
        persistence.saveEdadRetiro(snappedAge);
      }
      _inputs.umaMultiplier = persistence.loadUmaMultiplier(
        defaultValue: 25.0,
      );
      _inputs.salarioRegistrado = persistence.loadSalarioRegistrado(
        defaultValue: defaults.salarioRegistrado,
      );
      // Ensure salarioRegistrado is never 0; fall back to metadata default
      if (_inputs.salarioRegistrado <= 0) {
        _inputs.salarioRegistrado = defaults.salarioRegistrado;
        persistence.saveSalarioRegistrado(_inputs.salarioRegistrado);
      }
      _inputs.startDate = persistence.loadStartDate(
        defaultValue: DateTime(2027, 2, 1),
      );
      _inputs.endDate = persistence.loadEndDate(
        defaultValue: DateTime.now().add(const Duration(days: 365)),
      );
      // Ensure startDate/endDate are valid (endDate > startDate)
      if (_inputs.endDate.isBefore(_inputs.startDate) ||
          _inputs.endDate.isAtSameMomentAs(_inputs.startDate)) {
        _inputs.endDate = _inputs.startDate.add(const Duration(days: 365));
        persistence.saveEndDate(_inputs.endDate);
      }

      _inputs.costoModalidad40 = persistence.loadCostoModalidad40(
        defaultValue: defaults.retroactiveYears,
      );

      // Load semanas desglose (semanasEnMod40 needed before retroactiveYears default)
      _inputs.semanasAntesMod40 = persistence.loadSemanasAntesMod40(
        defaultValue: defaults.semanasAntesMod40,
      );
      _inputs.semanasEnMod40 = persistence.loadSemanasEnMod40(
        defaultValue: defaults.semanasEnMod40,
      );

      // RetroactiveYears: default = semanasEnMod40 converted to years (e.g. 130 sem = 2.5 años)
      _inputs.retroactiveYears = persistence.loadRetroactiveYears(
        defaultValue: _inputs.semanasEnMod40 / 52,
      );

      // Migration guard: semanasAntesMod40 is a user-captured input (Excel DATOS GEN)
      // and must stay aligned with totalSemanasSinMod40.
      // Older versions could overwrite semanasAntesMod40 from SAL. PROM periodos,
      // causing values around ~250 after app updates/reinstalls.
      // We only align both fields; we do not force business thresholds here
      // so user-captured values are always respected.
      final semanasAntesCanonicas = _inputs.totalSemanasSinMod40.toDouble();
      if (_inputs.semanasAntesMod40 != semanasAntesCanonicas) {
        _inputs.semanasAntesMod40 = semanasAntesCanonicas;
        persistence.saveSemanasAntesMod40(_inputs.semanasAntesMod40);
      }

      ErrorHandler.logDebug('Semanas antes Mod40 loaded: ${_inputs.semanasAntesMod40} (default was: ${defaults.semanasAntesMod40})');
      ErrorHandler.logDebug('Salario Promedio 250 Semanas loaded: ${_inputs.salarioPromedio250Semanas} (default was: ${defaults.salarioPromedio250Semanas})');

      // Load fechas
      _inputs.fechaCalculo = persistence.loadFechaCalculo(
        defaultValue: DateTime.now(),
      );
      _inputs.fechaNacimiento = persistence.loadFechaNacimiento(
        defaultValue: defaults.fechaNacimiento,
      );

      // Load periodos from persistence
      _inputs.periodos = persistence.loadPeriodos();

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
      if (_inputs.periodos.isEmpty) {
        _inputs.periodos = _createBaselinePeriodos();
        persistence.savePeriodos(_inputs.periodos);
        // Recalculate _salarioDiarioPromedio from seeded periods (Excel E19).
        _inputs.salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
        persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
        // Recalculate _salarioPromedio250Semanas from NON-Mod40 periods only
        final totalSemanasSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
        final totalResultadosSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
        _inputs.salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
        persistence.saveSalarioPromedio250Semanas(_inputs.salarioPromedio250Semanas);
        ErrorHandler.logDebug('Salario Promedio 250 Semanas calculated from seeded periodos: ${_inputs.salarioPromedio250Semanas} (totalSemanasSinMod40: $totalSemanasSinMod40, totalResultadosSinMod40: $totalResultadosSinMod40)');
        _inputs.salarioPromAutoCalculado = true;
      } else {
        // Recalculate _salarioDiarioPromedio from saved periods (Excel E19).
        _inputs.salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
        persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
        // Recalculate _salarioPromedio250Semanas from NON-Mod40 periods only
        final totalSemanasSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
        final totalResultadosSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
        _inputs.salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
        persistence.saveSalarioPromedio250Semanas(_inputs.salarioPromedio250Semanas);
        ErrorHandler.logDebug('Salario Promedio 250 Semanas calculated from saved periodos: ${_inputs.salarioPromedio250Semanas} (totalSemanasSinMod40: $totalSemanasSinMod40, totalResultadosSinMod40: $totalResultadosSinMod40)');
        // Periods were loaded from persistence (user's saved data).
        // Set auto-calculated to false so that _recalculatePromedioFromPeriodos
        // does NOT overwrite the user's manually-edited period values when
        // inputs like UMA, SM, edadRetiro, etc. change later.
        // The user's custom desglose de periodos must be preserved.
        _inputs.salarioPromAutoCalculado = false;
      }

      // IMPORTANT: semanasAntesMod40 is a user-captured input (Excel DATOS GEN).
      // Never derive it from SAL. PROM periodos.
      // Only keep semanasEnMod40 synchronized from Mod40-tagged periods.
      final semanasEnMod40 =
          _inputs.periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
      _inputs.semanasEnMod40 = semanasEnMod40;
      persistence.saveSemanasEnMod40(_inputs.semanasEnMod40);
      _inputs.semanasCotizadas = (_inputs.semanasAntesMod40 + _inputs.semanasEnMod40).toInt();
      persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);

      // Auto-calculate endDate from startDate + semanasEnMod40
      if (_inputs.semanasEnMod40 > 0) {
        _inputs.endDate = _inputs.startDate.add(Duration(days: (_inputs.semanasEnMod40 * 7).round()));
        persistence.saveEndDate(_inputs.endDate);
      }

      // Recalculate all (in dependency order)
      _calculator.recalcularTodo();

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
    if (v == _inputs.salarioDiarioPromedio) return;
    _inputs.salarioDiarioPromedio = v;
    // User manually edited → disable auto-projection
    _inputs.salarioPromAutoCalculado = false;
    persistence.saveSalarioDiarioPromedio(v);
    _calculator.recalcularFactAsig();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  void setUmaDiaria(double v) {
    if (v == _inputs.umaDiaria) return;
    _inputs.umaDiaria = v;
    // User manually edited → disable auto-projection
    _inputs.umaSmAutoCalculated = false;
    persistence.saveUmaDiaria(v);
    // Recalculate salario registrado from the new UMA value (25 × UMA)
    _projectSalarioRegistrado(force: true);
    // Recalculate Salario Promedio (con Mod40) with the new salarioRegistrado
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    notifyListeners();
  }

  void setSalarioMinimoDiario(double v) {
    if (v == _inputs.salarioMinimoDiario) return;
    _inputs.salarioMinimoDiario = v;
    // User manually edited → disable auto-projection
    _inputs.umaSmAutoCalculated = false;
    persistence.saveSalarioMinimoDiario(v);
    _calculator.recalcularFactAsig();
    _calculator.recalcularPensionMod40();
    notifyListeners();
  }

  void setPensionYear(int v) {
    if (v == _inputs.pensionYear) return;
    _inputs.pensionYear = v;
    persistence.savePensionYear(v);
    // Project UMA/SM for the new pension year (same as setEdadRetiro)
    _projectUmaSm(force: true);
    // Project salario registrado from UMAs (like Excel cell C12 = 25 × UMA)
    _projectSalarioRegistrado(force: true);
    // Recalculate Salario Promedio (con Mod40) with the new salarioRegistrado
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    // Recalculate Costo Mod40 with the new salarioRegistrado
    _calculator.recalcularCostoMod40();
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularInversion();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  void setSemanasCotizadas(int v) {
    if (v == _inputs.semanasCotizadas) return;
    // El total es la fuente primaria: al fijarlo se deriva antes. Desactiva el
    // modo "antes explícito" para que un setSemanasEnMod40 posterior PRESERVE
    // este total (antes = total - en) en lugar de sumar sobre antes.
    _semanasAntesMod40Explicit = false;
    // `semanasCotizadas` es el TOTAL = semanasAntesMod40 + semanasEnMod40.
    // Al fijar el total se deriva el componente "antes Mod40" (invariante
    // total = antes + en) y se alinea `totalSemanasSinMod40` para que la
    // guardia de migración de initialize() y las rutas de recomputación
    // (setPeriodos, setSemanasEnMod40, etc.) conserven el valor solicitado en
    // lugar de revertirlo al desglose anterior.
    final antesDerivado = (v - _inputs.semanasEnMod40).clamp(0.0, v.toDouble());
    _inputs.semanasAntesMod40 = antesDerivado.toDouble();
    persistence.saveSemanasAntesMod40(antesDerivado.toDouble());
    _inputs.totalSemanasSinMod40 = antesDerivado.toInt();
    persistence.saveTotalSemanasSinMod40(antesDerivado.toInt());
    _inputs.semanasCotizadas = v;
    persistence.saveSemanasCotizadas(v);
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  void setTieneEsposa(bool v) {
    if (v == _inputs.tieneEsposa) return;
    _inputs.tieneEsposa = v;
    persistence.saveTieneEsposa(v);
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    notifyListeners();
  }

  void setNumeroHijos(int v) {
    if (v == _inputs.numeroHijos) return;
    _inputs.numeroHijos = v;
    persistence.saveNumeroHijos(v);
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    notifyListeners();
  }

  void setNumeroPadres(int v) {
    if (v == _inputs.numeroPadres) return;
    _inputs.numeroPadres = v;
    persistence.saveNumeroPadres(v);
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    notifyListeners();
  }

  void setSalarioPromedio250Semanas(double v) {
    if (v == _inputs.salarioPromedio250Semanas) return;
    _inputs.salarioPromedio250Semanas = v;
    persistence.saveSalarioPromedio250Semanas(v);
    // Update all non-Mod40 periods to use this new salary value
    bool anyChanged = false;
    for (int i = 0; i < _inputs.periodos.length; i++) {
      final p = _inputs.periodos[i];
      if (!p.esMod40) {
        final nuevoSalario = _inputs.salarioPromedio250Semanas;
        if (p.salarioDiario != nuevoSalario) {
          _inputs.periodos[i] = PeriodoSalarial(
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
      persistence.savePeriodos(_inputs.periodos);
      // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
      final semanasEnMod40 =
          _inputs.periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
      _inputs.semanasEnMod40 = semanasEnMod40;
      persistence.saveSemanasEnMod40(_inputs.semanasEnMod40);
      _inputs.semanasCotizadas = (_inputs.semanasAntesMod40 + _inputs.semanasEnMod40).toInt();
      persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);
      _inputs.salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
      persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
    }
    // Recalculate all dependent values
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  /// Setter for the periodos list.
  ///
  /// When the user manually sets the full periodos list (e.g. from persistence
  /// or manual edit), auto-projection is disabled so that
  /// [_recalculatePromedioFromPeriodos] does NOT overwrite the user's custom
  /// period values later (e.g. when [setSalarioPromedio250Semanas] is called).
  void setPeriodos(List<PeriodoSalarial> periodos) {
    _inputs.periodos = List.from(periodos);
    persistence.savePeriodos(_inputs.periodos);
    // User manually set periods → disable auto-projection
    _inputs.salarioPromAutoCalculado = false;
    // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
    final semanasEnMod40 =
        _inputs.periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
    _inputs.semanasEnMod40 = semanasEnMod40;
    persistence.saveSemanasEnMod40(_inputs.semanasEnMod40);
    // Update total cotizadas semanas
    _inputs.semanasCotizadas = (_inputs.semanasAntesMod40 + _inputs.semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);
    // Recalculate Salario Promedio from the new periods (Excel E19).
    _inputs.salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
    persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
    // Recalculate Salario Promedio 250 Semanas from NON-Mod40 periods only
    final totalSemanasSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
    final totalResultadosSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
    _inputs.salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
    persistence.saveSalarioPromedio250Semanas(_inputs.salarioPromedio250Semanas);

    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  /// Update a single period at [index].
  ///
  /// When the user manually edits a period (salarioDiario or semanas),
  /// auto-projection is disabled so that [_recalculatePromedioFromPeriodos]
  /// does NOT overwrite the user's manual edits later (e.g. when
  /// [setSalarioPromedio250Semanas] is called).
  void updatePeriodo(int index, PeriodoSalarial periodo) {
    if (index < 0 || index >= _inputs.periodos.length) return;
    _inputs.periodos[index] = periodo;
    persistence.savePeriodos(_inputs.periodos);
    // User manually edited → disable auto-projection so _recalculatePromedioFromPeriodos
    // won't overwrite the user's custom period values later.
    _inputs.salarioPromAutoCalculado = false;
    // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
    final semanasEnMod40 =
        _inputs.periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
    _inputs.semanasEnMod40 = semanasEnMod40;
    persistence.saveSemanasEnMod40(_inputs.semanasEnMod40);
    ErrorHandler.logDebug('Semanas Mod40 actualizadas:');
    ErrorHandler.logDebug('  - Valor calculado: $semanasEnMod40');
    ErrorHandler.logDebug('  - Valor asignado: ${_inputs.semanasEnMod40}');
    // Update total cotizadas semanas
    _inputs.semanasCotizadas = (_inputs.semanasAntesMod40 + _inputs.semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);
    // Recalculate Salario Promedio from the updated periods (Excel E19).
    _inputs.salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
    persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
    // Calculate Salario Promedio 250 Semanas from NON-Mod40 periods only (per user request: Desglose Sal. Prom without M40)
    if (_inputs.periodos.isNotEmpty) {
      final totalSemanasSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.semanas : 0));
      final totalResultadosSinMod40 = _inputs.periodos.fold<double>(0, (sum, p) => sum + (!p.esMod40 ? p.resultado : 0));
      _inputs.salarioPromedio250Semanas = totalSemanasSinMod40 > 0 ? totalResultadosSinMod40 / totalSemanasSinMod40 : 0;
      persistence.saveSalarioPromedio250Semanas(_inputs.salarioPromedio250Semanas);
    }

    ErrorHandler.logDebug('  - Semanas en Mod40: $semanasEnMod40');
    ErrorHandler.logDebug('  - Salario Promedio 250 Semanas: ${_inputs.salarioPromedio250Semanas}');
    ErrorHandler.logDebug('  - Salario Diario Promedio: ${_inputs.salarioDiarioPromedio}');

    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  /// Add a new empty period to the list.
  ///
  /// When the user manually adds a period, auto-projection is disabled so that
  /// [_recalculatePromedioFromPeriodos] does NOT overwrite the user's custom
  /// period values later (e.g. when [setSalarioPromedio250Semanas] is called).
  void addPeriodo() {
    _inputs.periodos.add(PeriodoSalarial(
      salarioDiario: 0.0,
      semanas: 0.0,
      esMod40: false,
    ));
    persistence.savePeriodos(_inputs.periodos);
    // User manually added a period → disable auto-projection
    _inputs.salarioPromAutoCalculado = false;
    notifyListeners();
  }

  /// Remove a period at [index].
  ///
  /// When the user manually removes a period, auto-projection is disabled so
  /// that [_recalculatePromedioFromPeriodos] does NOT overwrite the user's
  /// custom period values later (e.g. when [setSalarioPromedio250Semanas] is
  /// called).
  void removePeriodo(int index) {
    if (index < 0 || index >= _inputs.periodos.length) return;
    _inputs.periodos.removeAt(index);
    persistence.savePeriodos(_inputs.periodos);
    // User manually removed a period → disable auto-projection
    _inputs.salarioPromAutoCalculado = false;
    // Recalculate Mod40 weeks only; semanasAntesMod40 stays user-controlled.
    final semanasEnMod40 =
        _inputs.periodos.fold<double>(0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
    _inputs.semanasEnMod40 = semanasEnMod40;
    persistence.saveSemanasEnMod40(_inputs.semanasEnMod40);
    // Update total cotizadas semanas
    _inputs.semanasCotizadas = (_inputs.semanasAntesMod40 + _inputs.semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);
    // Recalculate Salario Promedio after removal
    _inputs.salarioDiarioPromedio = nuevoSalarioPromedio;
    persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  void setTotalSemanasSinMod40(int v) {
    if (v == _inputs.totalSemanasSinMod40) return;
    // Desglose explícito → "antes" es la fuente primaria (total = antes + en).
    _semanasAntesMod40Explicit = true;
    _inputs.totalSemanasSinMod40 = v;
    persistence.saveTotalSemanasSinMod40(v);
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  Future<void> setEdadRetiro(double v) async {
    // Coerce any value onto the legal grid [60, 60.51, ..., 65] so the
    // dropdown never holds an off-grid age (e.g. 60.5) that renders blank.
    // Root fix for "Mueve la edad a 60.5 años" → blank in Captura.
    //
    // En producción el evaluador siempre está inicializado (provider.initialize()
    // corre antes que cualquier setter). La guarda solo cubre los unit tests
    // que ejercen setters sobre un provider sin inicializar.
    final dropdown = evaluator.isInitialized
        ? evaluator.metadata.financialRules.pensionAgeDropdown
        : null;
    final snapped = dropdown?.nearestAge(v) ?? v;
    if (snapped == _inputs.edadRetiro) return;
    _inputs.edadRetiro = snapped;
    persistence.saveEdadRetiro(snapped);

    // Recalculate pensionYear from fechaNacimiento + edadRetiro
    _inputs.pensionYear = _inputs.fechaNacimiento.year + _inputs.edadRetiro.floor();
    persistence.savePensionYear(_inputs.pensionYear);

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
    _calculator.recalcularCostoMod40();
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularInversion();
    _calculator.recalcularFinanciamiento();

    notifyListeners();
  }

  /// Set UMA multiplier (1-25). Recalculates salario registrado and all
  /// downstream calculations.
  void setUmaMultiplier(double v) {
    final clamped = v.clamp(1.0, 25.0);
    if (clamped == _inputs.umaMultiplier) return;
    _inputs.umaMultiplier = clamped;
    persistence.saveUmaMultiplier(clamped);
    // Force re-project salario registrado from new multiplier × UMA
    _projectSalarioRegistrado(force: true);
    // Recalculate all downstream values
    _recalculatePromedioFromPeriodos();
    _calculator.recalcularCostoMod40();
    _calculator.recalcularFactAsig();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularInversion();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  void setSalarioRegistrado(double v) {
    if (v == _inputs.salarioRegistrado) return;
    _inputs.salarioRegistrado = v;
    // User manually edited → disable auto-projection
    _inputs.salarioPromAutoCalculado = false;
    persistence.saveSalarioRegistrado(v);
    // Recalculate Salario Promedio (con Mod40) when the registered salary changes
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _calculator.recalcularCostoMod40();
    _calculator.recalcularFactAsig();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularInversion();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  void setStartDate(DateTime v) {
    if (v == _inputs.startDate) return;
    _inputs.startDate = v;
    persistence.saveStartDate(v);
    // Auto-calculate endDate from new startDate + semanasEnMod40
    if (_inputs.semanasEnMod40 > 0) {
      _inputs.endDate = _inputs.startDate.add(Duration(days: (_inputs.semanasEnMod40 * 7).round()));
      persistence.saveEndDate(_inputs.endDate);
    }
    _calculator.recalcularCostoMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  void setEndDate(DateTime v) {
    if (v == _inputs.endDate) return;
    _inputs.endDate = v;
    persistence.saveEndDate(v);
    _calculator.recalcularCostoMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  void setCostoModalidad40(double v) {
    if (v == _inputs.costoModalidad40) return;
    _inputs.costoModalidad40 = v;
    persistence.saveCostoModalidad40(v);
    _calculator.recalcularRetroactivo();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  void setRetroactiveYears(double v) {
    if (v == _inputs.retroactiveYears) return;
    _inputs.retroactiveYears = v;
    persistence.saveRetroactiveYears(v);
    _calculator.recalcularRetroactivo();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  void setPensionMensualMejorada(double v) {
    if (v == _inputs.pensionMensualMejorada) return;
    _inputs.pensionMensualMejorada = v;
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  // --- Fecha setters ---
  void setFechaCalculo(DateTime v) {
    _inputs.fechaCalculo = v;
    persistence.saveFechaCalculo(v);
    notifyListeners();
  }

  void setFechaNacimiento(DateTime v) {
    _inputs.fechaNacimiento = v;
    persistence.saveFechaNacimiento(v);

    // Recalculate pensionYear from fechaNacimiento + edadRetiro
    _inputs.pensionYear = _inputs.fechaNacimiento.year + _inputs.edadRetiro.floor();
    persistence.savePensionYear(_inputs.pensionYear);

    // Always project UMA and Salario Mínimo when fechaNacimiento changes,
    // regardless of _umaSmAutoCalculated (same reasoning as setEdadRetiro).
    _projectUmaSm(force: true);
    // Project salario registrado from UMAs (like Excel cell C12 = 25 × UMA)
    _projectSalarioRegistrado(force: true);
    // Recalculate Salario Promedio (con Mod40) with the new salarioRegistrado
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    // Recalculate Costo Mod40 with the new salarioRegistrado
    _calculator.recalcularCostoMod40();

    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularInversion();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  // --- Semanas (desglose) setters ---
  void setSemanasAntesMod40(double v) {
    if (v == _inputs.semanasAntesMod40) return;
    // Desglose explícito → "antes" es la fuente primaria (total = antes + en).
    _semanasAntesMod40Explicit = true;
    _inputs.semanasAntesMod40 = v;
    persistence.saveSemanasAntesMod40(v);
    // Recalculate total semanas sin Mod40
    _inputs.totalSemanasSinMod40 = v.toInt();
    persistence.saveTotalSemanasSinMod40(_inputs.totalSemanasSinMod40);
    // Recalculate total semanas con Mod40 (semanasCotizadas = antes + en)
    _inputs.semanasCotizadas = (v + _inputs.semanasEnMod40).toInt();
    persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);
    // Recalculate Salario Promedio (con Mod40) when the weight distribution changes
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _calculator.recalcularFactAsig();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularInversion();
    notifyListeners();
  }

  void setSemanasEnMod40(double v) {
    if (v == _inputs.semanasEnMod40) return;
    _inputs.semanasEnMod40 = v;
    persistence.saveSemanasEnMod40(v);
    // Escalar las semanas de los periodos Mod40 para que sumen v. Esto hace que
    // el valor capturado persista: _recalculatePromedioFromPeriodos() re-deriva
    // semanasEnMod40 desde los periodos, así que mantener periodos y escalar en
    // sincronía evita que el valor se revierta silenciosamente (p. ej. los
    // periodos baseline traen 134.714 semanas Mod40 en vez del default 130).
    if (_inputs.periodos.isNotEmpty) {
      final totalActual = _inputs.periodos.fold<double>(
          0, (sum, p) => sum + (p.esMod40 ? p.semanas : 0));
      if (totalActual > 0 && (totalActual - v).abs() > 0.0001) {
        final factor = v / totalActual;
        _inputs.periodos = [
          for (final p in _inputs.periodos)
            if (p.esMod40)
              PeriodoSalarial(
                fechaInicio: p.fechaInicio,
                fechaTermino: p.fechaTermino,
                salarioDiario: p.salarioDiario,
                semanas: p.semanas * factor,
                esMod40: true,
              )
            else
              p,
        ];
        persistence.savePeriodos(_inputs.periodos);
      }
    }
    // Reconciliar total vs. desglose (invariante total = antes + en).
    if (_semanasAntesMod40Explicit) {
      // "antes" es primario (desglose explícito): conservar antes y derivar el
      // total = antes + en.
      _inputs.semanasCotizadas = (_inputs.semanasAntesMod40 + v).toInt();
      persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);
    } else {
      // El total es primario (p. ej. flujo guiado: el usuario tecleó primero el
      // total y después las semanas Mod40): PRESERVAR el total y re-derivar
      // antes = total - v, para que el valor que escribió el usuario (1300) no
      // se pierda en 1295 o se infle a 1430.
      final total = _inputs.semanasCotizadas.toDouble();
      final antes = (total - v).clamp(0.0, total);
      _inputs.semanasAntesMod40 = antes;
      persistence.saveSemanasAntesMod40(antes);
      _inputs.totalSemanasSinMod40 = antes.toInt();
      persistence.saveTotalSemanasSinMod40(antes.toInt());
      // semanasCotizadas (el total) NO se modifica: queda en el valor tecleado.
    }
    // Auto-calculate endDate from startDate + semanasEnMod40
    if (v > 0) {
      _inputs.endDate = _inputs.startDate.add(Duration(days: (v * 7).round()));
      persistence.saveEndDate(_inputs.endDate);
    }
    // Recalculate Salario Promedio (con Mod40) when the weight distribution changes
    // WITHOUT overwriting the user's desglose de periodos.
    _recalculatePromedioFromPeriodos();
    _calculator.recalcularFactAsig();
    _calculator.recalcularPensionMod40();
    _calculator.recalcularCostoMod40();
    _calculator.recalcularRetroactivo();
    _calculator.recalcularInversion();
    _calculator.recalcularFinanciamiento();
    notifyListeners();
  }

  // ===========================================================================
  // PROJECTIONES
  // ===========================================================================

  /// Auto-project UMA and Salario Mínimo from the current pensionYear.
  ///
  /// When [force] is `false` (default), only projects if the user has NOT
  /// manually overridden the values (i.e. [_inputs.umaSmAutoCalculated] is true).
  /// When [force] is `true`, always projects regardless of the flag — this
  /// is used when the pension year itself has changed (via [setEdadRetiro]
  /// or [setFechaNacimiento]), because the projected values must match the
  /// new year. The flag is also reset to `true` so subsequent auto-projection
  /// continues to work.
  void _projectUmaSm({bool force = false}) {
    if (!force && !_inputs.umaSmAutoCalculated) return;
    if (!evaluator.isInitialized) return;
    final rules = evaluator.metadata.financialRules;
    _inputs.umaDiaria = evaluator.getProjectedUma(_inputs.pensionYear, rules);
    _inputs.salarioMinimoDiario = evaluator.getProjectedMinWage(_inputs.pensionYear, rules);
    persistence.saveUmaDiaria(_inputs.umaDiaria);
    persistence.saveSalarioMinimoDiario(_inputs.salarioMinimoDiario);
    // Re-enable auto-projection so future changes keep working
    _inputs.umaSmAutoCalculated = true;
  }

  /// Project salario registrado as [umaMultiplier] × UMA diaria (like Excel cell C12).
  /// Called after [_projectUmaSm] to ensure [_inputs.umaDiaria] is current.
  void _projectSalarioRegistrado({bool force = false}) {
    if (!force && !_inputs.salarioPromAutoCalculado) return;
    final nuevoSalario = _inputs.umaMultiplier * _inputs.umaDiaria;
    if (nuevoSalario != _inputs.salarioRegistrado) {
      _inputs.salarioRegistrado = nuevoSalario;
      persistence.saveSalarioRegistrado(_inputs.salarioRegistrado);
      if (_inputs.periodos.isNotEmpty) {
        _updateMod40PeriodsWithNewSalary();
      }
    }
  }

  void _updateMod40PeriodsWithNewSalary() {
    bool anyChanged = false;
    for (int i = 0; i < _inputs.periodos.length; i++) {
      final p = _inputs.periodos[i];
      if (p.esMod40 && p.salarioDiario != _inputs.salarioRegistrado) {
        _inputs.periodos[i] = PeriodoSalarial(
          fechaInicio: p.fechaInicio,
          fechaTermino: p.fechaTermino,
          salarioDiario: _inputs.salarioRegistrado,
          semanas: p.semanas,
          esMod40: true,
        );
        anyChanged = true;
        ErrorHandler.logDebug('Periodo Mod40 actualizado con salario: ${_inputs.salarioRegistrado}');
      }
    }
    if (anyChanged) {
      persistence.savePeriodos(_inputs.periodos);
      _recalculatePromedioFromPeriodos();
      notifyListeners();
    }
  }

  /// Calculate Salario Promedio (con Mod40) from periodos using a 250-week cap.
  ///
  /// The calculation consumes period weeks in order and only takes up to
  /// totalSemanasPromedio (250 by metadata). Extra historical periods are
  /// ignored for the pension base. Si no hay periodos, retorna
  /// [salarioPromedio250Semanas].
  double _calculateSalarioPromedioFromPeriodos() {
    final totalSemanasPromedio =
        evaluator.metadata.financialRules.totalSemanasPromedio.toDouble();
    return _periodosEngine.promedioDesdePeriodos(
      _inputs.periodos,
      totalSemanasPromedio: totalSemanasPromedio,
      fallback: _inputs.salarioPromedio250Semanas,
    );
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
    if (_inputs.periodos.isNotEmpty) {
      // Update salarios usando estas reglas:
      // - Mod40 periods always follow _salarioRegistrado (derived from UMA).
      // - non-Mod40 periods are NEVER updated by this method when called from
      //   age changes. They are only updated when the user explicitly changes
      //   _salarioPromedio250Semanas.
      final result = _periodosEngine.actualizarSalariosDePeriodos(
        _inputs.periodos,
        salarioRegistrado: _inputs.salarioRegistrado,
        actualizarNoMod40: false,
      );
      if (result.anyChanged) {
        _inputs.periodos = result.periodos;
        persistence.savePeriodos(_inputs.periodos);
      }

      // Recalculate weighted average from periods using Excel E19.
      _inputs.salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
      persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);

      // Recalculate Semanas en Mod40 (always)
      _inputs.semanasEnMod40 = _periodosEngine.semanasEnMod40(_inputs.periodos);
      persistence.saveSemanasEnMod40(_inputs.semanasEnMod40);
    } else {
      // No periods defined — use the base 250-week average
      _inputs.salarioDiarioPromedio = _inputs.salarioPromedio250Semanas;
      persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
    }

    // Trigger recalculations for dependent fields
    _calculator.recalcularFactAsig();
    _calculator.recalcularFactAsigSinMod40();
    _calculator.recalcularPensionMod40();
    notifyListeners();
  }

  /// Create the baseline periodos list from Excel "SAL. PROM MOD 40" data.
  ///
  /// Valores que coinciden con la hoja de cálculo (ver [PeriodosEngine.crearBaseline]).
  /// Se usa en el primer arranque (sin datos guardados) para poblar el
  /// Desglose Sal. Prom con datos reales del Excel.
  List<PeriodoSalarial> _createBaselinePeriodos() {
    return _periodosEngine.crearBaseline(_inputs.salarioRegistrado);
  }

  /// Reset periodos to the Excel baseline data.
  ///
  /// This replaces the current periodos with the baseline from
  /// [_createBaselinePeriodos] and recalculates all derived values.
  /// Use this when the user wants to reload the original Excel data.
  void resetPeriodosToBaseline() {
    // Ensure salario registrado is up-to-date before creating baseline periodos
    _projectSalarioRegistrado(force: true);
    _inputs.periodos = _createBaselinePeriodos();
    persistence.savePeriodos(_inputs.periodos);
    // Recalculate _salarioDiarioPromedio from baseline periods (Excel E19).
    _inputs.salarioDiarioPromedio = _calculateSalarioPromedioFromPeriodos();
    persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
    // Re-enable auto-projection since we're back to baseline
    _inputs.salarioPromAutoCalculado = true;
    // Recalculate all downstream values
    _calculator.recalcularTodo();
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
    persistence.saveFechaCalculo(_inputs.fechaCalculo);
    persistence.saveFechaNacimiento(_inputs.fechaNacimiento);
    persistence.saveSalarioDiarioPromedio(_inputs.salarioDiarioPromedio);
    persistence.saveUmaDiaria(_inputs.umaDiaria);
    persistence.saveSalarioMinimoDiario(_inputs.salarioMinimoDiario);
    persistence.savePensionYear(_inputs.pensionYear);
    persistence.saveSemanasCotizadas(_inputs.semanasCotizadas);
    persistence.saveTieneEsposa(_inputs.tieneEsposa);
    persistence.saveNumeroHijos(_inputs.numeroHijos);
    persistence.saveNumeroPadres(_inputs.numeroPadres);
    persistence.saveSalarioPromedio250Semanas(_inputs.salarioPromedio250Semanas);
    persistence.saveTotalSemanasSinMod40(_inputs.totalSemanasSinMod40);
    persistence.saveEdadRetiro(_inputs.edadRetiro);
    persistence.saveUmaMultiplier(_inputs.umaMultiplier);
    persistence.saveSalarioRegistrado(_inputs.salarioRegistrado);
    persistence.saveStartDate(_inputs.startDate);
    persistence.saveEndDate(_inputs.endDate);
    persistence.saveCostoModalidad40(_inputs.costoModalidad40);
    persistence.saveRetroactiveYears(_inputs.retroactiveYears);
    persistence.saveSemanasAntesMod40(_inputs.semanasAntesMod40);
    persistence.saveSemanasEnMod40(_inputs.semanasEnMod40);
    persistence.savePeriodos(_inputs.periodos);
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
    _calculator.recalcularTodo();
    notifyListeners();
  }
}
