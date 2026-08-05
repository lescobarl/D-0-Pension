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

  test(
      'CAUSA RAÍZ: respuesta en texto libre (AiChat) + "mueve la edad de '
      'pensión a 62 años" SÍ aplica 62 (antes la guardia solo corría si la IA '
      'devolvía fill_fields)', () async {
    // La IA responde en texto libre, típico cuando hay historial de
    // conversación. Sin el detector determinista, esto nunca aplicaba el valor.
    final mock = MockClient(
      (request) async =>
          openAiResponse('He actualizado tu edad de retiro a 62 años.'),
    );

    final harness = await buildHarness(mock);
    // Simula un valor previo distinto presente en la conversación.
    await harness.provider.setEdadRetiro(63);
    await settle();

    final result =
        await harness.service.sendMessage('mueve la edad de pensión a 62 años');
    await settle();

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('edadRetiro'));
    expect(harness.provider.edadRetiro, 62);
    harness.service.dispose();
  });

  test(
      'respuesta AiChat + "pon 1300 semanas" aplica semanasCotizadas '
      '(independiente del tipo de respuesta)', () async {
    final mock = MockClient(
      (request) async => openAiResponse('He registrado tus semanas cotizadas.'),
    );

    final harness = await buildHarness(mock);
    final result = await harness.service.sendMessage('pon 1300 semanas');

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('semanasCotizadas'));
    expect(harness.provider.semanasCotizadas, 1300);
    harness.service.dispose();
  });

  test(
      'respuesta AiChat + "sube el salario a 500" aplica salarioDiarioPromedio '
      '(campo derivado: se prueba por setFields)', () async {
    final mock = MockClient(
      (request) async => openAiResponse('He actualizado tu salario.'),
    );

    final harness = await buildHarness(mock);
    final result = await harness.service.sendMessage('sube el salario a 500');

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('salarioDiarioPromedio'));
    harness.service.dispose();
  });

  test(
      'respuesta AiChat + "tengo 1300 semanas cotizadas" aplica '
      'semanasCotizadas (número antes del campo)', () async {
    final mock = MockClient(
      (request) async => openAiResponse('Perfecto, quedan registradas.'),
    );

    final harness = await buildHarness(mock);
    final result =
        await harness.service.sendMessage('tengo 1300 semanas cotizadas');

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('semanasCotizadas'));
    expect(harness.provider.semanasCotizadas, 1300);
    harness.service.dispose();
  });

  test(
      'GUIADA: al enviar semanas+salario, la app pregunta el siguiente dato '
      '(salario promedio de las 250 semanas), en vez del "¿Falta algún dato?" '
      'de la IA',
      () async {
    // La IA devuelve el escenario completo pero termina con la pregunta vaga.
    // La app debe reemplazarla por la guía determinista del siguiente dato.
    final content = jsonEncode({
      'type': 'fill_fields',
      'values': {'semanasCotizadas': 1200, 'salarioDiarioPromedio': 500},
      'message': 'He encontrado estos datos en tu mensaje. '
          'Los he llenado en la calculadora. ¿Falta algún dato?',
      'missing_fields': <String>[],
    });
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    await harness.service.sendMessage(
        'tengo 1200 semanas cotizadas y mi salario diario es 500');
    await settle();

    final last = harness.service.messages.last;
    expect(last.role, 'assistant');
    // Tras llenar semanas + salario diario, la guía pide el SIGUIENTE dato
    // vital: el salario promedio de las 250 semanas (no ofrece chips).
    expect(last.text, contains('250'));
    expect(last.text, contains('salario promedio'));
    expect(last.text, isNot(contains('Falta')));
    expect(last.suggestions, isEmpty);
    harness.service.dispose();
  });

  test(
      'GUIADA: turno tras turno la app pregunta un dato a la vez y, al final, '
      'reemplaza el "¿Falta algún dato?" por el mensaje de listo', () async {
    final mock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final msgs = body['messages'] as List<dynamic>;
      final lastUser = msgs
          .lastWhere((m) => m['role'] == 'user')['content']
          .toString()
          .toLowerCase();
      // 1er turno: semanas cotizadas (vital #1).
      if (lastUser.contains('semanas cotizadas')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'semanasCotizadas': 1200},
          'message': 'Datos capturados.',
          'missing_fields': <String>[],
        }));
      }
      // 2º turno: salario promedio de las 250 semanas (vital #2).
      if (lastUser.contains('250')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'salarioPromedio250Semanas': 1500},
          'message': 'Salario actualizado.',
          'missing_fields': <String>[],
        }));
      }
      // 3er turno: semanas en Modalidad 40 (vital #3).
      if (lastUser.contains('modalidad')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'semanasEnMod40': 130},
          'message': 'Semanas de M40 registradas.',
          'missing_fields': <String>[],
        }));
      }
      // 4º turno: fecha de nacimiento (primer opcional).
      if (lastUser.contains('nac')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'fechaNacimiento': '1975-03-05'},
          'message': 'Fecha registrada.',
          'missing_fields': <String>[],
        }));
      }
      if (lastUser.contains('esposa')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'tieneEsposa': true},
          'message': 'Registrado.',
          'missing_fields': <String>[],
        }));
      }
      if (lastUser.contains('hijos')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'numeroHijos': 2},
          'message': 'Registrado.',
          'missing_fields': <String>[],
        }));
      }
      if (lastUser.contains('padres')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'numeroPadres': 0},
          'message': 'Registrado.',
          'missing_fields': <String>[],
        }));
      }
      if (lastUser.contains('uma')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'umaMultiplier': 20},
          'message': 'Multiplicador actualizado.',
          'missing_fields': <String>[],
        }));
      }
      if (lastUser.contains('62')) {
        return openAiResponse(jsonEncode({
          'type': 'fill_fields',
          'values': {'edadRetiro': 62},
          'message': 'Edad actualizada.',
          'missing_fields': <String>[],
        }));
      }
      // Último turno: la IA termina con la pregunta vaga que ya no aplica.
      return openAiResponse(jsonEncode({
        'type': 'fill_fields',
        'values': <String, dynamic>{},
        'message': 'He encontrado estos datos en tu mensaje. '
            'Los he llenado en la calculadora. ¿Falta algún dato?',
        'missing_fields': <String>[],
      }));
    });

    final harness = await buildHarness(mock);
    // Vitales: semanas cotizadas → salario 250 → semanas M40.
    await harness.service.sendMessage('tengo 1200 semanas cotizadas');
    await harness.service.sendMessage(
        'mi salario promedio de las 250 semanas es 1500');
    await harness.service.sendMessage(
        'estoy cotizando 130 semanas en modalidad 40');
    // Opcionales: fechaNacimiento → esposa → hijos → padres → uma.
    // (edadRetiro ya NO se pregunta en la guía.)
    await harness.service.sendMessage('nací el 5 de marzo de 1975');
    await harness.service.sendMessage('sí, tengo esposa');
    await harness.service.sendMessage('tengo 2 hijos');
    await harness.service.sendMessage('no tengo padres dependientes');
    await harness.service.sendMessage('usa un multiplicador de uma de 20');
    // Con todos los campos ya marcados, el siguiente turno que toca la IA con
    // la pregunta vaga hace que nextGuide devuelva null → mensaje de ¡Listo!.
    await harness.service.sendMessage('listo, eso es todo');
    await settle();

    final last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('¡Listo!'));
    expect(last.text, isNot(contains('Falta')));
    expect(last.suggestions, isEmpty);
    harness.service.dispose();
  });

  test(
      'GUIADA: el chip "Ayúdame a llenar mi cálculo" inicia el llenado guiado '
      'sin llamar a la IA ni consumir cupo diario', () async {
    // Un client que falla si se invoca: la guía debe resolverse localmente.
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA en el inicio guiado');
    });

    final harness = await buildHarness(mock);
    expect(harness.service.dailySessionCount, 0);
    expect(harness.service.messages, isEmpty);

    final result = await harness.service
        .sendMessage('Ayúdame a llenar mi cálculo de pensión, cuentas conmigo');
    await settle();

    expect(result, isA<AiChat>());
    // El llenado guiado es local: NO consume cupo de sesión diaria.
    expect(harness.service.dailySessionCount, 0);
    // El mensaje del usuario quedó en el historial y el asistente respondió
    // con la pregunta guiada del primer dato pendiente.
    expect(harness.service.messages.first.role, 'user');
    final last = harness.service.messages.last;
    expect(last.role, 'assistant');
    // Aunque los defaults sembrados (semanas/salario > 0) ya están llenos, la
    // guía SIEMPRE pregunta primero las semanas cotizadas (vital; sin chips).
    expect(last.text, contains('semanas'));
    expect(last.suggestions, isEmpty);
    harness.service.dispose();
  });

  test(
      'GUIADA: con la calculadora vacía, el inicio guiado pregunta semanas '
      'primero (desde cero, sin API)', () async {
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA en el inicio guiado');
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // SIN initialize(): el estado queda vacío (semanas = 0, salario = 0), por
    // lo que la guía empieza por el primer dato obligatorio.
    final provider = RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
    final service = AiChatService(
      provider: provider,
      apiKey: 'test-key',
      client: mock,
    );

    final result = await service.sendMessage('Ayúdame a llenar mi cálculo');
    await settle();

    expect(result, isA<AiChat>());
    expect(service.dailySessionCount, 0);
    final last = service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('semanas'));
    expect(last.suggestions, isEmpty);
    service.dispose();
  });

  test(
      'GUIADA: tras el chip, cada respuesta corta se aplica localmente sin '
      'llamar a la IA (flujo determinista de extremo a extremo)', () async {
    // Un client que falla si se invoca: todo el llenado debe resolverse local.
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA durante el llenado guiado');
    });

    final harness = await buildHarness(mock);
    await harness.service
        .sendMessage('Ayúdame a llenar mi cálculo de pensión, cuentas conmigo');
    // Vitales: semanasCotizadas → salarioPromedio250Semanas → semanasEnMod40.
    await harness.service.sendMessage('1300');
    await harness.service.sendMessage('1500');
    await harness.service.sendMessage('130');
    // Opcionales: fechaNacimiento → esposa → hijos → padres → uma.
    // (edadRetiro ya NO se pregunta en la guía.)
    await harness.service.sendMessage('05/03/1975');
    await harness.service.sendMessage('sí');
    await harness.service.sendMessage('2');
    await harness.service.sendMessage('ninguno');
    await harness.service.sendMessage('20');
    await settle();

    // El flujo termina con el mensaje de listo sin pasar por la IA.
    final last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('¡Listo!'));
    expect(last.suggestions, isEmpty);
    // No consumió cupo de sesión diaria (todo local).
    expect(harness.service.dailySessionCount, 0);
    // Los valores quedaron aplicados en el proveedor (los vitales SIEMPRE se
    // preguntan aunque hubiera defaults sembrados).
    // El total capturado (1300) se PRESERVA: el promedio de las 250 semanas ya
    // no sobrescribe el desglose (antes=250) ni el total. setSemanasEnMod40(130)
    // deriva antes = total - en = 1300 - 130 = 1170.
    expect(harness.provider.semanasCotizadas, 1300);
    expect(harness.provider.semanasAntesMod40, closeTo(1170, 0.001));
    expect(harness.provider.salarioPromedio250Semanas, 1500);
    expect(harness.provider.semanasEnMod40, 130);
    // Prueba productiva del invariante: la respuesta de la IA (130) quedó en el
    // PRIMER registro del desglose (Mod40 → Semanas) y el escalar se deriva de
    // ahí (updatePeriodo fold de esMod40), NO al revés.
    expect(harness.provider.periodos.first.esMod40, isTrue,
        reason: 'El primer registro del desglose debe ser el periodo Mod40');
    expect(harness.provider.periodos.first.semanas, closeTo(130, 0.001),
        reason: 'Las semanas Mod40 respondidas deben vivir en el primer registro');
    expect(harness.provider.fechaNacimiento.year, 1975);
    expect(harness.provider.fechaNacimiento.month, 3);
    expect(harness.provider.fechaNacimiento.day, 5);
    expect(harness.provider.tieneEsposa, isTrue);
    expect(harness.provider.numeroHijos, 2);
    expect(harness.provider.numeroPadres, 0);
    expect(harness.provider.umaMultiplier, 20);
    harness.service.dispose();
  });

  test(
      'GUIADA: una respuesta no interpretable vuelve a preguntar el mismo '
      'dato sin llamar a la IA', () async {
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA durante el llenado guiado');
    });

    final harness = await buildHarness(mock);
    await harness.service
        .sendMessage('Ayúdame a llenar mi cálculo de pensión, cuentas conmigo');
    // Primera pregunta guiada = semanasCotizadas: una respuesta no
    // interpretable vuelve a preguntar las semanas (sin chips).
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    var last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('semanas'));
    expect(last.suggestions, isEmpty);

    // Tras dar las semanas, toca salarioPromedio250Semanas: re-ask sin chips.
    await harness.service.sendMessage('1300');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('250'));
    expect(last.suggestions, isEmpty);

    // Tras el salario 250, toca semanasEnMod40: re-ask sin chips (el botón
    // "Por fechas" se eliminó).
    await harness.service.sendMessage('1500');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('Modalidad 40'));
    expect(last.suggestions, isEmpty);

    // Tras las semanas de M40, toca fechaNacimiento: re-ask de la fecha.
    await harness.service.sendMessage('130');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('fecha'));
    expect(last.suggestions, isEmpty);

    // Tras la fecha, toca tieneEsposa (edadRetiro ya NO se pregunta): una
    // respuesta no interpretable se vuelve a preguntar con chips Sí/No.
    await harness.service.sendMessage('05/03/1975');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('esposa'));
    expect(last.suggestions, ['Sí', 'No']);
    harness.service.dispose();
  });

  test(
      'AI: un JSON truncado de fill_fields NO se filtra a la UI (se muestra '
      'un mensaje elegante)', () async {
    // JSON truncado (falta el cierre): reproduce el bug del error visible
    // `"type":"fill_fields"` tras la pregunta del cónyuge.
    final content = '{"type":"fill_fields","values":{"tieneEsposa":true},'
        '"message":"Registrado.","missing_fields":[]';
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    await harness.service.sendMessage('tengo esposa');
    await settle();

    final last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, isNot(contains('fill_fields')));
    expect(last.text, isNot(contains('"type"')));
    expect(last.text, isNot(contains('"values"')));
    expect(last.text, contains('actualizado'));
    harness.service.dispose();
  });

  test(
      'REGRESIÓN: re-clic en un chip de una pregunta ya respondida actualiza '
      'ESE campo (bug "2 hijos → 1 hijo no se actualiza")', () async {
    // Un client que falla si se invoca: todo el llenado debe resolverse local.
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA durante el llenado guiado');
    });

    final harness = await buildHarness(mock);
    await harness.service
        .sendMessage('Ayúdame a llenar mi cálculo de pensión, cuentas conmigo');
    // Vitales.
    await harness.service.sendMessage('1300');
    await harness.service.sendMessage('1500');
    await harness.service.sendMessage('130');
    // Opcionales: fechaNacimiento → esposa → hijos → padres → uma.
    await harness.service.sendMessage('05/03/1975');
    await harness.service.sendMessage('sí');
    // Respondemos "2" a hijos: la guía AVANZA a numeroPadres.
    await harness.service.sendMessage('2');
    await harness.service.sendMessage('ninguno');
    await harness.service.sendMessage('20');
    await settle();

    // Estado previo: hijos=2, padres=0, y la guía ya terminó.
    expect(harness.provider.numeroHijos, 2);
    expect(harness.provider.numeroPadres, 0);

    // ── Reproduce el bug ──
    // El chip viejo "1" de la pregunta de hijos sigue visible (por el
    // AutomaticKeepAliveClientMixin). El clic viaja con suggestionField
    // 'numeroHijos' y debe actualizar hijos, NO padres (que es el campo al
    // que la guía ya había avanzado).
    final reClickHijos =
        await harness.service.sendMessage('1', guideField: 'numeroHijos');
    await settle();

    // El campo correcto se actualizó y el otro quedó intacto.
    expect(harness.provider.numeroHijos, 1);
    expect(harness.provider.numeroPadres, 0);

    // El re-clic devuelve AiFillFields (no AiChat) para que la UI muestre
    // "✅ Datos aplicados" con el valor capturado (bug "No pude aplicar
    // ningún campo" en un clic de chip).
    expect(reClickHijos, isA<AiFillFields>());
    final reClickFill = reClickHijos as AiFillFields;
    expect(reClickFill.setFields, contains('numeroHijos'));
    expect(reClickFill.values['numeroHijos'], 1);
    expect(reClickFill.setFields, isNot(contains('numeroPadres')));

    // Re-clic en el chip de padres también debe ir a su propio campo.
    final reClickPadres =
        await harness.service.sendMessage('2', guideField: 'numeroPadres');
    await settle();
    expect(harness.provider.numeroPadres, 2);
    expect(harness.provider.numeroHijos, 1);
    expect(reClickPadres, isA<AiFillFields>());
    final reClickPadresFill = reClickPadres as AiFillFields;
    expect(reClickPadresFill.setFields, contains('numeroPadres'));
    expect(reClickPadresFill.values['numeroPadres'], 2);

    // El resto de campos permanece correcto (validación de todos los campos).
    expect(harness.provider.semanasCotizadas, 1300);
    expect(harness.provider.semanasAntesMod40, closeTo(1170, 0.001));
    expect(harness.provider.salarioPromedio250Semanas, 1500);
    expect(harness.provider.semanasEnMod40, 130);
    expect(harness.provider.fechaNacimiento.year, 1975);
    expect(harness.provider.fechaNacimiento.month, 3);
    expect(harness.provider.fechaNacimiento.day, 5);
    expect(harness.provider.tieneEsposa, isTrue);
    expect(harness.provider.umaMultiplier, 20);
    // No consumió cupo de sesión diaria (todo local).
    expect(harness.service.dailySessionCount, 0);
    harness.service.dispose();
  });

  test(
      'REGRESIÓN: "semanas cotizadas 1900" y "250 en modalidad 40" no se '
      'confunden (la IA no aplica semanas; el guard determinista sí)', () async {
    // La IA devuelve un fill_fields que NO incluye las semanas (simula que la
    // IA no las aplica). El guard determinista detectRequestedEdits debe
    // aplicarlas correctamente: total=1900, en=250, antes=1650.
    final content = jsonEncode({
      'type': 'fill_fields',
      'values': <String, dynamic>{},
      'message': 'He registrado tus datos.',
      'missing_fields': <String>[],
    });
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);

    // El usuario escribe "semanas cotizadas 1900" (número tras el campo, sin
    // conector). Antes se perdía y dependía de la IA.
    final r1 = await harness.service.sendMessage('semanas cotizadas 1900');
    await settle();
    expect(r1, isA<AiFillFields>());
    expect(harness.provider.semanasCotizadas, 1900);

    // Luego escribe "250 en modalidad 40". Antes se confundía con el total.
    final r2 = await harness.service.sendMessage('250 en modalidad 40');
    await settle();
    expect(r2, isA<AiFillFields>());
    expect(harness.provider.semanasEnMod40, 250);

    // Invariante: total = antes + en, con el total de 1900 conservado.
    expect(harness.provider.semanasCotizadas, 1900);
    expect(harness.provider.semanasAntesMod40 + harness.provider.semanasEnMod40,
        closeTo(1900, 0.001));
    expect(harness.provider.semanasAntesMod40, closeTo(1650, 0.001));
    harness.service.dispose();
  });
}
