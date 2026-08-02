/// Result model for the FACT. + ASIG. MOD.40 calculation.
/// Replicates the Excel sheet logic for cuantía básica, incrementos anuales,
/// asignaciones familiares, and total pension.
class FactAsigCalculation {
  // --- Elementos Clave ---
  final double salarioDiarioPromedio;
  final double umaDiaria;
  final double salarioMinimoDiario;
  final double salarioEnUMAs;
  final int pensionYear;

  // --- Cuantía Básica ---
  final double porcentajeCuantiaBasica;
  final double cuantiaBasicaPorDia;
  final double totalCuantiaBasicaAnual;

  // --- Incrementos Anuales ---
  final double porcentajeIncremento;
  final double incrementosDiarios;
  final double incrementoAnual;
  final double numeroIncrementosAnuales;
  final double numeroIncrementosRedondeado;
  final double totalIncrementosAnuales;

  // --- Cuantía Total Pensión Vejez ---
  final double cuantiaTotalPensionVejez;

  // --- Asignaciones Familiares ---
  final bool tieneEsposa;
  final double asignacionEsposa;
  final int numeroHijos;
  final double asignacionHijos;
  final int numeroPadres;
  final double asignacionPadres;
  final double cuantiaTotalAsignaciones;

  // --- Ayuda Asistencial ---
  final bool aplicaAyudaAsistencial;
  final double porcentajeAyudaAsistencial;
  final double totalAyudaAsistencial;

  // --- Decreto Presidencial ---
  final double cuantiaMasAsignaciones;
  final double asignacionDecretoPresidencial;

  // --- Totales Finales ---
  final double totalPensionAnual;
  final double totalPensionMensual;

  FactAsigCalculation({
    required this.salarioDiarioPromedio,
    required this.umaDiaria,
    required this.salarioMinimoDiario,
    required this.salarioEnUMAs,
    required this.pensionYear,
    required this.porcentajeCuantiaBasica,
    required this.cuantiaBasicaPorDia,
    required this.totalCuantiaBasicaAnual,
    required this.porcentajeIncremento,
    required this.incrementosDiarios,
    required this.incrementoAnual,
    required this.numeroIncrementosAnuales,
    required this.numeroIncrementosRedondeado,
    required this.totalIncrementosAnuales,
    required this.cuantiaTotalPensionVejez,
    required this.tieneEsposa,
    required this.asignacionEsposa,
    required this.numeroHijos,
    required this.asignacionHijos,
    required this.numeroPadres,
    required this.asignacionPadres,
    required this.cuantiaTotalAsignaciones,
    required this.aplicaAyudaAsistencial,
    required this.porcentajeAyudaAsistencial,
    required this.totalAyudaAsistencial,
    required this.cuantiaMasAsignaciones,
    required this.asignacionDecretoPresidencial,
    required this.totalPensionAnual,
    required this.totalPensionMensual,
  });
}

/// Result model for PENSION MOD. 40 calculation.
class PensionMod40Calculation {
  final double pensionAnual100;
  final double edadRetiro;
  final double porcentajePorEdad;
  final String tipoPension;
  final double pensionMinimaGarantizada;
  final bool aplicaMinima;
  final double pensionAnualFinal;
  final double pensionMensual;

  PensionMod40Calculation({
    required this.pensionAnual100,
    required this.edadRetiro,
    required this.porcentajePorEdad,
    required this.tipoPension,
    required this.pensionMinimaGarantizada,
    required this.aplicaMinima,
    required this.pensionAnualFinal,
    required this.pensionMensual,
  });
}

/// Result model for COSTO MOD. 40 calculation.
class CostoMod40Calculation {
  final List<CostoYearRow> yearlyCosts;
  final double inversionTotal;
  final double recuperacionAfore;
  final double inversionNeta;

  CostoMod40Calculation({
    required this.yearlyCosts,
    required this.inversionTotal,
    required this.recuperacionAfore,
    required this.inversionNeta,
  });

  /// Convenience getter for views that reference costoTotal
  double get costoTotal => inversionTotal;
}

