import '../../core/models/periodo_salarial.dart';

/// Contenedor de estado de los inputs y valores derivados del pipeline de
/// cálculo de Pensión CON Modalidad 40 (Ley 73).
///
/// Responsabilidad única: **mantener el estado** de los campos de entrada y de
/// los valores derivados que participan como entrada de la cadena de cálculo
/// (p. ej. `salarioDiarioPromedio`, `semanasEnMod40`, `semanasCotizadas`).
///
/// No contiene lógica de negocio, persistencia ni notificaciones. La fachada
/// [`RetroactiveProvider`](../retroactive_provider.dart) es quien orquesta la
/// persistencia, las proyecciones y la cadena de recálculo a partir de este
/// estado.
class RetroactiveInputs {
  // --- Fact. + Asig. (compartidos) ---
  double salarioDiarioPromedio = 0;
  double umaDiaria = 0;
  double salarioMinimoDiario = 0;
  int pensionYear = DateTime.now().year + 1;
  int semanasCotizadas = 0;
  bool tieneEsposa = false;
  int numeroHijos = 0;
  int numeroPadres = 0;

  // --- Pensión SIN M40 (para comparación) ---
  double salarioPromedio250Semanas = 0;
  int totalSemanasSinMod40 = 0;

  // --- Pensión (unificada: con M40 y sin M40 usan la misma edad retiro) ---
  double edadRetiro = 65;

  // --- COSTO MOD. 40 ---
  double umaMultiplier = 25.0; // 1-25, configurable por el usuario
  double salarioRegistrado = 0;
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now().add(const Duration(days: 365));

  // --- PAGO RETROACTIVO ---
  double costoModalidad40 = 0;
  double retroactiveYears = 0;

  // --- FINANCIAMIENTO ---
  double pensionMensualMejorada = 0;

  // --- Banderas de proyección automática ---
  // true: UMA/SM se proyectan automáticamente desde pensionYear.
  // false: el usuario editó manualmente UMA o SM.
  bool umaSmAutoCalculated = true;

  // true: Salario Promedio (con Mod40) se calcula automáticamente como
  // promedio ponderado desde el desglose de periodos.
  // false: el usuario editó manualmente el campo o el desglose.
  bool salarioPromAutoCalculado = true;

  // --- Periodos (desglose SAL. PROM MOD 40) ---
  List<PeriodoSalarial> periodos = [];

  // --- Fechas ---
  DateTime fechaCalculo = DateTime.now();
  DateTime fechaNacimiento = DateTime.now();

  /// Fecha en que el trabajador se dio de alta en el IMSS (empezó a cotizar).
  /// Opcional: se usa para confirmar la aplicabilidad de la Ley 73.
  DateTime? fechaAlta;

  /// Fecha en que el trabajador dejó de cotizar (baja del IMSS).
  /// Opcional: se usa para calcular la vigencia/conservación de derechos
  /// (Art. 150 LSS 1973). `null` = no capturada (la regla no se evalúa).
  DateTime? fechaUltimaCotizacion;

  // --- Semanas (desglose) ---
  double semanasAntesMod40 = 0;
  double semanasEnMod40 = 0;

  // true: el usuario NO hará aportaciones voluntarias de Modalidad 40.
  // false: Modalidad 40 activa (comportamiento actual).
  bool modalidad40OptOut = false;
}
