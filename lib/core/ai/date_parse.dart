/// Utilidad compartida de parseo de fechas en español para la IA.
///
/// Centraliza los formatos de fecha que aceptan los flujos de la IA (guía
/// determinista y `fill_fields` libre) para que TODOS los campos usen
/// EXACTAMENTE el mismo parser. Así se elimina la asimetría original en la que
/// `fechaNacimiento` aceptaba el formato compacto de 8 dígitos y `fechaAlta`
/// lo rechazaba con "No entendí tu respuesta".
library;

/// Meses en español → número de mes (1-12).
///
/// Incluye la variante "setiembre" (usada en algunos países) además de
/// "septiembre", ambas con el mismo número (9).
const Map<String, int> _spanishMonths = <String, int>{
  'enero': 1,
  'febrero': 2,
  'marzo': 3,
  'abril': 4,
  'mayo': 5,
  'junio': 6,
  'julio': 7,
  'agosto': 8,
  'septiembre': 9,
  'setiembre': 9,
  'octubre': 10,
  'noviembre': 11,
  'diciembre': 12,
};

/// Extrae los componentes `(año, mes, día)` de una fecha en [text].
///
/// Formatos admitidos (en orden de prioridad):
/// 1. ISO `aaaa-mm-dd`, `aaaa/mm/dd`, `aaaa.mm.dd` — PRIMERO para evitar que
///    "1975-03-05" se malinterprete como dd/mm/aaaa.
/// 2. Compacto de 8 dígitos sin separadores: si los primeros 4 forman un año
///    plausible (1900-2010) se interpreta como `AAAAMMDD` (19750305); de lo
///    contrario como `DDMMAAAA` (30011969 → 30/01/1969).
/// 3. `dd/mm/aaaa`, `dd-mm-aaaa`, `dd.mm.aaaa` → (día, mes, año) reordenado.
/// 4. Nombres de mes en español: "5 de marzo de 1975", "5 de Marzo del 1975".
///
/// Devuelve `null` si no se reconoce ningún formato. NO valida que la fecha
/// sea real (eso lo hace [isRealDate]).
(int?, int?, int?)? rawDate(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  // 1) aaaa-mm-dd (ISO) PRIMERO.
  final iso = RegExp(
    r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$',
  ).firstMatch(trimmed);
  if (iso != null) {
    return (
      int.tryParse(iso.group(1)!),
      int.tryParse(iso.group(2)!),
      int.tryParse(iso.group(3)!),
    );
  }

  // 2) 8 dígitos sin separadores: AAAAMMDD si los primeros 4 son un año
  // plausible (1900-2010); si no, DDMMAAAA.
  final compact = RegExp(r'^(\d{8})$').firstMatch(trimmed);
  if (compact != null) {
    final s = compact.group(1)!;
    final first4 = int.tryParse(s.substring(0, 4));
    if (first4 != null && first4 >= 1900 && first4 <= 2010) {
      // AAAAMMDD
      return (
        first4,
        int.tryParse(s.substring(4, 6)),
        int.tryParse(s.substring(6, 8)),
      );
    }
    // DDMMAAAA
    return (
      int.tryParse(s.substring(4, 8)),
      int.tryParse(s.substring(2, 4)),
      int.tryParse(s.substring(0, 2)),
    );
  }

  // 3) dd/mm/aaaa, dd-mm-aaaa, dd.mm.aaaa → (día, mes, año).
  final dmy = RegExp(
    r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$',
  ).firstMatch(trimmed);
  if (dmy != null) {
    return (
      int.tryParse(dmy.group(3)!),
      int.tryParse(dmy.group(2)!),
      int.tryParse(dmy.group(1)!),
    );
  }

  // 4) Nombres de mes en español ("5 de marzo de 1975"). Se usa [text] (no
  // [trimmed]) para tolerar textos con la fecha al inicio o al final.
  final named = RegExp(
    r'(\d{1,2})\s+(?:de\s+)?([a-záéíóúñ]+)(?:\s+de\s+|\s+del\s+)?(\d{4})',
    caseSensitive: false,
  ).firstMatch(text);
  if (named != null) {
    final month = _spanishMonths[named.group(2)!.toLowerCase()];
    if (month != null) {
      // Grupos (día, mes, año) → devuelve (año, mes, día).
      return (
        int.tryParse(named.group(3)!),
        month,
        int.tryParse(named.group(1)!),
      );
    }
  }

  return null;
}

/// ¿Los componentes forman una fecha REAL (no normalizada por `DateTime`)?
///
/// `DateTime(year, month, day)` normaliza fechas inválidas (p. ej. 31/02 →
/// 03/03); esta función las rechaza comparando los campos normalizados con los
/// ingresados. Devuelve `false` si algún componente es `null` o está fuera de
/// rango.
bool isRealDate(int? year, int? month, int? day) {
  if (year == null || month == null || day == null) return false;
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}