class CostoYearRow {
  final String label;
  final int yearStart;
  final int? yearEnd;
  final double salarioRegistrado;
  final double tasa;
  final int diasPagados;
  final double cuotaMensual;
  final double cuotaAnual;

  CostoYearRow({
    required this.label,
    required this.yearStart,
    this.yearEnd,
    required this.salarioRegistrado,
    required this.tasa,
    required this.diasPagados,
    required this.cuotaMensual,
    required this.cuotaAnual,
  });
}

/// Result model for INVERSION calculation.
class InversionCalculation {
  final int edadRetiroSinMod40;
  final int edadRetiroConMod40;
  final double pensionMensualSinMod40;
  final double pensionMensualConMod40;
  final double mejoraPension;
  final double periodosRecuperacionMeses;
  final double flujoHasta80SinMod40;
  final double flujoHasta80ConMod40;
  final double gananciaTotal;
  final double tasaRendimiento;
  final String veredicto;
  final double inversionNeta;
  final double recuperacionAfore;

  InversionCalculation({
    required this.edadRetiroSinMod40,
    required this.edadRetiroConMod40,
    required this.pensionMensualSinMod40,
    required this.pensionMensualConMod40,
    required this.mejoraPension,
    required this.periodosRecuperacionMeses,
    required this.flujoHasta80SinMod40,
    required this.flujoHasta80ConMod40,
    required this.gananciaTotal,
    required this.tasaRendimiento,
    required this.veredicto,
    this.inversionNeta = 0,
    this.recuperacionAfore = 0,
  });

  // Convenience getters for views that use different naming
  double get pensionSinMod40 => pensionMensualSinMod40;
  double get periodoRecuperacionMeses => periodosRecuperacionMeses;
}

/// Result model for FINANCIAMIENTO calculation.
class FinanciamientoCalculation {
  final double inversionTotal;
  final double participacionBanco;
  final double participacionPropia;
  final double porcentajeBanco;
  final double porcentajePropio;
  final double montoCredito;
  final int duracionTramiteMeses;
  final double costoFinanciamiento;
  final double montoMaximoPagar;
  final double montoCreditoRedondeado;
  final int plazoMeses;
  final double descuentoMensual;
  final double pensionMensualInmediata;
  final double pensionMensualLiquidacion;
  final double flujoHasta80;
  final double periodosRecuperacionMeses;
  final String veredicto;

  // Extended fields for comparison views
  final double recuperacionAfore;
  final double tasaRendimiento;
  final double gananciaTotal;
  final double segundoFondeo;
  final double cantidadMinimaAfore;

  // DEBUG fields to trace input values
  final double debugPensionMensualMejorada;
  final double debugPensionSinMod40;
  final double debugFlujoHasta80SinMod40;

  FinanciamientoCalculation({
    required this.inversionTotal,
    required this.participacionBanco,
    required this.participacionPropia,
    required this.porcentajeBanco,
    required this.porcentajePropio,
    required this.montoCredito,
    required this.duracionTramiteMeses,
    required this.costoFinanciamiento,
    required this.montoMaximoPagar,
    required this.montoCreditoRedondeado,
    required this.plazoMeses,
    required this.descuentoMensual,
    required this.pensionMensualInmediata,
    required this.pensionMensualLiquidacion,
    required this.flujoHasta80,
    required this.periodosRecuperacionMeses,
    required this.veredicto,
    this.recuperacionAfore = 0,
    this.tasaRendimiento = 0,
    this.gananciaTotal = 0,
    this.segundoFondeo = 0,
    this.cantidadMinimaAfore = 0,
    this.debugPensionMensualMejorada = 0,
    this.debugPensionSinMod40 = 0,
    this.debugFlujoHasta80SinMod40 = 0,
  });

  // Convenience getters for views that use different naming
  double get pensionInmediata => pensionMensualInmediata;
  double get pensionAlLiquidar => pensionMensualLiquidacion;
  double get periodoRecuperacionMeses => periodosRecuperacionMeses;
}
