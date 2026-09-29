import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tamaño lógico fijo tipo teléfono para goldens deterministas.
const Size goldenLogicalSize = Size(390, 844);

/// Configura un viewport determinista (1.0 dpr) para que el render de golden
/// sea idéntico entre ejecuciones y entre plataformas.
void setGoldenSurface(WidgetTester tester,
    {Size logicalSize = goldenLogicalSize}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.reset);
}

/// Bombea frames hasta que [finder] haga match, con timeout acotado.
/// Evita `pumpAndSettle` en pantallas con campos de texto (cursor) o con
/// cualquier animación residual que impediría asentarse.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('pumpUntilFound: no se encontró $finder dentro de ${timeout.inSeconds}s');
}
