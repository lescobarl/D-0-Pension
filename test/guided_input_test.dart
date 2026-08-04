import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/ai/guided_input.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Pruebas de la guía determinista de captura de datos.
///
/// Es LA APP (no la IA) quien decide qué dato falta y pregunta UN dato a la
/// vez en un orden fijo, reemplazando la pregunta vaga "¿Falta algún dato?".
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

  test('proveedor vacío: pide primero semanasCotizadas (obligatorio)', () async {
    final provider = await buildProvider();
    final guide = GuidedInput.nextGuide(provider, <String>{});
    expect(guide, isNotNull);
    expect(guide!.field, 'semanasCotizadas');
    expect(guide.question, contains('semanas'));
  });

  test('semanasCotizadas se vuelve a preguntar si sigue en 0 aunque ya se '
      'registró en requested (campo obligatorio)', () async {
    final provider = await buildProvider();
    // Se pidió antes (requested lo contiene), pero el proveedor sigue en 0 →
    // el campo obligatorio se vuelve a preguntar hasta llenarse.
    final guide = GuidedInput.nextGuide(provider, {'semanasCotizadas'});
    expect(guide!.field, 'semanasCotizadas');
  });

  test('con semanas, pide salarioDiarioPromedio (segundo obligatorio)',
      () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    final guide = GuidedInput.nextGuide(provider, <String>{});
    expect(guide!.field, 'salarioDiarioPromedio');
    expect(guide.suggestions, isEmpty);
  });

  test('obligatorios llenos: pide fechaNacimiento (primer opcional)', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(provider, <String>{});
    expect(guide!.field, 'fechaNacimiento');
    expect(guide.question, contains('fecha de nacimiento'));
    // La fecha se captura como texto libre (sin chips).
    expect(guide.suggestions, isEmpty);
  });

  test('edadRetiro con metadata: sugiere TODAS las edades del dropdown '
      '(60, 60.51, ..., 65)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
    await provider.initialize();
    // initialize() siembra semanas/salario > 0 → primer opcional es
    // fechaNacimiento; al marcarlo como solicitado toca edadRetiro.
    final guide = GuidedInput.nextGuide(provider, {'fechaNacimiento'});
    expect(guide!.field, 'edadRetiro');
    expect(guide.suggestions, [
      '60', '60.51', '61', '61.51', '62', '62.51',
      '63', '63.51', '64', '64.51', '65',
    ]);
  });

  test('applyAnswer: interpreta y aplica respuestas cortas de la guía', () async {
    final provider = await buildProvider();

    final semanas =
        await GuidedInput.applyAnswer(provider, 'semanasCotizadas', '1200');
    expect(semanas!.ok, isTrue);
    expect(semanas.setFields, ['semanasCotizadas']);
    expect(provider.semanasCotizadas, 1200);

    final salario =
        await GuidedInput.applyAnswer(provider, 'salarioDiarioPromedio', '500.50');
    expect(salario!.ok, isTrue);
    expect(salario.setFields, ['salarioDiarioPromedio']);
    expect(provider.salarioDiarioPromedio, 500.5);

    final nacimiento = await GuidedInput.applyAnswer(
        provider, 'fechaNacimiento', '05/03/1975');
    expect(nacimiento!.ok, isTrue);
    expect(nacimiento.setFields, ['fechaNacimiento']);
    expect(provider.fechaNacimiento.year, 1975);
    expect(provider.fechaNacimiento.month, 3);
    expect(provider.fechaNacimiento.day, 5);

    final esposa =
        await GuidedInput.applyAnswer(provider, 'tieneEsposa', 'sí, tengo esposa');
    expect(esposa!.ok, isTrue);
    expect(provider.tieneEsposa, isTrue);

    final hijos = await GuidedInput.applyAnswer(provider, 'numeroHijos', 'dos');
    expect(hijos!.ok, isTrue);
    expect(hijos.setFields, ['numeroHijos']);
    expect(provider.numeroHijos, 2);

    final padres =
        await GuidedInput.applyAnswer(provider, 'numeroPadres', 'no tengo');
    expect(padres!.ok, isTrue);
    expect(padres.setFields, ['numeroPadres']);
    expect(provider.numeroPadres, 0);

    final uma = await GuidedInput.applyAnswer(provider, 'umaMultiplier', '20');
    expect(uma!.ok, isTrue);
    expect(uma.setFields, ['umaMultiplier']);
    expect(provider.umaMultiplier, 20);
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
  });

  test('opcionales se piden una sola vez y en orden fijo: nacimiento → edad → '
      'esposa → hijos → padres → uma', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);

    final requested = <String>{};
    final fields = <String>[];
    while (true) {
      final guide = GuidedInput.nextGuide(provider, requested);
      if (guide == null) break;
      requested.add(guide.field);
      fields.add(guide.field);
    }
    expect(fields, [
      'fechaNacimiento',
      'edadRetiro',
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
    final guide = GuidedInput.nextGuide(
        provider, {'fechaNacimiento', 'edadRetiro'});
    expect(guide!.field, 'tieneEsposa');
    expect(guide.suggestions, ['Sí', 'No']);
  });

  test('numeroHijos ofrece chips 1-4 y numeroPadres 0-2', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);

    final hijos = GuidedInput.nextGuide(
        provider, {'fechaNacimiento', 'edadRetiro', 'tieneEsposa'});
    expect(hijos!.field, 'numeroHijos');
    expect(hijos.suggestions, ['1', '2', '3', '4']);

    final padres = GuidedInput.nextGuide(
        provider, {'fechaNacimiento', 'edadRetiro', 'tieneEsposa', 'numeroHijos'});
    expect(padres!.field, 'numeroPadres');
    expect(padres.suggestions, ['0', '1', '2']);
  });

  test('todos los campos completos: nextGuide devuelve null (guía termina)',
      () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(
      provider,
      {
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

  test('umaMultiplier ofrece chips 25/20/15', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(
      provider,
      {
        'fechaNacimiento',
        'edadRetiro',
        'tieneEsposa',
        'numeroHijos',
        'numeroPadres',
      },
    );
    expect(guide!.field, 'umaMultiplier');
    expect(guide.suggestions, ['25', '20', '15']);
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
}
