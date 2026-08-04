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

  test('obligatorios llenos: pide edadRetiro (primer opcional) con los rangos '
      'de edad del dropdown (fallback 60..65 si el proveedor no está '
      'inicializado)', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(provider, <String>{});
    expect(guide!.field, 'edadRetiro');
    // Proveedor sin initialize() (sin metadata) → lista de respaldo 60..65.
    expect(guide.suggestions, ['60', '61', '62', '63', '64', '65']);
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
    // initialize() siembra semanas/salario > 0 → primer opcional = edadRetiro.
    final guide = GuidedInput.nextGuide(provider, <String>{});
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
  });

  test('opcionales se piden una sola vez y en orden fijo: edad → esposa → '
      'hijos → padres', () async {
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
    expect(fields, ['edadRetiro', 'tieneEsposa', 'numeroHijos', 'numeroPadres']);
  });

  test('tieneEsposa ofrece chips "Sí"/"No"', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(provider, {'edadRetiro'});
    expect(guide!.field, 'tieneEsposa');
    expect(guide.suggestions, ['Sí', 'No']);
  });

  test('numeroHijos ofrece chips 1-4 y numeroPadres 0-2', () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);

    final hijos = GuidedInput.nextGuide(provider, {'edadRetiro', 'tieneEsposa'});
    expect(hijos!.field, 'numeroHijos');
    expect(hijos.suggestions, ['1', '2', '3', '4']);

    final padres =
        GuidedInput.nextGuide(provider, {'edadRetiro', 'tieneEsposa', 'numeroHijos'});
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
      {'edadRetiro', 'tieneEsposa', 'numeroHijos', 'numeroPadres'},
    );
    expect(guide, isNull);
  });
}
