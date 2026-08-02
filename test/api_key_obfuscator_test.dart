import 'package:flutter_test/flutter_test.dart';
import 'package:d_0_pension/core/ai/api_key_obfuscator.dart';

void main() {
  group('ApiKeyObfuscator', () {
    test('decodifica(encode(x)) == x (ida y vuelta)', () {
      const samples = [
        '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',
        '',
        'a',
        'clave-con-acentos-ñ-ü-123',
      ];
      for (final s in samples) {
        final encoded = ApiKeyObfuscator.encode(s);
        expect(ApiKeyObfuscator.decode(encoded), s);
      }
    });

    test('la key ofuscada del build decodifica a la key original', () {
      // Valor generado por scripts/ofuscar_api_key.py con XOR_KEY=KEY-OFUSCACION
      const obfuscated =
          'OC50Qj1rI2JueXYreX4vdzxOKnM0YXtyeiopKnggO08tJWM2InV1Ki4scnA8FC4kYzIlJSJ9ey16cmwaKnAzNXB4Inh+eXtxPQ==';
      const expected =
          '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';
      expect(ApiKeyObfuscator.decode(obfuscated), expected);
    });

    test('la clave XOR documentada coincide con la del codigo', () {
      expect(ApiKeyObfuscator.keyMatchesDocumented, isTrue);
    });
  });
}
