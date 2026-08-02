import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/ai_chat_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Regression tests for the OpenRouter HTTP transport in AiChatService.
///
/// These prove the request/response path works through `package:http` (which
/// resolves to BrowserClient/fetch on web) and never touches `dart:io`
/// (HttpClient) — the root cause of the web-only runtime crash
/// `Unsupported operation: Platform._version`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AiChatService> buildService(http.Client client) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
    return AiChatService(
      provider: provider,
      apiKey: 'test-key',
      client: client,
    );
  }

  test(
    'POSTs to OpenRouter with correct headers/body and parses assistant text',
    () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Tu pensión estimada es de 87,000 MXN'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = await buildService(mock);
      final result = await service.callOpenRouterApiForTest([
        {'role': 'user', 'text': 'Quiero una pensión arriba de 87000'},
      ]);

      expect(
        captured.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(captured.method, 'POST');
      expect(captured.headers['Content-Type'], startsWith('application/json'));
      expect(captured.headers['Authorization'], 'Bearer test-key');
      expect(captured.headers['HTTP-Referer'], 'https://d-0-pension.app');
      expect(captured.headers['X-Title'], 'D-0-Pension Calculator');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'google/gemini-2.5-flash-lite');
      expect(body['messages'], [
        {'role': 'user', 'text': 'Quiero una pensión arriba de 87000'},
      ]);

      // UTF-8 accents must survive the round trip.
      expect(result, 'Tu pensión estimada es de 87,000 MXN');
      service.dispose();
    },
  );

  test('throws Exception with HTTP status on non-200 response', () async {
    final mock = MockClient((request) async {
      return http.Response(
        '{"error":"sin credito"}',
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final service = await buildService(mock);
    await expectLater(
      service.callOpenRouterApiForTest([
        {'role': 'user', 'text': 'hola'},
      ]),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('HTTP 401'),
        ),
      ),
    );
    service.dispose();
  });

  test('throws Exception when response has no choices', () async {
    final mock = MockClient((request) async {
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final service = await buildService(mock);
    await expectLater(
      service.callOpenRouterApiForTest([
        {'role': 'user', 'text': 'hola'},
      ]),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No choices'),
        ),
      ),
    );
    service.dispose();
  });
}
