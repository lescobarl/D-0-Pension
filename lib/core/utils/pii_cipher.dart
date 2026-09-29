import 'dart:convert';

/// Ofuscación ligera (base64 + XOR) de datos personales (PII) en reposo.
///
/// Reutiliza el mismo patrón de `ApiKeyObfuscator`
/// (base64(XOR(utf8(plain)))) con una clave dedicada exclusivamente a datos
/// personales, distinta de la usada para la API key de OpenRouter.
///
/// ADVERTENCIA: esto NO es seguridad real. La clave vive en el código fuente y
/// la app necesita reconstruir los valores en tiempo de ejecución, así que
/// cualquier persona decidida puede recuperarlos. Es solo un disuasivo contra
/// la extracción casual de datos sensibles del almacenamiento local
/// (SharedPreferences), no un cifrado de grado producción.
///
/// Los valores numéricos se serializan a su forma textual antes de ofuscar
/// (`double.toString` / `int.toString`), lo que garantiza un round-trip exacto.
class PiiCipher {
  PiiCipher._();

  /// Clave XOR (se repite sobre los bytes del mensaje). Documentada también en
  /// `KEY-PII-OFUSCACION.txt` (raíz del proyecto). Si cambias una, cambia la otra.
  static const String _xorKey = 'PII-OFUSCACION-V1';

  /// Bytes UTF-8 de [_xorKey].
  static final List<int> _xorKeyBytes = utf8.encode(_xorKey);

  /// Decodifica un valor ofuscado (base64(XOR(utf8(plain)))) a texto plano.
  static String decode(String obfuscated) {
    final bytes = base64Decode(obfuscated);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ _xorKeyBytes[i % _xorKeyBytes.length],
    );
    return utf8.decode(out);
  }

  /// Codifica texto plano a base64(XOR(utf8(plain))).
  static String encode(String plain) {
    final bytes = utf8.encode(plain);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ _xorKeyBytes[i % _xorKeyBytes.length],
    );
    return base64Encode(out);
  }

  /// Codifica un [double] conservando su precisión textual exacta.
  static String encodeDouble(double value) => encode(value.toString());

  /// Decodifica un [double] ofuscado por [encodeDouble].
  static double decodeDouble(String obfuscated) =>
      double.parse(decode(obfuscated));

  /// Codifica un [int].
  static String encodeInt(int value) => encode(value.toString());

  /// Decodifica un [int] ofuscado por [encodeInt].
  static int decodeInt(String obfuscated) => int.parse(decode(obfuscated));

  /// Codifica un [bool].
  static String encodeBool(bool value) => encode(value ? '1' : '0');

  /// Decodifica un [bool] ofuscado por [encodeBool].
  static bool decodeBool(String obfuscated) => decode(obfuscated) == '1';
}
