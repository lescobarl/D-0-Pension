/// Represents a single period in the SAL. PROM MOD 40 breakdown.
///
/// Mirrors the Excel sheet structure where each row has:
///   - [fechaInicio]  (Columna B)
///   - [fechaTermino] (Columna C)
///   - [salarioDiario] (Columna D)
///   - [semanas]       (Columna E)
///   - [resultado] = salarioDiario × semanas (Columna F)
///
/// The [esMod40] flag identifies which period corresponds to the Modalidad 40
/// registration (auto-filled from [_salarioRegistrado]).
class PeriodoSalarial {
  DateTime? fechaInicio;
  DateTime? fechaTermino;
  double salarioDiario;
  double semanas;
  bool esMod40;

  /// Resultado = salarioDiario × semanas (Columna F in Excel)
  double get resultado => salarioDiario * semanas;

  PeriodoSalarial({
    this.fechaInicio,
    this.fechaTermino,
    required this.salarioDiario,
    required this.semanas,
    this.esMod40 = false,
  });

  /// Creates a copy with optional field overrides.
  PeriodoSalarial copyWith({
    DateTime? fechaInicio,
    DateTime? fechaTermino,
    double? salarioDiario,
    double? semanas,
    bool? esMod40,
  }) {
    return PeriodoSalarial(
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaTermino: fechaTermino ?? this.fechaTermino,
      salarioDiario: salarioDiario ?? this.salarioDiario,
      semanas: semanas ?? this.semanas,
      esMod40: esMod40 ?? this.esMod40,
    );
  }

  Map<String, dynamic> toJson() => {
        'fechaInicio': fechaInicio?.toIso8601String(),
        'fechaTermino': fechaTermino?.toIso8601String(),
        'salarioDiario': salarioDiario,
        'semanas': semanas,
        'esMod40': esMod40,
      };

  factory PeriodoSalarial.fromJson(Map<String, dynamic> json) => PeriodoSalarial(
        fechaInicio: json['fechaInicio'] != null
            ? DateTime.parse(json['fechaInicio'] as String)
            : null,
        fechaTermino: json['fechaTermino'] != null
            ? DateTime.parse(json['fechaTermino'] as String)
            : null,
        salarioDiario: (json['salarioDiario'] as num).toDouble(),
        semanas: (json['semanas'] as num).toDouble(),
        esMod40: json['esMod40'] as bool? ?? false,
      );
}
