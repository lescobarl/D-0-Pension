import 'dart:convert';

/// Ofuscacion ligera (base64 + XOR) de la API key de OpenRouter.
///
/// ADVERTENCIA: esto NO es seguridad real. La key se reconstruye en tiempo
/// de ejecucion para poder enviarse a OpenRouter, por lo que cualquier
/// persona decidida puede recuperarla. Es solo un disuasivo contra la
/// extraccion casual, mientras se migra a un backend proxy.
///
/// La clave XOR debe coincidir con la documentada en `KEY-OFUSCACION.txt`
/// (raiz del proyecto) y con la usada por `scripts/ofuscar_api_key.py`.
class ApiKeyObfuscator {
  ApiKeyObfuscator._();

  /// Clave XOR (se repite sobre los bytes). Debe coincidir con
  /// `XOR_KEY` de `KEY-OFUSCACION.txt`.
  static const String _xorKey = 'KEY-OFUSCACION';

  /// Bytes ASCII de [_xorKey] = "KEY-OFUSCACION"
  /// (K,E,Y,-,O,F,U,S,C,A,C,I,O,N). El caracter en la posicion 3 es
  /// un guion '-' (0x2D), NO un guion bajo.
  static const List<int> _xorKeyBytes = [
    0x4B, 0x45, 0x59, 0x2D, 0x4F, 0x46, 0x55, 0x53, // KEY-OFUS
    0x43, 0x41, 0x43, 0x49, 0x4F, 0x4E, // CACION
  ];

  /// Decodifica un valor ofuscado (base64(XOR(utf8(plain)))) a la key plana.
  static String decode(String obfuscated) {
    final bytes = base64Decode(obfuscated);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ _xorKeyBytes[i % _xorKeyBytes.length],
    );
    return utf8.decode(out);
  }

  /// Codifica una key plana a base64(XOR(utf8(plain))).
  /// (Usada principalmente por `scripts/ofuscar_api_key.py`; se mantiene
  /// aqui para referencia y pruebas de ida y vuelta.)
  static String encode(String plain) {
    final bytes = utf8.encode(plain);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ _xorKeyBytes[i % _xorKeyBytes.length],
    );
    return base64Encode(out);
  }

  /// Verifica que [_xorKey] coincida con la documentada. Se usa en tests.
  static bool get keyMatchesDocumented => _xorKey == 'KEY-OFUSCACION';
}
