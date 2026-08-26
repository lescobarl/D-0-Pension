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

  test('modo editar: "mueve la edad de pensión a 63 años" aplica edadRetiro '
      '(escenario real que fallaba)', () async {
    final content = jsonEncode({
      'type': 'fill_fields',
      'values': {'edadRetiro': 63},
      'message': 'He actualizado la edad de retiro a 63 años.',
      'missing_fields': <String>[],
    });
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    final result = await harness.service.sendMessage(
      'mueve la edad de pensión a 63 años',
    );
    await settle();

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('edadRetiro'));
    expect(harness.provider.edadRetiro, 63);
    harness.service.dispose();
  });

  test('tolera texto adicional después del JSON (robustez del parseo)', () async {
    final content =
        '{"type":"fill_fields","values":{"semanasCotizadas":1300},'
        '"message":"He registrado tus semanas cotizadas.","missing_fields":[]} '
        'Aquí tienes tus datos actualizados, ¿necesitas algo más?';
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    final result = await harness.service.sendMessage(
      'tengo 1300 semanas cotizadas',
    );

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
    final result = await harness.service.sendMessage(
      'mi edad de retiro será 63',
    );
    await settle();

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('edadRetiro'));
    expect(harness.provider.edadRetiro, 63);
    harness.service.dispose();
  });

  test(
    'GUARDIA: "mueve la edad de pensión a 62 años" aplica 62 aunque la IA '
    'devuelva 63 (contaminación del número del ejemplo del prompt)',
    () async {
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
      final result = await harness.service.sendMessage(
        'mueve la edad de pensión a 62 años',
      );
      await settle();

      expect(result, isA<AiFillFields>());
      final fill = result! as AiFillFields;
      // El valor que se envió a applyValues ya es 62, no 63.
      expect(fill.values['edadRetiro'], 62);
      expect(fill.setFields, contains('edadRetiro'));
      // El provider queda en 62 (NO en 63, el número contaminado que devolvió).
      expect(harness.provider.edadRetiro, 62);
      harness.service.dispose();
    },
  );

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
    },
  );

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

  test('CAUSA RAÍZ: respuesta en texto libre (AiChat) + "mueve la edad de '
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

    final result = await harness.service.sendMessage(
      'mueve la edad de pensión a 62 años',
    );
    await settle();

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('edadRetiro'));
    expect(harness.provider.edadRetiro, 62);
    harness.service.dispose();
  });

  test('respuesta AiChat + "pon 1300 semanas" aplica semanasCotizadas '
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
    '(campo derivado: se prueba por setFields)',
    () async {
      final mock = MockClient(
        (request) async => openAiResponse('He actualizado tu salario.'),
      );

      final harness = await buildHarness(mock);
      final result = await harness.service.sendMessage('sube el salario a 500');

      expect(result, isA<AiFillFields>());
      final fill = result! as AiFillFields;
      expect(fill.setFields, contains('salarioDiarioPromedio'));
      harness.service.dispose();
    },
  );

  test('respuesta AiChat + "tengo 1300 semanas cotizadas" aplica '
      'semanasCotizadas (número antes del campo)', () async {
    final mock = MockClient(
      (request) async => openAiResponse('Perfecto, quedan registradas.'),
    );

    final harness = await buildHarness(mock);
    final result = await harness.service.sendMessage(
      'tengo 1300 semanas cotizadas',
    );

    expect(result, isA<AiFillFields>());
    final fill = result! as AiFillFields;
    expect(fill.setFields, contains('semanasCotizadas'));
    expect(harness.provider.semanasCotizadas, 1300);
    harness.service.dispose();
  });

  test('GUIADA: al enviar semanas+salario, la app pregunta la fecha de alta '
      '(clave Ley 73) en primer lugar, en vez del "¿Falta algún dato?" de la '
      'IA', () async {
    // La IA devuelve el escenario completo pero termina con la pregunta vaga.
    // La app debe reemplazarla por la guía determinista del siguiente dato.
    final content = jsonEncode({
      'type': 'fill_fields',
      'values': {'semanasCotizadas': 1200, 'salarioDiarioPromedio': 500},
      'message':
          'He encontrado estos datos en tu mensaje. '
          'Los he llenado en la calculadora. ¿Falta algún dato?',
      'missing_fields': <String>[],
    });
    final mock = MockClient((request) async => openAiResponse(content));

    final harness = await buildHarness(mock);
    await harness.service.sendMessage(
      'tengo 1200 semanas cotizadas y mi salario diario es 500',
    );
    await settle();

    final last = harness.service.messages.last;
    expect(last.role, 'assistant');
    // Tras llenar semanas + salario diario, la guía pide en 1er lugar la fecha
    // de alta en el IMSS (clave Ley 73), no el "¿Falta algún dato?" (sin
    // chips).
    expect(last.text, contains('fecha de alta'));
    expect(last.text, isNot(contains('Falta')));
    expect(last.suggestions, isEmpty);
    harness.service.dispose();
  });

  test('GUIADA: turno tras turno la app pregunta un dato a la vez y, al final, '
      'reemplaza el "¿Falta algún dato?" por el mensaje de listo', () async {
    final mock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final msgs = body['messages'] as List<dynamic>;
      final lastUser = msgs
          .lastWhere((m) => m['role'] == 'user')['content']
          .toString()
          .toLowerCase();
      // 1er turno: semanas cotizadas (vital).
      if (lastUser.contains('semanas cotizadas')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'semanasCotizadas': 1200},
            'message': 'Datos capturados.',
            'missing_fields': <String>[],
          }),
        );
      }
      // 2º turno: fecha de alta en el IMSS (clave Ley 73: la app la pide en
      // 1er lugar, antes que el resto de los datos).
      if (lastUser.contains('alta')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'fechaAlta': '1990-06-01'},
            'message': 'Fecha de alta registrada.',
            'missing_fields': <String>[],
          }),
        );
      }
      // 3er turno: salario promedio de las 250 semanas (vital).
      if (lastUser.contains('250')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'salarioPromedio250Semanas': 1500},
            'message': 'Salario actualizado.',
            'missing_fields': <String>[],
          }),
        );
      }
      // 4º turno: semanas en Modalidad 40 (vital).
      if (lastUser.contains('modalidad')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'semanasEnMod40': 130},
            'message': 'Semanas de M40 registradas.',
            'missing_fields': <String>[],
          }),
        );
      }
      // 5º turno: fecha de nacimiento (primer opcional).
      if (lastUser.contains('nac')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'fechaNacimiento': '1975-03-05'},
            'message': 'Fecha registrada.',
            'missing_fields': <String>[],
          }),
        );
      }
      if (lastUser.contains('esposa')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'tieneEsposa': true},
            'message': 'Registrado.',
            'missing_fields': <String>[],
          }),
        );
      }
      if (lastUser.contains('hijos')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'numeroHijos': 2},
            'message': 'Registrado.',
            'missing_fields': <String>[],
          }),
        );
      }
      if (lastUser.contains('padres')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'numeroPadres': 0},
            'message': 'Registrado.',
            'missing_fields': <String>[],
          }),
        );
      }
      if (lastUser.contains('uma')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'umaMultiplier': 20},
            'message': 'Multiplicador actualizado.',
            'missing_fields': <String>[],
          }),
        );
      }
      if (lastUser.contains('62')) {
        return openAiResponse(
          jsonEncode({
            'type': 'fill_fields',
            'values': {'edadRetiro': 62},
            'message': 'Edad actualizada.',
            'missing_fields': <String>[],
          }),
        );
      }
      // Último turno: la IA termina con la pregunta vaga que ya no aplica.
      return openAiResponse(
        jsonEncode({
          'type': 'fill_fields',
          'values': <String, dynamic>{},
          'message':
              'He encontrado estos datos en tu mensaje. '
              'Los he llenado en la calculadora. ¿Falta algún dato?',
          'missing_fields': <String>[],
        }),
      );
    });

    final harness = await buildHarness(mock);
    // 1er turno: semanas cotizadas (vital).
    await harness.service.sendMessage('tengo 1200 semanas cotizadas');
    // 2º turno: la app pide la fecha de alta en 1er lugar (clave Ley 73);
    // el usuario la responde aquí, antes que el resto de los datos.
    await harness.service.sendMessage('me di de alta el 1 de junio de 1990');
    // 3er turno: salario promedio de las 250 semanas (vital).
    await harness.service.sendMessage(
      'mi salario promedio de las 250 semanas es 1500',
    );
    // 4º turno: semanas en Modalidad 40 (vital).
    await harness.service.sendMessage(
      'estoy cotizando 130 semanas en modalidad 40',
    );
    // 5º turno: multiplicador de UMA (vital/obligatorio, acepta 0): se maneja
    // localmente por la guía (sin llamar a la IA) y se aplica 20.
    await harness.service.sendMessage('usa un multiplicador de uma de 20');
    // 6º turno en adelante (opcionales): fechaNacimiento → edadRetiro
    // (dropdown 60-65) → esposa → hijos → padres.
    await harness.service.sendMessage('nací el 5 de marzo de 1975');
    // Edad de pensión: se elige del dropdown (el mock responde 62).
    await harness.service.sendMessage('62');
    await harness.service.sendMessage('sí, tengo esposa');
    await harness.service.sendMessage('tengo 2 hijos');
    await harness.service.sendMessage('no tengo padres dependientes');
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

  test('GUIADA: el chip "Ayúdame a llenar mi cálculo" inicia el llenado guiado '
      'sin llamar a la IA ni consumir cupo diario', () async {
    // Un client que falla si se invoca: la guía debe resolverse localmente.
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA en el inicio guiado');
    });

    final harness = await buildHarness(mock);
    expect(harness.service.dailySessionCount, 0);
    expect(harness.service.messages, isEmpty);

    final result = await harness.service.sendMessage(
      'Ayúdame a llenar mi cálculo de pensión, cuentas conmigo',
    );
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
    // guía SIEMPRE pregunta primero la fecha de alta en el IMSS (clave Ley 73;
    // sin chips).
    expect(last.text, contains('fecha de alta'));
    expect(last.suggestions, isEmpty);
    harness.service.dispose();
  });

  test('GUIADA: con la calculadora vacía, el inicio guiado pregunta la fecha '
      'de alta primero (desde cero, sin API)', () async {
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA en el inicio guiado');
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // SIN initialize(): el estado queda vacío (semanas = 0, salario = 0), por
    // lo que la guía empieza por la fecha de alta (clave Ley 73).
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
    expect(last.text, contains('fecha de alta'));
    expect(last.suggestions, isEmpty);
    service.dispose();
  });

  test('GUIADA: tras el chip, cada respuesta corta se aplica localmente sin '
      'llamar a la IA (flujo determinista de extremo a extremo)', () async {
    // Un client que falla si se invoca: todo el llenado debe resolverse local.
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA durante el llenado guiado');
    });

    final harness = await buildHarness(mock);
    await harness.service.sendMessage(
      'Ayúdame a llenar mi cálculo de pensión, cuentas conmigo',
    );
    // La guía pide la fecha de alta en 1er lugar (clave Ley 73).
    await harness.service.sendMessage('01/06/1990');
    // Vitales: semanasCotizadas → salarioPromedio250Semanas → semanasEnMod40
    // → umaMultiplier (obligatorio, acepta 0).
    await harness.service.sendMessage('1300');
    await harness.service.sendMessage('1500');
    await harness.service.sendMessage('130');
    await harness.service.sendMessage('20');
    // Opcionales: fechaNacimiento → edadRetiro (dropdown 60-65) → esposa →
    // hijos → padres.
    await harness.service.sendMessage('05/03/1975');
    // Edad de pensión: 62 (del dropdown).
    await harness.service.sendMessage('62');
    await harness.service.sendMessage('sí');
    await harness.service.sendMessage('2');
    await harness.service.sendMessage('ninguno');
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
    // Modelo actual: el total capturado (1300) es el historial ANTES de Mod40
    // (fuente primaria). setSemanasEnMod40(130) NO toca el historial: antes
    // sigue = 1300 y el total CON M40 = 1300 + 130 = 1430.
    expect(harness.provider.semanasCotizadas, 1300);
    expect(harness.provider.semanasAntesMod40, closeTo(1300, 0.001));
    expect(harness.provider.salarioPromedio250Semanas, 1500);
    expect(harness.provider.semanasEnMod40, 130);
    expect(harness.provider.totalSemanasConMod40, 1430);
    // Prueba productiva del invariante: la respuesta de la IA (130) quedó en el
    // PRIMER registro del desglose (Mod40 → Semanas) y el escalar se deriva de
    // ahí (updatePeriodo fold de esMod40), NO al revés.
    expect(
      harness.provider.periodos.first.esMod40,
      isTrue,
      reason: 'El primer registro del desglose debe ser el periodo Mod40',
    );
    expect(
      harness.provider.periodos.first.semanas,
      closeTo(130, 0.001),
      reason: 'Las semanas Mod40 respondidas deben vivir en el primer registro',
    );
    expect(harness.provider.fechaNacimiento.year, 1975);
    expect(harness.provider.fechaNacimiento.month, 3);
    expect(harness.provider.fechaNacimiento.day, 5);
    expect(harness.provider.fechaAlta, DateTime(1990, 6, 1));
    // Prueba productiva: la edad de pensión se aplicó desde el dropdown (62).
    expect(harness.provider.edadRetiro, 62);
    expect(harness.provider.tieneEsposa, isTrue);
    expect(harness.provider.numeroHijos, 2);
    expect(harness.provider.numeroPadres, 0);
    expect(harness.provider.umaMultiplier, 20);
    harness.service.dispose();
  });

  test('GUIADA: una respuesta no interpretable vuelve a preguntar el mismo '
      'dato sin llamar a la IA', () async {
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA durante el llenado guiado');
    });

    final harness = await buildHarness(mock);
    await harness.service.sendMessage(
      'Ayúdame a llenar mi cálculo de pensión, cuentas conmigo',
    );
    // Primera pregunta guiada = fecha de alta en el IMSS (clave Ley 73): una
    // respuesta no interpretable vuelve a preguntar la fecha de alta (sin
    // chips).
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    var last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('fecha de alta'));
    expect(last.suggestions, isEmpty);

    // Tras la fecha de alta, toca semanasCotizadas: re-ask sin chips.
    await harness.service.sendMessage('01/06/1990');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
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

    // Tras las semanas de M40, toca el multiplicador de UMA (obligatorio,
    // acepta 0): una respuesta no interpretable se vuelve a preguntar con los
    // chips de UMA.
    await harness.service.sendMessage('130');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('UMA'));
    expect(last.suggestions, isNotEmpty);

    // Tras responder la UMA, toca fechaNacimiento: re-ask de la fecha.
    await harness.service.sendMessage('20');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('fecha'));
    expect(last.suggestions, isEmpty);

    // Tras la fecha de nacimiento, toca edadRetiro (dropdown de edad de
    // pensión): una respuesta no interpretable se vuelve a preguntar con los
    // chips 60-65.
    await harness.service.sendMessage('05/03/1975');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('edad'));
    expect(last.suggestions, isNotEmpty);
    expect(last.suggestions!.first, '60');
    expect(last.suggestions, contains('62'));
    expect(last.suggestions, contains('65'));

    // Tras responder la edad (62), toca tieneEsposa: una respuesta no
    // interpretable se vuelve a preguntar con chips Sí/No.
    await harness.service.sendMessage('62');
    await harness.service.sendMessage('quizás más adelante');
    await settle();

    last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('No entendí tu respuesta'));
    expect(last.text, contains('esposa'));
    expect(last.suggestions, ['Sí', 'No']);
    harness.service.dispose();
  });

  test('GUIADA: una fecha de alta posterior al 1-jul-1997 BLOQUEA el flujo '
      '(mensaje legal de Ley 73, sin avanzar ni "¡Listo!") y una fecha válida '
      'después sí continúa', () async {
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA durante el llenado guiado');
    });

    final harness = await buildHarness(mock);
    await harness.service.sendMessage(
      'Ayúdame a llenar mi cálculo de pensión, cuentas conmigo',
    );
    // Fecha de alta posterior al límite de la Ley 73: bloquea (no avanza).
    await harness.service.sendMessage('01/07/1997');
    await settle();

    var last = harness.service.messages.last;
    expect(last.role, 'assistant');
    expect(last.text, contains('posterior al 1 de julio'));
    expect(last.text, contains('fecha de alta'));
    // Bloqueo: NO muestra "¡Listo!" ni "No entendí tu respuesta".
    expect(last.text, isNot(contains('¡Listo!')));
    expect(last.text, isNot(contains('No entendí')));
    expect(last.suggestions, isEmpty);
    // initialize() siembra fechaAlta = 1988-01-01: lo importante es que NO se
    // guardó la fecha bloqueada.
    expect(harness.provider.fechaAlta, isNot(DateTime(1997, 7, 1)));

    // Tras el bloqueo se vuelve a preguntar la fecha de alta: ahora una fecha
    // válida (pre-Ley 73) SÍ avanza a semanasCotizadas.
    await harness.service.sendMessage('01/06/1990');
    await settle();

    last = harness.service.messages.last;
    expect(harness.provider.fechaAlta, DateTime(1990, 6, 1));
    expect(last.text, contains('semanas'));
    expect(last.text, isNot(contains('¡Listo!')));
    harness.service.dispose();
  });

  test('AI: un JSON truncado de fill_fields NO se filtra a la UI (se muestra '
      'un mensaje elegante)', () async {
    // JSON truncado (falta el cierre): reproduce el bug del error visible
    // `"type":"fill_fields"` tras la pregunta del cónyuge.
    final content =
        '{"type":"fill_fields","values":{"tieneEsposa":true},'
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

  test('REGRESIÓN: re-clic en un chip de una pregunta ya respondida actualiza '
      'ESE campo (bug "2 hijos → 1 hijo no se actualiza")', () async {
    // Un client que falla si se invoca: todo el llenado debe resolverse local.
    final mock = MockClient((request) async {
      throw StateError('No se debe llamar a la IA durante el llenado guiado');
    });

    final harness = await buildHarness(mock);
    await harness.service.sendMessage(
      'Ayúdame a llenar mi cálculo de pensión, cuentas conmigo',
    );
    // La guía pide la fecha de alta en 1er lugar (clave Ley 73).
    await harness.service.sendMessage('01/06/1990');
    // Vitales: semanasCotizadas → salarioPromedio250Semanas → semanasEnMod40
    // → umaMultiplier (obligatorio, acepta 0).
    await harness.service.sendMessage('1300');
    await harness.service.sendMessage('1500');
    await harness.service.sendMessage('130');
    await harness.service.sendMessage('20');
    // Opcionales: fechaNacimiento → edadRetiro (dropdown 60-65) → esposa →
    // hijos → padres.
    await harness.service.sendMessage('05/03/1975');
    await harness.service.sendMessage('62');
    await harness.service.sendMessage('sí');
    // Respondemos "2" a hijos: la guía AVANZA a numeroPadres.
    await harness.service.sendMessage('2');
    await harness.service.sendMessage('ninguno');
    await settle();

    // Estado previo: hijos=2, padres=0, y la guía ya terminó.
    expect(harness.provider.numeroHijos, 2);
    expect(harness.provider.numeroPadres, 0);

    // ── Reproduce el bug ──
    // El chip viejo "1" de la pregunta de hijos sigue visible (por el
    // AutomaticKeepAliveClientMixin). El clic viaja con suggestionField
    // 'numeroHijos' y debe actualizar hijos, NO padres (que es el campo al
    // que la guía ya había avanzado).
    final reClickHijos = await harness.service.sendMessage(
      '1',
      guideField: 'numeroHijos',
    );
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
    final reClickPadres = await harness.service.sendMessage(
      '2',
      guideField: 'numeroPadres',
    );
    await settle();
    expect(harness.provider.numeroPadres, 2);
    expect(harness.provider.numeroHijos, 1);
    expect(reClickPadres, isA<AiFillFields>());
    final reClickPadresFill = reClickPadres as AiFillFields;
    expect(reClickPadresFill.setFields, contains('numeroPadres'));
    expect(reClickPadresFill.values['numeroPadres'], 2);

    // El resto de campos permanece correcto (validación de todos los campos).
    // Modelo actual: "1300 semanas cotizadas" = historial ANTES de Mod40; el
    // total CON M40 = 1300 + 130 = 1430.
    expect(harness.provider.semanasCotizadas, 1300);
    expect(harness.provider.semanasAntesMod40, closeTo(1300, 0.001));
    expect(harness.provider.salarioPromedio250Semanas, 1500);
    expect(harness.provider.semanasEnMod40, 130);
    expect(harness.provider.totalSemanasConMod40, 1430);
    expect(harness.provider.fechaNacimiento.year, 1975);
    expect(harness.provider.fechaNacimiento.month, 3);
    expect(harness.provider.fechaNacimiento.day, 5);
    expect(harness.provider.edadRetiro, 62);
    expect(harness.provider.tieneEsposa, isTrue);
    expect(harness.provider.umaMultiplier, 20);
    // No consumió cupo de sesión diaria (todo local).
    expect(harness.service.dailySessionCount, 0);
    harness.service.dispose();
  });

  test('REGRESIÓN: "semanas cotizadas 1900" y "250 en modalidad 40" no se '
      'confunden (la IA no aplica semanas; el guard determinista sí)', () async {
    // La IA devuelve un fill_fields que NO incluye las semanas (simula que la
    // IA no las aplica). El guard determinista detectRequestedEdits debe
    // aplicarlas correctamente: historial antes=1900, en=250, total CON M40=2150.
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

    // Modelo actual: "semanas cotizadas 1900" = historial ANTES de M40;
    // totalSemanasConMod40 = 1900 + 250 = 2150.
    expect(harness.provider.semanasCotizadas, 1900);
    expect(harness.provider.semanasAntesMod40, 1900);
    expect(harness.provider.totalSemanasConMod40, 2150);
    harness.service.dispose();
  });

  test(
    'OPT-OUT: la IA entiende "no quiero Modalidad 40" → aplica '
    'modalidad40OptOut, limpia el desglose M40 y no aplica los campos M40',
    () async {
      // La IA devuelve un fill_fields con el opt-out y campos M40; el opt-out se
      // aplica primero y los campos M40 del mismo payload se ignoran.
      final content = jsonEncode({
        'type': 'fill_fields',
        'values': <String, dynamic>{
          'modalidad40OptOut': true,
          'semanasEnMod40': 200,
          'umaMultiplier': 15,
          'startDate': '2022-01-15',
          'endDate': '2023-01-15',
        },
        'message': 'Entendido, calculamos tu pensión sin Modalidad 40.',
        'missing_fields': <String>[],
      });
      final mock = MockClient((request) async => openAiResponse(content));

      final harness = await buildHarness(mock);

      // El baseline siembra un renglón esMod40 en el desglose.
      expect(harness.provider.periodos.where((p) => p.esMod40), isNotEmpty);
      final beforeUma = harness.provider.umaMultiplier;
      final beforeStart = harness.provider.startDate;

      final r1 = await harness.service.sendMessage(
        'no quiero hacer modalidad 40',
      );
      await settle();
      expect(r1, isA<AiFillFields>());
      final fill = r1! as AiFillFields;

      expect(fill.setFields, contains('modalidad40OptOut'));
      expect(fill.setFields, isNot(contains('semanasEnMod40')));
      expect(fill.setFields, isNot(contains('umaMultiplier')));
      expect(fill.setFields, isNot(contains('startDate')));
      expect(fill.setFields, isNot(contains('endDate')));

      // Desglose sin renglones M40 y campos M40 intactos (sin "renglón vacío").
      expect(harness.provider.modalidad40OptOut, isTrue);
      expect(harness.provider.periodos.where((p) => p.esMod40), isEmpty);
      expect(harness.provider.semanasEnMod40, 0);
      expect(harness.provider.umaMultiplier, beforeUma);
      expect(harness.provider.startDate, beforeStart);
      harness.service.dispose();
    },
  );
}
