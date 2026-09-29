import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/presentation/screens/captura_view.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

import 'golden_fonts.dart';

/// Validación de LAYOUT de los resultados Mod40 (parte inferior de
/// CapturaView): las etiquetas deben verse COMPLETAS (sin truncar) y el valor
/// debe quedar pegado al borde derecho, sin desperdiciar el espacio.
///
/// Mide el ancho real de cada etiqueta (con fuentes Roboto reales) contra su
/// ancho natural: si la etiqueta estuviera truncada, su ancho renderizado
/// quedaría por debajo del natural.
///
/// IMPORTANTE: un solo testWidgets por archivo (ver
/// regla_a_19990130_test.dart): un segundo flujo completo
/// pumpWidget(CapturaView) en el mismo proceso se cuelga en pumpWidget.
void main() {
  setUpAll(loadGoldenFonts);

  Future<RetroactiveProvider> _buildProvider() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    );
    await provider.initialize();
    return provider;
  }

  testWidgets(
    'Mod40 resultados: etiquetas completas (sin truncar) y valor pegado a la derecha',
    (WidgetTester tester) async {
      // Pantalla de teléfono típica (390x844): el mismo ancho donde el usuario
      // reportó la etiqueta truncada.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = await _buildProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(home: Scaffold(body: CapturaView())),
        ),
      );
      await tester.pumpAndSettle();

      // Etiquetas de los resultados Mod40 + la compartida de Card2 (misma
      // builder _buildReadOnlyField).
      const labels = [
        'Semanas en Mod40',
        'Semanas Totales',
        'Salario Promedio (con Mod40)',
        'Salario Promedio 250 Semanas',
      ];

      for (final label in labels) {
        final finder = find.text(label);
        expect(
          finder,
          findsOneWidget,
          reason: 'Debe existir la etiqueta "$label".',
        );

        // --- 1) La etiqueta NO debe estar truncada --------------------------
        final textWidget = tester.widget<Text>(finder);
        final context = tester.element(finder);
        final mergedStyle = DefaultTextStyle.of(
          context,
        ).style.merge(textWidget.style);
        final painter = TextPainter(
          text: TextSpan(text: label, style: mergedStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final renderedWidth = tester.getSize(finder).width;
        final naturalWidth = painter.width;

        expect(
          renderedWidth,
          greaterThanOrEqualTo(naturalWidth - 0.5),
          reason:
              'La etiqueta "$label" está truncada: '
              'render=${renderedWidth.toStringAsFixed(1)}px vs '
              'natural=${naturalWidth.toStringAsFixed(1)}px.',
        );

        // --- 2) El valor debe quedar pegado al borde derecho de su fila -----
        final rowFinder = find
            .ancestor(of: finder, matching: find.byType(Row))
            .first;
        final rowRect = tester.getRect(rowFinder);
        final valueFinder = find
            .descendant(of: rowFinder, matching: find.byType(Text))
            .at(1);
        final valueRect = tester.getRect(valueFinder);

        expect(
          (rowRect.right - valueRect.right).abs(),
          lessThan(1.0),
          reason:
              'El valor de "$label" no queda pegado al borde derecho: '
              'fila.right=${rowRect.right.toStringAsFixed(1)}px vs '
              'valor.right=${valueRect.right.toStringAsFixed(1)}px.',
        );
      }
    },
  );
}
