import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga las fuentes reales Roboto + MaterialIcons para que los golden tests
/// rendericen glifos reales (en lugar de los rectángulos Ahem que el entorno de
/// test usa por defecto).
///
/// Es un reemplazo sin dependencias de `golden_toolkit.loadAppFonts()`. Las
/// fuentes se resuelven en este orden:
///
/// 1. Copias empaquetadas en el repo (`test/fonts/`): byte-idénticas a las del
///    SDK 3.41.x, deterministas en cualquier plataforma y CI. No dependen de la
///    caché de artefactos del SDK (que en runners Linux no incluye
///    `material_fonts`: `flutter test`/`flutter precache` no lo descargan ahí).
/// 2. Caché del SDK (`bin/cache/artifacts/material_fonts`), localizada vía
///    `FLUTTER_ROOT` o subiendo desde el ejecutable en uso.
Future<void> loadGoldenFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repoFonts = _join([Directory.current.path, 'test', 'fonts']);
  final sdkFonts = await _sdkMaterialFontsPath();

  final String fontsPath;
  if (Directory(repoFonts).existsSync()) {
    fontsPath = repoFonts;
  } else if (sdkFonts != null) {
    fontsPath = sdkFonts;
  } else {
    throw StateError(
      'Fuentes de golden tests no encontradas. Se buscó en:\n'
      '  - repo: $repoFonts\n'
      '  - SDK:  $sdkFonts\n'
      'Ejecute los tests con `flutter test` (fuentes del repo siempre presentes).',
    );
  }
  debugPrint('[GOLDEN-FONTS] usando: $fontsPath');

  Future<void> load(String family, String fileName) async {
    final file = File(_join([fontsPath, fileName]));
    if (!file.existsSync()) {
      throw StateError('Fuente no encontrada para golden tests: ${file.path}');
    }
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  // Roboto (regular, medium, bold, italic, black) + iconos de Material.
  await load('Roboto', 'roboto-regular.ttf');
  await load('Roboto', 'roboto-medium.ttf');
  await load('Roboto', 'roboto-bold.ttf');
  await load('Roboto', 'roboto-italic.ttf');
  await load('Roboto', 'roboto-black.ttf');
  await load('MaterialIcons', 'materialicons-regular.otf');
}

/// Devuelve la ruta a `bin/cache/artifacts/material_fonts` del SDK si existe;
/// `null` en caso contrario (runner Linux de CI, SDK recién instalado, etc.).
Future<String?> _sdkMaterialFontsPath() async {
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && envRoot.trim().isNotEmpty) {
    final p = _join([envRoot, 'bin', 'cache', 'artifacts', 'material_fonts']);
    if (Directory(p).existsSync()) return p;
  }

  // En `flutter test` el ejecutable vive dentro del SDK, así que subimos por
  // los directorios padre hasta encontrar el de material_fonts.
  var dir = Directory(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    final p = _join([dir.path, 'bin', 'cache', 'artifacts', 'material_fonts']);
    if (Directory(p).existsSync()) return p;
    dir = dir.parent;
  }

  return null;
}

String _join(List<String> parts) => parts.join(Platform.pathSeparator);
