import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/ai_chat_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// End-to-end tests proving the AI chat transcribes values into the captura
/// fields through `AiChatService.sendMessage` → `FieldExtractor.applyValues`.
///
/// The MockClient simulates OpenRouter returning a `fill_fields` JSON payload.
/// These tests verify the user-facing goal: an edit instruction such as
/// "mueve la edad de pensión a 63 años" actually updates `provider.edadRetiro`
/// (the exact scenario that used to fail leaving the field blank).
class _Harness {
  final RetroactiveProvider provider;
  final AiChatService service;

  _Harness(this.provider, this.service);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_Harness> buildHarness(http.Client client) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
    // Carga app_metadata.json (el evaluador lanza StateError si no se inicializa
    // y sendMessage → _buildAppStateContext lo necesita). Patrón usado en
    // validacion_tabs_ia_test.dart.
    await provider.initialize();
    final service = AiChatService(
      provider: provider,
      apiKey: 'test-key',
      client: client,
    );
    return _Harness(provider, service);
  }

  http.Response openAiResponse(String content) => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': content},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  // Permite que la continuación asíncrona de setEdadRetiro (Future.delayed
  // con duración cero) termine antes de finalizar el test.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  test(
      'modo editar: "mueve la edad de pensión a 63 años" aplica edadRetiro '
      '(escenario real que fallaba)', () async {
    final content = jsonEncode({
      'type': 'fill_fields',
      'values': {'edadRetiro': 63},
      'message': 'He actualizado la edad de retiro a 63 años.',
      'missing_fields': <String>[],
    });
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    final result =
        await harness.service.sendMessage('mueve la edad de pensión a 63 años');
    await settle();

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('edadRetiro'));
    expect(harness.provider.edadRetiro, 63);
    harness.service.dispose();
  });

  test('tolera texto adicional después del JSON (robustez del parseo)', () async {
    final content = '{"type":"fill_fields","values":{"semanasCotizadas":1300},'
        '"message":"He registrado tus semanas cotizadas.","missing_fields":[]} '
        'Aquí tienes tus datos actualizados, ¿necesitas algo más?';
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    final result =
        await harness.service.sendMessage('tengo 1300 semanas cotizadas');

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('semanasCotizadas'));
    expect(harness.provider.semanasCotizadas, 1300);
    harness.service.dispose();
  });

  test('normaliza sinónimos en el JSON de la IA (edad → edadRetiro)', () async {
    final content = jsonEncode({
      'type': 'fill_fields',
      'values': {'edad': 63},
      'message': 'He actualizado tu edad de retiro.',
      'missing_fields': <String>[],
    });
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    final result = await harness.service.sendMessage('mi edad de retiro será 63');
    await settle();

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('edadRetiro'));
    expect(harness.provider.edadRetiro, 63);
    harness.service.dispose();
  });

  test(
      'GUARDIA: "mueve la edad de pensión a 62 años" aplica 62 aunque la IA '
      'devuelva 63 (contaminación del número del ejemplo del prompt)', () async {
    // Escenario real del bug: la IA contesta con el número del ejemplo del
    // prompt (63) en vez del número que pidió el usuario (62). La guardia
    // determinista FieldExtractor.enforceRequestedAge debe corregirlo a 62.
    final content = jsonEncode({
      'type': 'fill_fields',
      'values': {'edadRetiro': 63},
      'message': 'He actualizado la edad de retiro.',
      'missing_fields': <String>[],
    });
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    final result =
        await harness.service.sendMessage('mueve la edad de pensión a 62 años');
    await settle();

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    // El valor que se envió a applyValues ya es 62, no 63.
    expect(fill.values['edadRetiro'], 62);
    expect(fill.setFields, contains('edadRetiro'));
    // El provider queda en 62 (NO en 63, el número contaminado que devolvió).
    expect(harness.provider.edadRetiro, 62);
    harness.service.dispose();
  });

  test(
      'conteo perezoso: consume un cupo diario SOLO con el primer mensaje de '
      'cada sesión (apertura de pestaña y "Limpiar conversación" no consumen)',
      () async {
    final mock = MockClient(
      (request) async => openAiResponse('¡Hola! Soy tu asistente.'),
    );
    final harness = await buildHarness(mock);

    // Apertura de la pestaña AI (initialize) NO consume cupo diario.
    await harness.service.initialize();
    expect(harness.service.dailySessionCount, 0);

    // "Limpiar conversación" (startNewSession) NO consume cupo diario.
    await harness.service.startNewSession();
    expect(harness.service.dailySessionCount, 0);

    // Primer mensaje de la sesión 1 → consume 1 cupo.
    await harness.service.sendMessage('hola');
    expect(harness.service.dailySessionCount, 1);

    // Segundo mensaje de la misma sesión → NO consume otro cupo.
    await harness.service.sendMessage('gracias');
    expect(harness.service.dailySessionCount, 1);

    // Nueva sesión: primer mensaje → consume otro cupo (total 2).
    await harness.service.startNewSession();
    await harness.service.sendMessage('hola de nuevo');
    expect(harness.service.dailySessionCount, 2);

    harness.service.dispose();
  });

  test('texto natural sin JSON no modifica los campos', () async {
    final mock = MockClient(
      (request) async => openAiResponse(
        '¡Hola! Soy tu asistente de pensiones. ¿En qué puedo ayudarte?',
      ),
    );

    final harness = await buildHarness(mock);
    final edadRetiroInicial = harness.provider.edadRetiro;
    final result = await harness.service.sendMessage('hola');

    expect(result, isA<AiChat>());
    // Sin cambios: el texto natural no debe tocar ningún campo de captura.
    expect(harness.provider.edadRetiro, edadRetiroInicial);
    harness.service.dispose();
  });
}
