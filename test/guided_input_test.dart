import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/ai/guided_input.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/periodo_salarial.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Pruebas de la guía determinista de captura de datos.
///
/// Es LA APP (no la IA) quien decide qué dato falta y pregunta UN dato a la
/// vez en un orden fijo, reemplazando la pregunta vaga "¿Falta algún dato?".
///
/// ## Orden de prioridad
/// 1. `semanasCotizadas`          → vital, SIEMPRE una vez por sesión
/// 2. `salarioPromedio250Semanas` → vital, SIEMPRE una vez por sesión
/// 3. `semanasEnMod40`            → vital, SIEMPRE una vez por sesión
///                                  (número o "por fechas": inicio/fin)
/// 4. `salarioDiarioPromedio`     → respaldo (solo si sigue en 0)
/// 5. Opcionales: fechaNacimiento → esposa → hijos → padres → uma
///    (edadRetiro NO se pregunta en la guía)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // NOTA: NO se llama provider.initialize(). GuidedInput solo lee los getters
  // del provider y initialize() siembra datos reales (semanas/salario > 0),
  // lo que impediría probar el estado "vacío" (sentinel 0 = falta).
  Future<RetroactiveProvider> buildProvider() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
  }

  // Los tres datos vitales, en el orden exacto en que la guía los pide.
  const vitales = [
    'semanasCotizadas',
    'salarioPromedio250Semanas',
    'semanasEnMod40',
  ];

  test('proveedor vacío: pide primero semanasCotizadas (vital)', () async {
    final provider = await buildProvider();
    final guide = GuidedInput.nextGuide(provider, <String>{});
    expect(guide, isNotNull);
    expect(guide!.field, 'semanasCotizadas');
    expect(guide.question, contains('semanas'));
  });

  test('los vitales se preguntan SIEMPRE una vez por sesión, en orden fijo',
      () async {
    final provider = await buildProvider();
    final requested = <String>{};
    final fields = <String>[];
    for (var i = 0; i < 3; i++) {
      final guide = GuidedInput.nextGuide(provider, requested);
      expect(guide, isNotNull, reason: 'iteración $i');
      requested.add(guide!.field);
      fields.add(guide.field);
    }
    expect(fields, vitales);
  });

  test('IGNORA DEFAULTS: aunque el proveedor tenga valores precargados, la '
      'guía SIEMPRE vuelve a preguntar los vitales', () async {
    final provider = await buildProvider();
    // Valores sembrados por default (como app_metadata.json).
    provider.setSemanasCotizadas(2090);
    provider.setSalarioPromedio250Semanas(2897.19);
    provider.setSemanasEnMod40(130);
    // Aun con todo lleno, sin marcarlos como "ya preguntados", se repreguntan.
    final guide = GuidedInput.nextGuide(provider, <String>{});
    expect(guide!.field, 'semanasCotizadas');
  });

  test('con vitales ya preguntados y salarioDiarioPromedio en 0, pide el '
      'respaldo salarioDiarioPromedio', () async {
    final provider = await buildProvider();
    // provider sin initialize() → salarioDiarioPromedio queda en 0.
    final guide = GuidedInput.nextGuide(provider, vitales.toSet());
    expect(guide!.field, 'salarioDiarioPromedio');
    expect(guide.suggestions, isEmpty);
  });

  test('vitales + respaldo listos: pide fechaNacimiento (primer opcional)',
      () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(
        provider, vitales.toSet()..add('salarioDiarioPromedio'));
    expect(guide!.field, 'fechaNacimiento');
    expect(guide.question, contains('fecha de nacimiento'));
    // La fecha se captura como texto libre (sin chips).
    expect(guide.suggestions, isEmpty);
  });

  test('semanasEnMod40 NO ofrece chip "Por fechas" (solo número)', () async {
    final provider = await buildProvider();
    final guide = GuidedInput.nextGuide(
        provider, {'semanasCotizadas', 'salarioPromedio250Semanas'});
    expect(guide!.field, 'semanasEnMod40');
    expect(guide.suggestions, isEmpty);
  });

  test('la guía NO pregunta edadRetiro: tras fechaNacimiento toca tieneEsposa',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
    await provider.initialize();
    // initialize() siembra salarioDiarioPromedio > 0 → respaldo omitido.
    // Con los vitales + fechaNacimiento ya preguntados, la edad se omite y
    // el siguiente opcional es tieneEsposa.
    final guide =
        GuidedInput.nextGuide(provider, vitales.toSet()..add('fechaNacimiento'));
    expect(guide!.field, 'tieneEsposa');
  });

  test('applyAnswer: interpreta y aplica respuestas cortas de la guía', () async {
    final provider = await buildProvider();

    final semanas =
        await GuidedInput.applyAnswer(provider, 'semanasCotizadas', '1200');
    expect(semanas!.ok, isTrue);
    expect(semanas.setFields, ['semanasCotizadas']);
    expect(semanas.nextField, isNull);
    expect(provider.semanasCotizadas, 1200);

    final salario =
        await GuidedInput.applyAnswer(provider, 'salarioDiarioPromedio', '500.50');
    expect(salario!.ok, isTrue);
    expect(salario.setFields, ['salarioDiarioPromedio']);
    expect(salario.nextField, isNull);
    expect(provider.salarioDiarioPromedio, 500.5);

    final salario250 = await GuidedInput.applyAnswer(
        provider, 'salarioPromedio250Semanas', '1300');
    expect(salario250!.ok, isTrue);
    expect(salario250.setFields, ['salarioPromedio250Semanas']);
    expect(salario250.nextField, isNull);
    expect(provider.salarioPromedio250Semanas, 1300);

    final mod40 =
        await GuidedInput.applyAnswer(provider, 'semanasEnMod40', '130');
    expect(mod40!.ok, isTrue);
    expect(mod40.setFields, ['semanasEnMod40']);
    expect(mod40.nextField, isNull);
    expect(provider.semanasEnMod40, 130);

    final nacimiento = await GuidedInput.applyAnswer(
        provider, 'fechaNacimiento', '05/03/1975');
    expect(nacimiento!.ok, isTrue);
    expect(nacimiento.setFields, ['fechaNacimiento']);
    expect(nacimiento.nextField, isNull);
    expect(provider.fechaNacimiento.year, 1975);
    expect(provider.fechaNacimiento.month, 3);
    expect(provider.fechaNacimiento.day, 5);

    final esposa =
        await GuidedInput.applyAnswer(provider, 'tieneEsposa', 'sí, tengo esposa');
    expect(esposa!.ok, isTrue);
    expect(esposa.nextField, isNull);
    expect(provider.tieneEsposa, isTrue);

    final hijos = await GuidedInput.applyAnswer(provider, 'numeroHijos', 'dos');
    expect(hijos!.ok, isTrue);
    expect(hijos.setFields, ['numeroHijos']);
    expect(hijos.nextField, isNull);
    expect(provider.numeroHijos, 2);

    final padres =
        await GuidedInput.applyAnswer(provider, 'numeroPadres', 'no tengo');
    expect(padres!.ok, isTrue);
    expect(padres.setFields, ['numeroPadres']);
    expect(padres.nextField, isNull);
    expect(provider.numeroPadres, 0);

    final uma = await GuidedInput.applyAnswer(provider, 'umaMultiplier', '20');
    expect(uma!.ok, isTrue);
    expect(uma.setFields, ['umaMultiplier']);
    expect(uma.nextField, isNull);
    expect(provider.umaMultiplier, 20);
  });

  test('applyAnswer semanasEnMod40 "por fechas": sub-flujo inicio/fin calcula '
      'las semanas', () async {
    final provider = await buildProvider();

    // "por fechas" enruta al sub-flujo interno (fecha inicio).
    final porFechas =
        await GuidedInput.applyAnswer(provider, 'semanasEnMod40', 'por fechas');
    expect(porFechas!.ok, isTrue);
    expect(porFechas.setFields, isEmpty);
    expect(porFechas.nextField, 'm40StartDate');

    final inicio =
        await GuidedInput.applyAnswer(provider, 'm40StartDate', '01/01/2010');
    expect(inicio!.ok, isTrue);
    expect(inicio.setFields, ['startDate']);
    expect(inicio.nextField, 'm40EndDate');
    expect(provider.startDate, DateTime(2010, 1, 1));

    final fin =
        await GuidedInput.applyAnswer(provider, 'm40EndDate', '31/12/2010');
    expect(fin!.ok, isTrue);
    expect(fin.setFields, containsAll(['endDate', 'semanasEnMod40']));
    expect(fin.nextField, isNull);
    expect(provider.endDate, DateTime(2010, 12, 31));
    // 364 días → 52 semanas exactas (round-trip limpio: dias/7 * 7 = dias).
    expect(provider.semanasEnMod40, closeTo(52.0, 0.001));
  });

  test('fechas de M40 aceptan fechas recientes (sin la restricción de edad '
      '18+ de la fecha de nacimiento)', () async {
    final provider = await buildProvider();
    // 01/01/2020: la fecha de nacimiento la rechazaría (edad ~6), pero para
    // M40 es una fecha de inicio perfectamente válida.
    final inicio =
        await GuidedInput.applyAnswer(provider, 'm40StartDate', '01/01/2020');
    expect(inicio!.ok, isTrue);
    expect(provider.startDate, DateTime(2020, 1, 1));
  });

  test('applyAnswer: devuelve null cuando la respuesta no se puede interpretar',
      () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);

    expect(
      await GuidedInput.applyAnswer(provider, 'tieneEsposa', 'quizás'),
      isNull,
    );
    expect(
      await GuidedInput.applyAnswer(provider, 'semanasCotizadas', 'hola'),
      isNull,
    );
    expect(
      await GuidedInput.applyAnswer(provider, 'salarioPromedio250Semanas', 'abc'),
      isNull,
    );
    expect(
      await GuidedInput.applyAnswer(provider, 'semanasEnMod40', 'muchas'),
      isNull,
    );
    expect(
      await GuidedInput.applyAnswer(provider, 'numeroHijos', 'muchos'),
      isNull,
    );
    // Fuera de rango para edad de retiro.
    expect(
      await GuidedInput.applyAnswer(provider, 'edadRetiro', '45'),
      isNull,
    );
    // Fecha no reconocida (sin día/mes o futuro).
    expect(
      await GuidedInput.applyAnswer(provider, 'fechaNacimiento', '45'),
      isNull,
    );
    expect(
      await GuidedInput.applyAnswer(provider, 'fechaNacimiento', 'marzo 1975'),
      isNull,
    );
    // Multiplicador de UMA fuera de rango (1-25).
    expect(
      await GuidedInput.applyAnswer(provider, 'umaMultiplier', '30'),
      isNull,
    );
    // Fechas de M40: inicio no es fecha y fin <= inicio (sin mutar).
    expect(
      await GuidedInput.applyAnswer(provider, 'm40StartDate', 'abc'),
      isNull,
    );
    provider.setStartDate(DateTime(2010, 1, 1));
    expect(
      await GuidedInput.applyAnswer(provider, 'm40EndDate', '01/01/2009'),
      isNull,
    );
  });

  test('todos los datos (vitales + respaldo + opcionales) se piden en orden '
      'fijo y una sola vez', () async {
    final provider = await buildProvider();
    // Sin initialize() → salarioDiarioPromedio = 0 → también se pide el
    // respaldo salarioDiarioPromedio antes de los opcionales.

    final requested = <String>{};
    final fields = <String>[];
    while (true) {
      final guide = GuidedInput.nextGuide(provider, requested);
      if (guide == null) break;
      requested.add(guide.field);
      fields.add(guide.field);
    }
    expect(fields, [
      'semanasCotizadas',
      'salarioPromedio250Semanas',
      'semanasEnMod40',
      'salarioDiarioPromedio',
      'fechaNacimiento',
      'tieneEsposa',
      'numeroHijos',
      'numeroPadres',
      'umaMultiplier',
    ]);
  });

  test('tieneEsposa ofrece chips "Sí"/"No"', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(provider, {
      'semanasCotizadas',
      'salarioPromedio250Semanas',
      'semanasEnMod40',
      'fechaNacimiento',
      'edadRetiro',
    });
    expect(guide!.field, 'tieneEsposa');
    expect(guide.suggestions, ['Sí', 'No']);
  });

  test('numeroHijos ofrece chips 1-4 y numeroPadres 0-2', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);

    final hijos = GuidedInput.nextGuide(provider, {
      'semanasCotizadas',
      'salarioPromedio250Semanas',
      'semanasEnMod40',
      'fechaNacimiento',
      'edadRetiro',
      'tieneEsposa',
    });
    expect(hijos!.field, 'numeroHijos');
    expect(hijos.suggestions, ['1', '2', '3', '4']);

    final padres = GuidedInput.nextGuide(provider, {
      'semanasCotizadas',
      'salarioPromedio250Semanas',
      'semanasEnMod40',
      'fechaNacimiento',
      'edadRetiro',
      'tieneEsposa',
      'numeroHijos',
    });
    expect(padres!.field, 'numeroPadres');
    expect(padres.suggestions, ['0', '1', '2']);
  });

  test('umaMultiplier ofrece chips 25/20/15/10/5/1', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(provider, {
      'semanasCotizadas',
      'salarioPromedio250Semanas',
      'semanasEnMod40',
      'fechaNacimiento',
      'edadRetiro',
      'tieneEsposa',
      'numeroHijos',
      'numeroPadres',
    });
    expect(guide!.field, 'umaMultiplier');
    expect(guide.suggestions, ['25', '20', '15', '10', '5', '1']);
  });

  test('todos los campos completos: nextGuide devuelve null (guía termina)',
      () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(
      provider,
      {
        'semanasCotizadas',
        'salarioPromedio250Semanas',
        'semanasEnMod40',
        'fechaNacimiento',
        'edadRetiro',
        'tieneEsposa',
        'numeroHijos',
        'numeroPadres',
        'umaMultiplier',
      },
    );
    expect(guide, isNull);
  });

  test('applyAnswer fechaNacimiento: acepta varios formatos de fecha y rechaza '
      'las no plausibles', () async {
    final provider = await buildProvider();

    for (final text in [
      '05/03/1975',
      '05-03-1975',
      '05.03.1975',
      '1975-03-05',
      '5 de marzo de 1975',
      '5 de Marzo del 1975',
    ]) {
      final result =
          await GuidedInput.applyAnswer(provider, 'fechaNacimiento', text);
      expect(result!.ok, isTrue, reason: 'debió aceptar "$text"');
      expect(provider.fechaNacimiento.year, 1975, reason: 'para "$text"');
      expect(provider.fechaNacimiento.month, 3, reason: 'para "$text"');
      expect(provider.fechaNacimiento.day, 5, reason: 'para "$text"');
    }

    // DDMMYYYY compacto (8 dígitos): 30011969 → 30/01/1969.
    final compacto =
        await GuidedInput.applyAnswer(provider, 'fechaNacimiento', '30011969');
    expect(compacto!.ok, isTrue, reason: 'debió aceptar "30011969"');
    expect(provider.fechaNacimiento.year, 1969);
    expect(provider.fechaNacimiento.month, 1);
    expect(provider.fechaNacimiento.day, 30);

    // Fecha futura → inválida.
    final futura = DateTime.now().add(const Duration(days: 1));
    final futuraText = '${futura.day}/${futura.month}/${futura.year}';
    expect(
      await GuidedInput.applyAnswer(provider, 'fechaNacimiento', futuraText),
      isNull,
    );
    // Sin día/mes → inválida.
    expect(
      await GuidedInput.applyAnswer(provider, 'fechaNacimiento', '1975'),
      isNull,
    );
    // Día imposible → inválida (31/02 se normaliza a 03/03).
    expect(
      await GuidedInput.applyAnswer(provider, 'fechaNacimiento', '31/02/1975'),
      isNull,
    );
  });

  test(
      'applyAnswer salarioPromedio250Semanas: colapsa el desglose no-Mod40 en '
      'un único registro de 250 semanas y conserva los periodos Mod40', () async {
    final provider = await buildProvider();
    // Sembrar un desglose con varios periodos: 2 no-Mod40 y 1 Mod40.
    provider.setPeriodos([
      PeriodoSalarial(salarioDiario: 1000, semanas: 100, esMod40: false),
      PeriodoSalarial(salarioDiario: 1200, semanas: 150, esMod40: false),
      PeriodoSalarial(salarioDiario: 800, semanas: 130, esMod40: true),
    ]);
    // El usuario teclea su promedio de las 250 semanas.
    final result = await GuidedInput.applyAnswer(
      provider,
      'salarioPromedio250Semanas',
      '1500',
    );
    expect(result!.ok, isTrue);

    // El promedio tecleado se conserva.
    expect(provider.salarioPromedio250Semanas, 1500);
    // "Antes" queda en 250 semanas (un único registro no-Mod40).
    expect(provider.semanasAntesMod40, 250);
    // El desglose queda: 1 registro no-Mod40 de 250 semanas + el Mod40.
    final noMod40 = provider.periodos.where((p) => !p.esMod40).toList();
    final mod40 = provider.periodos.where((p) => p.esMod40).toList();
    expect(noMod40.length, 1, reason: 'debe quedar UN solo registro no-Mod40');
    expect(noMod40.single.semanas, 250);
    expect(noMod40.single.salarioDiario, 1500);
    // Los periodos Mod40 se conservan intactos.
    expect(mod40.length, 1);
    expect(mod40.single.semanas, 130);
    expect(mod40.single.salarioDiario, 800);
    // Semanas en Mod40 y total cotizadas se recalculan.
    expect(provider.semanasEnMod40, 130);
    expect(provider.semanasCotizadas, 250 + 130);
  });
}
