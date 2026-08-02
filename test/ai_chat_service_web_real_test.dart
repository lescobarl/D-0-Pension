import 'dart:convert';

import 'package:d_0_pension/core/ai/api_key_obfuscator.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/ai_chat_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prueba E2E REAL contra el runtime de navegador.
///
/// Se ejecuta SOLO con `flutter test --platform chrome` (kIsWeb == true).
/// Usa el cliente HTTP real (BrowserClient en web) y la API key real, por lo
/// que hace una llamada autentica a OpenRouter SIN mocks. En VM se salta para
/// no disparar red accidentalmente.
void main() {
  test(
    'web E2E: llamada real a OpenRouter desde el navegador (sin mock)',
    () async {
      if (!kIsWeb) {
        markTestSkipped(
            'E2E web real: se ejecuta solo con --platform chrome');
        return;
      }

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = RetroactiveProvider(
        evaluator: FormulaEvaluator(),
        persistence: PersistenceService(prefs),
      );

      // Misma ruta que usa la app real (rootBundle + ApiKeyObfuscator).
      final jsonStr =
          await rootBundle.loadString('assets/config/api_key.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final obfuscated = json['openrouter_api_key_obfuscated'] as String;
      final apiKey = ApiKeyObfuscator.decode(obfuscated);
      expect(apiKey, isNotEmpty, reason: 'Debe existir una API key real');

      // Cliente REAL: en web http.Client() se resuelve a BrowserClient.
      final service = AiChatService(provider: provider, apiKey: apiKey);
      addTearDown(service.dispose);

      final reply = await service
          .callOpenRouterApiForTest(const [
            {
              'role': 'user',
              'content':
                  'Quiero tener una pension de arriba de 87000, tengo 58 '
                      'anos, un hijo menor, gano 3000 diarios y soy soltero. '
                      'Responde en una frase corta.',
            },
          ])
          .timeout(const Duration(seconds: 90));

      expect(reply, isNotEmpty, reason: 'Debe devolver texto del modelo');
      expect(service.lastError, isNull,
          reason: 'No debe quedar error registrado');
      debugPrint('WEB-E2E REAL REPLY: $reply');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
