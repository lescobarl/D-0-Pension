import '../../core/models/periodo_salarial.dart';

/// Motor de lógica pura para el desglose de periodos salariales
/// (hoja Excel "SAL. PROM MOD 40").
///
/// Responsabilidad única: **matemáticas de periodos** (promedios, semanas,
/// baseline y actualización de salarios). Es una clase sin estado que no
/// conoce persistencia, UI ni notificaciones, lo que la hace directamente
/// testeable.
class PeriodosEngine {
  /// Suma las semanas de los periodos marcados como Mod40.
  double semanasEnMod40(List<PeriodoSalarial> periodos) =>
      periodos.fold<double>(0, (s, p) => s + (p.esMod40 ? p.semanas : 0));

  /// Suma las semanas de los periodos NO Mod40.
  double semanasSinMod40(List<PeriodoSalarial> periodos) =>
      periodos.fold<double>(0, (s, p) => s + (!p.esMod40 ? p.semanas : 0));

  /// Promedio ponderado de los periodos NO Mod40: Σ(resultado) / Σ(semanas).
  ///
  /// Retorna `0` cuando no hay semanas NO Mod40.
  double promedio250SinMod40(List<PeriodoSalarial> periodos) {
    final totalSemanas = semanasSinMod40(periodos);
    final totalResultados =
        periodos.fold<double>(0, (s, p) => s + (!p.esMod40 ? p.resultado : 0));
    return totalSemanas > 0 ? totalResultados / totalSemanas : 0;
  }

  /// Promedio ponderado desde el desglose con tope de [totalSemanasPromedio]
  /// (regla Excel E19: como máximo 250 semanas efectivas; los periodos más
  /// antiguos se consumen primero y el último puede quedar parcial).
  ///
  /// Si [periodos] está vacío, retorna [fallback].
  double promedioDesdePeriodos(
    List<PeriodoSalarial> periodos, {
    required double totalSemanasPromedio,
    required double fallback,
  }) {
    if (periodos.isEmpty) return fallback;

    double semanasConsumidas = 0;
    double sumaResultados = 0;

    for (final p in periodos) {
      if (semanasConsumidas >= totalSemanasPromedio) break;
      final semanasDisponibles = totalSemanasPromedio - semanasConsumidas;
      final semanasUsadas =
          p.semanas <= semanasDisponibles ? p.semanas : semanasDisponibles;
      if (semanasUsadas <= 0) continue;
      sumaResultados += p.salarioDiario * semanasUsadas;
      semanasConsumidas += semanasUsadas;
    }

    return sumaResultados / totalSemanasPromedio;
  }

  /// Actualiza los salarios de los periodos **sin mutar la lista original**.
  ///
  /// Reglas:
  /// - Periodos Mod40 → siempre a [salarioRegistrado] (se derivan de UMA).
  /// - Periodos NO Mod40 → a [salarioPromedio250] si [actualizarNoMod40] es
  ///   `true`; de lo contrario conservan su salario actual.
  ///
  /// Retorna la nueva lista y si hubo algún cambio.
  ({List<PeriodoSalarial> periodos, bool anyChanged}) actualizarSalariosDePeriodos(
    List<PeriodoSalarial> periodos, {
    required double salarioRegistrado,
    double? salarioPromedio250,
    required bool actualizarNoMod40,
  }) {
    final nuevos = <PeriodoSalarial>[];
    var anyChanged = false;
    for (final p in periodos) {
      double nuevoSalario;
      if (p.esMod40) {
        nuevoSalario = salarioRegistrado;
      } else if (actualizarNoMod40 && salarioPromedio250 != null) {
        nuevoSalario = salarioPromedio250;
      } else {
        nuevoSalario = p.salarioDiario;
      }
      if (p.salarioDiario != nuevoSalario) {
        anyChanged = true;
        nuevos.add(PeriodoSalarial(
          fechaInicio: p.fechaInicio,
          fechaTermino: p.fechaTermino,
          salarioDiario: nuevoSalario,
          semanas: p.semanas,
          esMod40: p.esMod40,
        ));
      } else {
        nuevos.add(p);
      }
    }
    return (periodos: nuevos, anyChanged: anyChanged);
  }

  /// Baseline del desglose desde el Excel (SAL. PROM MOD 40 + CAL. PROM.
  /// 250 SEM).
  ///
  /// Valores que coinciden con la hoja de cálculo:
  ///   SAL. PROM MOD 40 Row 22: periodo Mod40 (2027-02-01 a 2029-08-31,
  ///     [salarioRegistrado], 134.7142857143 sem)
  ///   CAL. PROM. 250 SEM Rows 7-13: los 7 periodos originales de 250 semanas.
  ///
  /// Total semanas ≈ 384.71 (excede 250 porque las semanas Mod40 se suman
  /// sobre la base original de 250).
  List<PeriodoSalarial> crearBaseline(double salarioRegistrado) {
    return [
      // Periodo Mod40 (SAL. PROM MOD 40 Row 22)
      PeriodoSalarial(
        fechaInicio: DateTime(2027, 2, 1),
        fechaTermino: DateTime(2029, 8, 31),
        salarioDiario: salarioRegistrado,
        semanas: 134.7142857143,
        esMod40: true,
      ),
      // Periodos originales de 250 semanas (CAL. PROM. 250 SEM Rows 7-13)
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
}
