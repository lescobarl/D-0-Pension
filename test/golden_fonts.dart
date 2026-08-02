import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga las fuentes reales Roboto + MaterialIcons empaquetadas con el SDK de
/// Flutter para que los golden tests rendericen glifos reales (en lugar de los
/// rectángulos Ahem que el entorno de test usa por defecto).
///
/// Es un reemplazo sin dependencias de `golden_toolkit.loadAppFonts()`:
/// localiza el SDK vía `FLUTTER_ROOT` o subiendo desde el ejecutable en uso
/// (`flutter_tester`/`dart` viven dentro de `bin/cache` del SDK).
Future<void> loadGoldenFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final flutterRoot = await _findFlutterRoot();
  final fontsPath =
      _join([flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts']);

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

/// Localiza la raíz del SDK de Flutter (el directorio que contiene
/// `bin/cache/artifacts/material_fonts`).
Future<String> _findFlutterRoot() async {
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && envRoot.trim().isNotEmpty) {
    if (Directory(
            _join([envRoot, 'bin', 'cache', 'artifacts', 'material_fonts']))
        .existsSync()) {
      return envRoot;
    }
  }

  // En `flutter test` el ejecutable vive dentro del SDK, así que subimos por
  // los directorios padre hasta encontrar el de material_fonts.
  var dir = Directory(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    if (Directory(
            _join([dir.path, 'bin', 'cache', 'artifacts', 'material_fonts']))
        .existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }

  throw StateError(
    'No se pudo localizar el SDK de Flutter para cargar fuentes de golden '
    'tests. Defina FLUTTER_ROOT o ejecute los tests con `flutter test`.',
  );
}

String _join(List<String> parts) => parts.join(Platform.pathSeparator);
