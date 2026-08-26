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
    'fechaAlta',
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
    'modalidad40OptOut',
  ];

  test('aplica los 24 campos canónicos y reporta setFields', () async {
    final provider = await buildProvider();

    final setFields = FieldExtractor.applyValues(provider, {
      'fechaNacimiento': '1960-05-15',
      'fechaAlta': '1990-06-01',
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
      'modalidad40OptOut': false,
      'fechaCalculo': '2026-01-01',
    });
    await settle();

    // La transcripción se prueba por el setFields: los 24 campos se aplicaron.
    expect(setFields.length, allCanonicalFields.length);
    expect(setFields, containsAll(allCanonicalFields));

    // Fechas.
    expect(provider.fechaNacimiento, DateTime(1960, 5, 15));
    expect(provider.fechaAlta, DateTime(1990, 6, 1));
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

    // Semanas: `semanasCotizadas` es el historial ANTES de Mod40 (fuente
    // primaria; se aplica al final y gana). `semanasAntesMod40` y
    // `totalSemanasSinMod40` son ALIASES del mismo valor; el total CON Mod40
    // (= antes + en) lo calcula el RetroactiveCalculator.
    expect(provider.semanasCotizadas, 1200);
    expect(provider.semanasAntesMod40, 1200);
    expect(provider.semanasEnMod40, 100);
    expect(provider.totalSemanasSinMod40, 1200);
    expect(provider.totalSemanasConMod40, 1300);

    // Dependientes.
    expect(provider.tieneEsposa, isTrue);
    expect(provider.numeroHijos, 2);
    expect(provider.numeroPadres, 1);

    // Opt-out: el valor explícito false mantiene Modalidad 40 activa.
    expect(provider.modalidad40OptOut, isFalse);

    // Costos / retroactivo / mejoras.
    expect(provider.costoModalidad40, 45000);
    expect(provider.retroactiveYears, 5);
    expect(provider.pensionMensualMejorada, 25000);
  });

  test('fechaAlta posterior o igual al 1-jul-1997 se RECHAZA (no avanza): '
      'misma ley que la pestaña Pensión y el flujo guiado', () async {
    final provider = await buildProvider();

    // Fecha en el límite de la Ley 73 (1-jul-1997): no aplica → no entra en
    // setFields y no se guarda (el free-path no puede avanzar con ella).
    final setFields = FieldExtractor.applyValues(provider, {
      'fechaAlta': '1997-07-01',
    });
    expect(setFields, isNot(contains('fechaAlta')));
    expect(provider.fechaAlta, isNot(DateTime(1997, 7, 1)));

    // Un día antes (30-jun-1997): la Ley 73 SÍ ampara y se aplica.
    final setFieldsOk = FieldExtractor.applyValues(provider, {
      'fechaAlta': '1997-06-30',
    });
    expect(setFieldsOk, contains('fechaAlta'));
    expect(provider.fechaAlta, DateTime(1997, 6, 30));
  });

  test('fechaAlta acepta formato compacto (AAAAMMDD / DDMMAAAA) igual que las '
      'demás fechas', () async {
    final provider = await buildProvider();

    // AAAAMMDD.
    final aaaa = FieldExtractor.applyValues(provider, {
      'fechaAlta': '19900601',
    });
    expect(aaaa, contains('fechaAlta'));
    expect(provider.fechaAlta, DateTime(1990, 6, 1));

    // DDMMAAAA.
    final ddmm = FieldExtractor.applyValues(provider, {
      'fechaAlta': '01061990',
    });
    expect(ddmm, contains('fechaAlta'));
    expect(provider.fechaAlta, DateTime(1990, 6, 1));
  });

  test(
    'semanasCotizadas es el historial ANTES de Mod40: fijarlo alinea "antes" '
    'y totalSemanasSinMod40; el total CON Mod40 lo calcula el motor',
    () async {
      final provider = await buildProvider();

      // Desglose inicial: antes = 1960, en = 1 (total CON Mod40 = 1961).
      FieldExtractor.applyValues(provider, {
        'semanasAntesMod40': 1960,
        'semanasEnMod40': 1,
      });
      expect(provider.semanasCotizadas, 1960);
      expect(provider.totalSemanasSinMod40, 1960);
      expect(provider.totalSemanasConMod40, 1961);

      // Al fijar explícitamente el historial (1961), se alinean los alias.
      FieldExtractor.applyValues(provider, {'semanasCotizadas': 1961});
      expect(provider.semanasCotizadas, 1961);
      expect(provider.semanasAntesMod40, 1961);
      expect(provider.totalSemanasSinMod40, 1961);
      expect(provider.totalSemanasConMod40, 1962);

      // Al subir el historial a 2100, los alias se alinean; "en" no cambia.
      FieldExtractor.applyValues(provider, {'semanasCotizadas': 2100});
      expect(provider.semanasCotizadas, 2100);
      expect(provider.semanasAntesMod40, 2100);
      expect(provider.totalSemanasSinMod40, 2100);
      expect(provider.totalSemanasConMod40, 2101);
    },
  );

  test(
    'valores explícitos de UMA/SM ganan sobre las proyecciones de edadRetiro',
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
    },
  );

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
    const values = {'edad': 63, 'semanas': 1300, 'umaDiaria': 999.99};

    expect(FieldExtractor.valueFor(values, 'edadRetiro'), 63);
    expect(FieldExtractor.valueFor(values, 'semanasCotizadas'), 1300);
    expect(FieldExtractor.valueFor(values, 'umaDiaria'), 999.99);
    expect(FieldExtractor.valueFor(values, 'numeroPadres'), isNull);
  });

  test('extractRequestedRetirementAge detecta la edad explícita pedida', () {
    // Positivos: órdenes explícitas de cambiar la edad de retiro.
    expect(
      FieldExtractor.extractRequestedRetirementAge(
        'mueve la edad de pensión a 62 años',
      ),
      62,
    );
    expect(
      FieldExtractor.extractRequestedRetirementAge(
        'quiero pensionarme a los 62 años',
      ),
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
    expect(
      FieldExtractor.extractRequestedRetirementAge('nací en 1962'),
      isNull,
    );
  });

  test('enforceRequestedAge corrige la edad a la que pidió el usuario', () {
    // La IA devolvió 63 (contaminada por el ejemplo del prompt) pero el usuario
    // pidió 62 → se fuerza 62 en lugar del número que devolvió la IA.
    final corrected = FieldExtractor.enforceRequestedAge({
      'edadRetiro': 63,
    }, 'mueve la edad de pensión a 62 años');
    expect(corrected['edadRetiro'], 62);

    // Sin petición explícita de edad → los valores se dejan igual.
    final unchanged = FieldExtractor.enforceRequestedAge({
      'edadRetiro': 63,
    }, 'mi edad de retiro es 65');
    expect(unchanged['edadRetiro'], 63);

    // Corrige también bajo el sinónimo "edad" → edadRetiro.
    final syn = FieldExtractor.enforceRequestedAge({
      'edad': 63,
    }, 'mueve la edad a 62');
    expect(syn['edad'], 62);

    // La IA omitió la edad de retiro → se AGREGA la edad pedida.
    final added = FieldExtractor.enforceRequestedAge({
      'semanasCotizadas': 1300,
    }, 'mueve la edad a 62');
    expect(added['edadRetiro'], 62);
    expect(added['semanasCotizadas'], 1300);
  });

  test(
    'detectRequestedEdits: campo → conector → número (todas las familias)',
    () {
      expect(
        FieldExtractor.detectRequestedEdits(
          'mueve la edad de pensión a 62 años',
        ),
        {'edadRetiro': 62},
      );
      expect(
        FieldExtractor.detectRequestedEdits(
          'cambia las semanas cotizadas a 1300',
        ),
        {'semanasCotizadas': 1300},
      );
      expect(FieldExtractor.detectRequestedEdits('pon el salario en 500'), {
        'salarioDiarioPromedio': 500,
      });
      expect(FieldExtractor.detectRequestedEdits('sube los hijos a 2'), {
        'numeroHijos': 2,
      });
      expect(FieldExtractor.detectRequestedEdits('baja la UMA hasta 108.57'), {
        'umaDiaria': 108.57,
      });
    },
  );

  test(
    'detectRequestedEdits: número → campo ("tengo 1300 semanas cotizadas")',
    () {
      expect(
        FieldExtractor.detectRequestedEdits('tengo 1300 semanas cotizadas'),
        {'semanasCotizadas': 1300},
      );
      expect(FieldExtractor.detectRequestedEdits('pon 1500 semanas'), {
        'semanasCotizadas': 1500,
      });
    },
  );

  test('detectRequestedEdits: campo → número directo sin conector '
      '("semanas cotizadas 1900")', () {
    // Regresión: "semanas cotizadas 1900" (número tras el campo, sin conector)
    // se perdía y dependía de la IA. Ahora se detecta de forma determinista.
    expect(FieldExtractor.detectRequestedEdits('semanas cotizadas 1900'), {
      'semanasCotizadas': 1900,
    });
    expect(FieldExtractor.detectRequestedEdits('salario 500'), {
      'salarioDiarioPromedio': 500,
    });
    expect(FieldExtractor.detectRequestedEdits('hijos 2'), {'numeroHijos': 2});
    expect(FieldExtractor.detectRequestedEdits('semanas cotizadas en 1900'), {
      'semanasCotizadas': 1900,
    });
  });

  test('detectRequestedEdits: "250 en modalidad 40" → semanasEnMod40', () {
    // Regresión: el usuario escribe "250 en modalidad 40" y antes se perdía
    // (dependía de la IA, que podía confundirlo con semanas cotizadas totales).
    expect(FieldExtractor.detectRequestedEdits('250 en modalidad 40'), {
      'semanasEnMod40': 250,
    });
    expect(FieldExtractor.detectRequestedEdits('250 en mod 40'), {
      'semanasEnMod40': 250,
    });
    expect(FieldExtractor.detectRequestedEdits('250 en m40'), {
      'semanasEnMod40': 250,
    });
  });

  test('detectRequestedEdits: "X Umas" → umaMultiplier (NO salario)', () {
    // Regresión: "15 Umas" se mapeaba a salarioDiarioPromedio. Ahora el plural
    // "Umas" debe ir a umaMultiplier, nunca a salario.
    expect(FieldExtractor.detectRequestedEdits('mi salario era de 15 Umas'), {
      'umaMultiplier': 15,
    });
    expect(FieldExtractor.detectRequestedEdits('ganaba 15 Umas'), {
      'umaMultiplier': 15,
    });
    expect(FieldExtractor.detectRequestedEdits('pon 15 umas'), {
      'umaMultiplier': 15,
    });
    // El singular "UMA" con valor en pesos sigue siendo umaDiaria.
    expect(FieldExtractor.detectRequestedEdits('baja la UMA hasta 108.57'), {
      'umaDiaria': 108.57,
    });
  });

  test('detectRequestedEdits: el sinónimo más específico gana', () {
    expect(FieldExtractor.detectRequestedEdits('semanas en mod 40 a 200'), {
      'semanasEnMod40': 200,
    });
    expect(
      FieldExtractor.detectRequestedEdits(
        'salario promedio 250 semanas a 5000',
      ),
      {'salarioPromedio250Semanas': 5000},
    );
    // Regla del último conector: "semanas en mod 40 a 1300" → 1300 (no "en 40").
    expect(FieldExtractor.detectRequestedEdits('semanas en mod 40 a 1300'), {
      'semanasEnMod40': 1300,
    });
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

  test(
    'detectRequestedEdits extrae 60.5 crudo; el snap ocurre en el provider',
    () {
      // El extractor reporta el número exacto que escribió el usuario; el ajuste
      // a la rejilla legal [60, 60.51, ..., 65] ocurre en setEdadRetiro.
      expect(FieldExtractor.detectRequestedEdits('mueve la edad a 60.5 años'), {
        'edadRetiro': 60.5,
      });
    },
  );

  test(
    'setEdadRetiro ajusta (snap) valores fuera de la rejilla legal',
    () async {
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
    },
  );

  test(
    'applyValues ajusta la edad pedida con 60.5 a la rejilla legal',
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
    },
  );

  test(
    'OPT-OUT: modalidad40OptOut:true elimina los renglones M40 del desglose y '
    'bloquea los campos M40 del mismo payload (sin renglón vacío)',
    () async {
      final provider = await buildProvider();
      await provider.initialize();
      await settle();

      // El baseline siembra un renglón esMod40 en el desglose.
      expect(provider.periodos.where((p) => p.esMod40), isNotEmpty);

      // Valor previo del multiplicador UMA para probar que NO se sobreescribe.
      provider.setUmaMultiplier(12.0);
      await settle();

      // Un mismo payload trae el opt-out y campos M40: el opt-out se aplica
      // primero y los campos M40 quedan bloqueados (no se mutan).
      final setFields = FieldExtractor.applyValues(provider, {
        'modalidad40OptOut': true,
        'semanasEnMod40': 200,
        'umaMultiplier': 15.0,
        'startDate': '2022-01-15',
        'endDate': '2023-01-15',
      });
      await settle();

      expect(setFields, ['modalidad40OptOut']);
      expect(setFields, isNot(contains('semanasEnMod40')));
      expect(setFields, isNot(contains('umaMultiplier')));
      expect(setFields, isNot(contains('startDate')));
      expect(setFields, isNot(contains('endDate')));

      // Desglose sin renglones M40 (no hay "renglón vacío" que valide error).
      expect(provider.modalidad40OptOut, isTrue);
      expect(provider.periodos.where((p) => p.esMod40), isEmpty);
      expect(provider.semanasEnMod40, 0);
      // El UMA multiplier del payload NO se aplicó (guard del opt-out).
      expect(provider.umaMultiplier, 12.0);
    },
  );

  test(
    'OPT-OUT: al volver a false (Sí) los campos M40 se vuelven a aplicar y el '
    'desglose vuelve a tener un renglón esMod40',
    () async {
      final provider = await buildProvider();
      await provider.initialize();
      await settle();

      // Apagar M40: se limpia el renglón esMod40 del baseline.
      final off = FieldExtractor.applyValues(provider, {
        'modalidad40OptOut': true,
      });
      await settle();
      expect(off, ['modalidad40OptOut']);
      expect(provider.modalidad40OptOut, isTrue);
      expect(provider.periodos.where((p) => p.esMod40), isEmpty);

      // Volver a "Sí" y capturar semanas de M40: el renglón esMod40 se recrea.
      final on = FieldExtractor.applyValues(provider, {
        'modalidad40OptOut': false,
        'semanasEnMod40': 150,
      });
      await settle();
      expect(on, containsAll(['modalidad40OptOut', 'semanasEnMod40']));
      expect(provider.modalidad40OptOut, isFalse);
      expect(provider.semanasEnMod40, closeTo(150, 0.001));
      final mod40 = provider.periodos.where((p) => p.esMod40).toList();
      expect(mod40, hasLength(1));
      expect(mod40.single.semanas, closeTo(150, 0.001));
    },
  );

  test('OPT-OUT: sinónimos "noquieromodalidad40"/"sinmod40" resuelven a '
      'modalidad40OptOut (gana el sinónimo más largo)', () async {
    final provider = await buildProvider();

    final off = FieldExtractor.applyValues(provider, {
      'noquieromodalidad40': true,
    });
    await settle();
    expect(off, ['modalidad40OptOut']);
    expect(provider.modalidad40OptOut, isTrue);

    final on = FieldExtractor.applyValues(provider, {'sinmod40': false});
    await settle();
    expect(on, ['modalidad40OptOut']);
    expect(provider.modalidad40OptOut, isFalse);
  });
}
