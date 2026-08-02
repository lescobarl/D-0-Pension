import '../../services/retroactive_provider.dart';

/// Maps AI-extracted JSON values to [RetroactiveProvider] setters.
///
/// This is the bridge between Gemini's structured JSON response
/// and the app's state management. It only sets fields that are
/// present and non-null in the AI response.
class FieldExtractor {
  FieldExtractor._();

  /// Apply extracted values from AI JSON to the provider.
  ///
  /// [values] is a `Map<String, dynamic>` from the AI's "values" field.
  /// Only non-null values are applied. Returns a list of field names
  /// that were successfully set.
  static List<String> applyValues(
    RetroactiveProvider provider,
    Map<String, dynamic> values,
  ) {
    final setFields = <String>[];

    // ── FACT + ASIG fields ──
    if (values.containsKey('salarioDiarioPromedio') &&
        values['salarioDiarioPromedio'] != null) {
      provider.setSalarioDiarioPromedio(
        _toDouble(values['salarioDiarioPromedio']!),
      );
      setFields.add('salarioDiarioPromedio');
    }

    if (values.containsKey('umaDiaria') && values['umaDiaria'] != null) {
      provider.setUmaDiaria(_toDouble(values['umaDiaria']!));
      setFields.add('umaDiaria');
    }

    if (values.containsKey('salarioMinimoDiario') &&
        values['salarioMinimoDiario'] != null) {
      provider.setSalarioMinimoDiario(
        _toDouble(values['salarioMinimoDiario']!),
      );
      setFields.add('salarioMinimoDiario');
    }

    if (values.containsKey('pensionYear') && values['pensionYear'] != null) {
      provider.setPensionYear(_toInt(values['pensionYear']!));
      setFields.add('pensionYear');
    }

    if (values.containsKey('semanasCotizadas') &&
        values['semanasCotizadas'] != null) {
      provider.setSemanasCotizadas(_toInt(values['semanasCotizadas']!));
      setFields.add('semanasCotizadas');
    }

    if (values.containsKey('tieneEsposa') &&
        values['tieneEsposa'] != null) {
      provider.setTieneEsposa(_toBool(values['tieneEsposa']!));
      setFields.add('tieneEsposa');
    }

    if (values.containsKey('numeroHijos') && values['numeroHijos'] != null) {
      provider.setNumeroHijos(_toInt(values['numeroHijos']!));
      setFields.add('numeroHijos');
    }

    if (values.containsKey('numeroPadres') && values['numeroPadres'] != null) {
      provider.setNumeroPadres(_toInt(values['numeroPadres']!));
      setFields.add('numeroPadres');
    }

    // ── PENSION MOD 40 fields ──
    if (values.containsKey('edadRetiro') && values['edadRetiro'] != null) {
      provider.setEdadRetiro(_toDouble(values['edadRetiro']!));
      setFields.add('edadRetiro');
    }

    // ── COSTO MOD 40 fields ──
    if (values.containsKey('salarioRegistrado') &&
        values['salarioRegistrado'] != null) {
      provider.setSalarioRegistrado(_toDouble(values['salarioRegistrado']!));
      setFields.add('salarioRegistrado');
    }

    // ── PAGO RETROACTIVO fields ──
    if (values.containsKey('retroactiveYears') &&
        values['retroactiveYears'] != null) {
      provider.setRetroactiveYears(_toDouble(values['retroactiveYears']!));
      setFields.add('retroactiveYears');
    }

    if (values.containsKey('costoModalidad40') &&
        values['costoModalidad40'] != null) {
      provider.setCostoModalidad40(_toDouble(values['costoModalidad40']!));
      setFields.add('costoModalidad40');
    }

    if (values.containsKey('salarioDiario') &&
        values['salarioDiario'] != null) {
      provider.setSalarioDiarioPromedio(_toDouble(values['salarioDiario']!));
      setFields.add('salarioDiario');
    }

    // ── INVERSION fields ──
    if (values.containsKey('edadRetiroSinMod40') &&
        values['edadRetiroSinMod40'] != null) {
      provider.setEdadRetiro(
        _toDouble(values['edadRetiroSinMod40']!),
      );
      setFields.add('edadRetiroSinMod40');
    }

    return setFields;
  }

  /// Get a human-readable label for a field name.
  static String fieldLabel(String fieldName) {
    switch (fieldName) {
      case 'salarioDiarioPromedio':
        return 'Salario diario promedio';
      case 'umaDiaria':
        return 'UMA diaria';
      case 'salarioMinimoDiario':
        return 'Salario mínimo diario';
      case 'pensionYear':
        return 'Año de pensión';
      case 'semanasCotizadas':
        return 'Semanas cotizadas';
      case 'tieneEsposa':
        return '¿Tiene esposa?';
      case 'numeroHijos':
        return 'Número de hijos';
      case 'numeroPadres':
        return 'Número de padres';
      case 'edadRetiro':
        return 'Edad de retiro (con Modalidad 40)';
      case 'salarioRegistrado':
        return 'Salario registrado';
      case 'retroactiveYears':
        return 'Años retroactivos';
      case 'costoModalidad40':
        return 'Costo de Modalidad 40';
      case 'salarioDiario':
        return 'Salario diario';
      case 'edadRetiroSinMod40':
        return 'Edad de retiro';
      default:
        return fieldName;
    }
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true' || value == 'sí' || value == 'si';
    if (value is num) return value != 0;
    return false;
  }
}
