/// Result model for the PAGO RETROACTIVO calculation.
///
/// Contains all cost components: Modalidad 40 base cost,
/// actualizaciones (inflation adjustments), recargos (surcharges),
/// and derived values like AFORE recovery and total investment.
class RetroactiveCalculation {
  final double costoModalidad40;
  final double actualizaciones;
  final double recargos;
  final double costoTotal;
  final double incrementoPorcentaje;
  final double recuperacionAfore;
  final double inversionTotal;
  final int mesesRetroactivos;

  // Extended fields for comparison views
  final double gananciaTotal;
  final double tasaRendimiento;
  final double periodoRecuperacionMeses;

  RetroactiveCalculation({
    required this.costoModalidad40,
    required this.actualizaciones,
    required this.recargos,
    required this.costoTotal,
    required this.incrementoPorcentaje,
    required this.recuperacionAfore,
    required this.inversionTotal,
    required this.mesesRetroactivos,
    this.gananciaTotal = 0,
    this.tasaRendimiento = 0,
    this.periodoRecuperacionMeses = 0,
  });
}
