import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/ai/api_key_obfuscator.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/services/ai_chat_service.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Prueba E2E REAL (sin mocks de IA) contra OpenRouter con la API key real.
///
/// Reproduce EXACTAMENTE el escenario reportado por el usuario:
///   "le dije mueve la edad de pension a 61 anos, me respondio 'He actualizado
///    tu edad de retiro a 61 años' y dejo 63 en Captura".
/// Verifica que `provider.edadRetiro` termine en 61 pase lo que pase lo que la
/// IA devuelva (gracias a la guardia determinista enforceRequestedAge).
///
/// IMPORTANTE: `TestWidgetsFlutterBinding` BLOQUEA todo HTTP real (devuelve
/// 400) al instalar un HttpOverrides de prueba. Aquí se restaura
/// `HttpOverrides.global = null` para que el HTTP de package:http sea REAL
/// (IOClient en VM), mientras el binding sigue activo para que rootBundle y
/// SharedPreferences funcionen igual que en la app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Desbloquea el HTTP real (el binding lo bloquea con un mock que da 400).
  HttpOverrides.global = null;

  test(
    'REAL OpenRouter: "mueve la edad de pensión a 61 años" deja el provider en 61',
    () async {
      // Misma ruta que la app real (rootBundle + ApiKeyObfuscator).
      final jsonStr =
          await rootBundle.loadString('assets/config/api_key.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final apiKey = ApiKeyObfuscator.decode(
          json['openrouter_api_key_obfuscated'] as String);
      expect(apiKey, isNotEmpty, reason: 'Debe existir una API key real');

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = RetroactiveProvider(
        evaluator: FormulaEvaluator(),
        persistence: PersistenceService(prefs),
      );
      await provider.initialize();

      // Cliente HTTP REAL (IOClient en VM).
      final service = AiChatService(
        provider: provider,
        apiKey: apiKey,
        client: http.Client(),
      );
      await service.initialize();
      addTearDown(service.dispose);

      final before = provider.edadRetiro;
      debugPrint('REAL-E2E before edadRetiro=$before');

      final result = await service
          .sendMessage('mueve la edad de pensión a 61 años')
          .timeout(const Duration(seconds: 90));

      // Permite que la continuación asíncrona de setEdadRetiro termine.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      debugPrint('REAL-E2E result type=${result.runtimeType}');
      if (result is AiFillFields) {
        debugPrint('REAL-E2E values=${jsonEncode(result.values)}');
        debugPrint('REAL-E2E message=${result.message}');
        debugPrint('REAL-E2E setFields=${result.setFields}');
      }
      if (result is AiError) {
        debugPrint('REAL-E2E error=${result.error}');
      }
      debugPrint('REAL-E2E after edadRetiro=${provider.edadRetiro}');

      expect(
        provider.edadRetiro,
        61,
        reason: 'El usuario pidió mover la edad a 61 años; Captura debe quedar '
            'en 61 sin importar lo que devuelva la IA',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
