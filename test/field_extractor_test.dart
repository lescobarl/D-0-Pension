import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/ai/field_extractor.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Unit tests for [FieldExtractor]: the bridge that transcribes the AI's
/// structured JSON into [RetroactiveProvider] captura field values.
///
/// They run against the real provider so they double as an integration check
/// that every setter accepts the extracted value.
///
/// ## Derived fields (important)
/// `salarioDiarioPromedio` and `semanasEnMod40` are recomputed from the
/// periodos desglose by `_recalculatePromedioFromPeriodos()` (called by
/// several setters and by the async continuation of `setEdadRetiro`), so they
/// are asserted only as `>= 0`. The proof of transcription for those fields is
/// their presence in the returned `setFields` list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RetroactiveProvider> buildProvider() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
  }

  // Let setEdadRetiro's zero-delay continuation settle so derived fields
  // (salarioDiarioPromedio / semanasEnMod40) are stable before asserting.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  const allCanonicalFields = [
    'fechaNacimiento',
    'edadRetiro',
    'pensionYear',
    'umaDiaria',
    'salarioMinimoDiario',
    'umaMultiplier',
    'salarioRegistrado',
    'salarioPromedio250Semanas',
    'salarioDiarioPromedio',
    'semanasAntesMod40',
    'semanasEnMod40',
    'totalSemanasSinMod40',
    'semanasCotizadas',
    'tieneEsposa',
    'numeroHijos',
    'numeroPadres',
    'startDate',
    'endDate',
    'costoModalidad40',
    'retroactiveYears',
    'pensionMensualMejorada',
    'fechaCalculo',
  ];

  test('aplica los 22 campos canónicos y reporta setFields', () async {
    final provider = await buildProvider();

    final setFields = FieldExtractor.applyValues(provider, {
      'fechaNacimiento': '1960-05-15',
      'edadRetiro': 63,
      'pensionYear': 2023,
      'umaDiaria': 999.99,
      'salarioMinimoDiario': 888.88,
      'umaMultiplier': 12.0,
      'salarioRegistrado': 777.77,
      'salarioPromedio250Semanas': 666.66,
      'salarioDiarioPromedio': 555.55,
      'semanasAntesMod40': 1000,
      'semanasEnMod40': 100,
      'totalSemanasSinMod40': 900,
      'semanasCotizadas': 1200,
      'tieneEsposa': true,
      'numeroHijos': 2,
      'numeroPadres': 1,
      'startDate': '2020-01-15',
      'endDate': '2021-01-15',
      'costoModalidad40': 45000,
      'retroactiveYears': 5,
      'pensionMensualMejorada': 25000,
      'fechaCalculo': '2026-01-01',
    });
    await settle();

    // La transcripción se prueba por el setFields: los 22 campos se aplicaron.
    expect(setFields.length, allCanonicalFields.length);
    expect(setFields, containsAll(allCanonicalFields));

    // Fechas.
    expect(provider.fechaNacimiento, DateTime(1960, 5, 15));
    expect(provider.fechaCalculo, DateTime(2026, 1, 1));
    expect(provider.startDate, DateTime(2020, 1, 15));
    expect(provider.endDate, DateTime(2021, 1, 15));

    // Edad / año de pensión (el pensionYear explícito gana sobre el recálculo).
    expect(provider.edadRetiro, 63);
    expect(provider.pensionYear, 2023);

    // UMA / SM / multiplicador / salario registrado (explícitos ganan a las
    // proyecciones forzadas por setEdadRetiro / setPensionYear).
    expect(provider.umaDiaria, 999.99);
    expect(provider.salarioMinimoDiario, 888.88);
    expect(provider.umaMultiplier, 12.0);
    expect(provider.salarioRegistrado, 777.77);

    // Salarios: salarioPromedio250Semanas exacto; salarioDiarioPromedio es
    // derivado de los periodos (los setters de semanas lo recalculan).
    expect(provider.salarioPromedio250Semanas, 666.66);
    expect(provider.salarioDiarioPromedio, greaterThanOrEqualTo(0));

    // Semanas: `semanasCotizadas` es el TOTAL explícito y se aplica al final
    // (gana). `semanasEnMod40` puede derivarse de los periodos, por lo que el
    // componente "antes Mod40" se deriva como total - en (invariante
    // total = antes + en) y `totalSemanasSinMod40` se alinea con antes para
    // que la guardia de migración no revierta el valor solicitado.
    expect(provider.semanasCotizadas, 1200);
    expect(provider.semanasEnMod40, greaterThanOrEqualTo(0));
    expect(provider.semanasAntesMod40 + provider.semanasEnMod40,
        closeTo(provider.semanasCotizadas.toDouble(), 0.001));
    expect(provider.totalSemanasSinMod40, provider.semanasAntesMod40.toInt());

    // Dependientes.
    expect(provider.tieneEsposa, isTrue);
    expect(provider.numeroHijos, 2);
    expect(provider.numeroPadres, 1);

    // Costos / retroactivo / mejoras.
    expect(provider.costoModalidad40, 45000);
    expect(provider.retroactiveYears, 5);
    expect(provider.pensionMensualMejorada, 25000);
  });

  test('semanasCotizadas es el TOTAL: fija el total, deriva "antes" y alinea '
      'totalSemanasSinMod40 (bug: AI dice 1961, captura mostraba 1960)', () async {
    final provider = await buildProvider();

    // Desglose inicial: antes = 1960, en = 1 (total = 1961).
    FieldExtractor.applyValues(provider, {
      'semanasAntesMod40': 1960,
      'semanasEnMod40': 1,
    });
    expect(provider.semanasCotizadas, 1961);

    // El total ya es 1961 y permanece consistente (total = antes + en).
    FieldExtractor.applyValues(provider, {'semanasCotizadas': 1961});
    expect(provider.semanasCotizadas, 1961);
    expect(provider.semanasAntesMod40 + provider.semanasEnMod40,
        closeTo(1961, 0.001));
    expect(provider.totalSemanasSinMod40, provider.semanasAntesMod40.toInt());

    // Al subir el total a 2100, el componente "antes" se deriva
    // (antes = 2100 - en) y el desglose queda consistente.
    FieldExtractor.applyValues(provider, {'semanasCotizadas': 2100});
    expect(provider.semanasCotizadas, 2100);
    expect(provider.semanasAntesMod40 + provider.semanasEnMod40,
        closeTo(2100, 0.001));
    expect(provider.totalSemanasSinMod40, provider.semanasAntesMod40.toInt());
  });

  test('valores explícitos de UMA/SM ganan sobre las proyecciones de edadRetiro',
      () async {
    final provider = await buildProvider();

    final setFields = FieldExtractor.applyValues(provider, {
      'fechaNacimiento': '1960-05-15',
      'edadRetiro': 63,
      'umaDiaria': 999.99,
      'salarioMinimoDiario': 888.88,
    });
    await settle();

    expect(
      setFields,
      containsAll([
        'fechaNacimiento',
        'edadRetiro',
        'umaDiaria',
        'salarioMinimoDiario',
      ]),
    );
    expect(provider.fechaNacimiento, DateTime(1960, 5, 15));
    expect(provider.edadRetiro, 63);
    // pensionYear derivado de fechaNacimiento + edadRetiro (1960 + 63).
    expect(provider.pensionYear, 2023);
    // Las proyecciones de UMA/SM (año 2023) quedan pisadas por los valores
    // explícitos que la IA envió después.
    expect(provider.umaDiaria, 999.99);
    expect(provider.salarioMinimoDiario, 888.88);
  });

  test('normaliza sinónimos en lenguaje natural', () async {
    final provider = await buildProvider();

    final setFields = FieldExtractor.applyValues(provider, {
      'edad': 60,
      'salario': 500,
      'semanas': 1200,
      'esposa': 'si',
      'hijos': 2,
      'padres': 1,
      'uma': 108.57,
      'salarioMinimo': 248.93,
    });
    await settle();

    expect(
      setFields,
      containsAll([
        'edadRetiro',
        'salarioDiarioPromedio',
        'semanasCotizadas',
        'tieneEsposa',
        'numeroHijos',
        'numeroPadres',
        'umaDiaria',
        'salarioMinimoDiario',
      ]),
    );
    expect(provider.edadRetiro, 60);
    expect(provider.umaDiaria, 108.57);
    expect(provider.salarioMinimoDiario, 248.93);
    expect(provider.semanasCotizadas, 1200);
    expect(provider.tieneEsposa, isTrue);
    expect(provider.numeroHijos, 2);
    expect(provider.numeroPadres, 1);
    // 'salario' → salarioDiarioPromedio, que es derivado de los periodos
    // (la continuación asíncrona de setEdadRetiro lo recalcula).
    expect(provider.salarioDiarioPromedio, greaterThanOrEqualTo(0));
  });

  test('ignora valores null', () async {
    final provider = await buildProvider();

    final setFields = FieldExtractor.applyValues(provider, {
      'edadRetiro': null,
      'semanasCotizadas': null,
      'umaDiaria': null,
    });

    expect(setFields, isEmpty);
    expect(provider.edadRetiro, 65); // valor por defecto sin cambios
    expect(provider.semanasCotizadas, 0);
    expect(provider.umaDiaria, 0);
  });

  test('ignora valores no parseables sin corromper el estado', () async {
    final provider = await buildProvider();
    final before = provider.salarioDiarioPromedio;

    final setFields = FieldExtractor.applyValues(provider, {
      'edadRetiro': 'sesenta y tres',
      'semanasCotizadas': 'mil',
      'salarioDiarioPromedio': -5,
      'tieneEsposa': 'quizás',
    });

    expect(setFields, isEmpty);
    expect(provider.edadRetiro, 65);
    expect(provider.semanasCotizadas, 0);
    expect(provider.tieneEsposa, isFalse);
    // Los valores inválidos nunca corrompen el estado previo.
    expect(provider.salarioDiarioPromedio, before);
  });

  test('parsea fechas ISO y mexicano DD/MM/YYYY', () async {
    final iso = await buildProvider();
    FieldExtractor.applyValues(iso, {'fechaNacimiento': '1960-05-15'});
    expect(iso.fechaNacimiento, DateTime(1960, 5, 15));

    final mexicano = await buildProvider();
    FieldExtractor.applyValues(mexicano, {'fechaNacimiento': '15/05/1960'});
    expect(mexicano.fechaNacimiento, DateTime(1960, 5, 15));

    final slash = await buildProvider();
    FieldExtractor.applyValues(slash, {'startDate': '15/01/2020'});
    expect(slash.startDate, DateTime(2020, 1, 15));
  });

  test('valueFor resuelve sinónimos al valor crudo', () {
    const values = {
      'edad': 63,
      'semanas': 1300,
      'umaDiaria': 999.99,
    };

    expect(FieldExtractor.valueFor(values, 'edadRetiro'), 63);
    expect(FieldExtractor.valueFor(values, 'semanasCotizadas'), 1300);
    expect(FieldExtractor.valueFor(values, 'umaDiaria'), 999.99);
    expect(FieldExtractor.valueFor(values, 'numeroPadres'), isNull);
  });

  test('extractRequestedRetirementAge detecta la edad explícita pedida', () {
    // Positivos: órdenes explícitas de cambiar la edad de retiro.
    expect(
      FieldExtractor.extractRequestedRetirementAge(
          'mueve la edad de pensión a 62 años'),
      62,
    );
    expect(
      FieldExtractor.extractRequestedRetirementAge(
          'quiero pensionarme a los 62 años'),
      62,
    );
    expect(
      FieldExtractor.extractRequestedRetirementAge('cambia la edad a 61'),
      61,
    );

    // Negativos: no son órdenes de edición de la edad de retiro.
    expect(
      FieldExtractor.extractRequestedRetirementAge('tengo 62 años'),
      isNull,
    );
    expect(
      FieldExtractor.extractRequestedRetirementAge('mi edad de retiro es 65'),
      isNull,
    );
    expect(FieldExtractor.extractRequestedRetirementAge('nací en 1962'), isNull);
  });

  test('enforceRequestedAge corrige la edad a la que pidió el usuario', () {
    // La IA devolvió 63 (contaminada por el ejemplo del prompt) pero el usuario
    // pidió 62 → se fuerza 62 en lugar del número que devolvió la IA.
    final corrected = FieldExtractor.enforceRequestedAge(
      {'edadRetiro': 63},
      'mueve la edad de pensión a 62 años',
    );
    expect(corrected['edadRetiro'], 62);

    // Sin petición explícita de edad → los valores se dejan igual.
    final unchanged = FieldExtractor.enforceRequestedAge(
      {'edadRetiro': 63},
      'mi edad de retiro es 65',
    );
    expect(unchanged['edadRetiro'], 63);

    // Corrige también bajo el sinónimo "edad" → edadRetiro.
    final syn = FieldExtractor.enforceRequestedAge(
      {'edad': 63},
      'mueve la edad a 62',
    );
    expect(syn['edad'], 62);

    // La IA omitió la edad de retiro → se AGREGA la edad pedida.
    final added = FieldExtractor.enforceRequestedAge(
      {'semanasCotizadas': 1300},
      'mueve la edad a 62',
    );
    expect(added['edadRetiro'], 62);
    expect(added['semanasCotizadas'], 1300);
  });

  test('detectRequestedEdits: campo → conector → número (todas las familias)',
      () {
    expect(
      FieldExtractor.detectRequestedEdits('mueve la edad de pensión a 62 años'),
      {'edadRetiro': 62},
    );
    expect(
      FieldExtractor.detectRequestedEdits('cambia las semanas cotizadas a 1300'),
      {'semanasCotizadas': 1300},
    );
    expect(
      FieldExtractor.detectRequestedEdits('pon el salario en 500'),
      {'salarioDiarioPromedio': 500},
    );
    expect(
      FieldExtractor.detectRequestedEdits('sube los hijos a 2'),
      {'numeroHijos': 2},
    );
    expect(
      FieldExtractor.detectRequestedEdits('baja la UMA hasta 108.57'),
      {'umaDiaria': 108.57},
    );
  });

  test('detectRequestedEdits: número → campo ("tengo 1300 semanas cotizadas")',
      () {
    expect(
      FieldExtractor.detectRequestedEdits('tengo 1300 semanas cotizadas'),
      {'semanasCotizadas': 1300},
    );
    expect(
      FieldExtractor.detectRequestedEdits('pon 1500 semanas'),
      {'semanasCotizadas': 1500},
    );
  });

  test('detectRequestedEdits: el sinónimo más específico gana', () {
    expect(
      FieldExtractor.detectRequestedEdits('semanas en mod 40 a 200'),
      {'semanasEnMod40': 200},
    );
    expect(
      FieldExtractor.detectRequestedEdits('salario promedio 250 semanas a 5000'),
      {'salarioPromedio250Semanas': 5000},
    );
    // Regla del último conector: "semanas en mod 40 a 1300" → 1300 (no "en 40").
    expect(
      FieldExtractor.detectRequestedEdits('semanas en mod 40 a 1300'),
      {'semanasEnMod40': 1300},
    );
  });

  test('detectRequestedEdits: sin edición explícita → vacío', () {
    expect(FieldExtractor.detectRequestedEdits('hola'), isEmpty);
    expect(FieldExtractor.detectRequestedEdits('gracias'), isEmpty);
    expect(
      FieldExtractor.detectRequestedEdits('mi edad de retiro es 65'),
      isEmpty,
    );
    expect(FieldExtractor.detectRequestedEdits('nací en 1962'), isEmpty);
    expect(FieldExtractor.detectRequestedEdits('tengo 62 años'), isEmpty);
  });

  test('detectRequestedEdits extrae 60.5 crudo; el snap ocurre en el provider',
      () {
    // El extractor reporta el número exacto que escribió el usuario; el ajuste
    // a la rejilla legal [60, 60.51, ..., 65] ocurre en setEdadRetiro.
    expect(
      FieldExtractor.detectRequestedEdits('mueve la edad a 60.5 años'),
      {'edadRetiro': 60.5},
    );
  });

  test('setEdadRetiro ajusta (snap) valores fuera de la rejilla legal', () async {
    final provider = await buildProvider();
    // Inicializa metadata (dropdown) para que el snap use la rejilla legal;
    // patrón del ai_chat_fill_fields_test.
    await provider.initialize();
    // Grid legal: [60, 60.51, 61, 61.51, ..., 65] — no existe 60.5.

    // Punto de partida en rejilla (62) para que el primer snap sea un cambio
    // real y no coincida con el default (60.51).
    await provider.setEdadRetiro(62);
    await settle();
    expect(provider.edadRetiro, 62);

    // 60.5 no está en la rejilla y su decimal (0.5) es menor al umbral 0.51,
    // así que redondea hacia abajo al entero 60 (regla Art. 167, igual que
    // Excel: 60.5 → 60 → 75%). Antes el snap daba 60.51 (80%), incorrecto.
    await provider.setEdadRetiro(60.5);
    await settle();
    expect(provider.edadRetiro, 60.0);
    expect(provider.availableAgesRetiro, contains(provider.edadRetiro));

    // 61.3: decimal 0.3 < 0.51 → redondea hacia abajo a 61 (no a 61.51).
    await provider.setEdadRetiro(61.3);
    await settle();
    expect(provider.edadRetiro, 61.0);

    // Fuera de rango → clamp al borde.
    await provider.setEdadRetiro(59.5);
    await settle();
    expect(provider.edadRetiro, 60);

    await provider.setEdadRetiro(65.5);
    await settle();
    expect(provider.edadRetiro, 65);

    // Enteros y valores ya en la rejilla no cambian.
    await provider.setEdadRetiro(62);
    await settle();
    expect(provider.edadRetiro, 62);

    await provider.setEdadRetiro(60.51);
    await settle();
    expect(provider.edadRetiro, 60.51);
  });

  test('applyValues ajusta la edad pedida con 60.5 a la rejilla legal',
      () async {
    final provider = await buildProvider();
    await provider.initialize();
    // Parte de 62 (en rejilla) para que el snap de 60.5 sea un cambio real.
    await provider.setEdadRetiro(62);
    await settle();

    final setFields = FieldExtractor.applyValues(provider, {
      'fechaNacimiento': '1960-05-15',
      'edadRetiro': 60.5,
    });
    await settle();

    expect(setFields, contains('edadRetiro'));
    // El valor aplicado (post-snap) siempre está en la rejilla, así el
    // dropdown de Captura nunca se renderiza en blanco.
    expect(provider.edadRetiro, 60.0);
    expect(provider.availableAgesRetiro, contains(provider.edadRetiro));
  });
}
