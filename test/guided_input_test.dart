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

  test('obligatorios llenos: pide edadRetiro (primer opcional) con chips 60/62/65',
      () async {
    final provider = await buildProvider();
    provider.setSemanasCotizadas(1200);
    provider.setSalarioDiarioPromedio(500);
    final guide = GuidedInput.nextGuide(provider, <String>{});
    expect(guide!.field, 'edadRetiro');
    expect(guide.suggestions, ['60', '62', '65']);
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
