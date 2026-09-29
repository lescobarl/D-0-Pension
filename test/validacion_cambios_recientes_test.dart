import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/periodo_salarial.dart';
import 'package:d_0_pension/presentation/screens/captura_view.dart';
import 'package:d_0_pension/presentation/widgets/disclaimer_card.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

void main() {
  Future<RetroactiveProvider> _buildProvider() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final persistenceService = PersistenceService(prefs);
    final formulaEvaluator = FormulaEvaluator();
    final provider = RetroactiveProvider(
      evaluator: formulaEvaluator,
      persistence: persistenceService,
    );
    await provider.initialize();
    return provider;
  }

  // IMPORTANTE (hallazgo empírico): un segundo flujo completo
  // "buildProvider + pumpWidget(CapturaView)" en el MISMO proceso de test se
  // cuelga en pumpWidget. Por eso TODAS las verificaciones de widgets se
  // agrupan en UN solo testWidgets (un único flujo completo por proceso).
  // La prueba unitaria pura se mantiene como test() aparte (los test() puros
  // sí funcionan repetidamente en el mismo proceso).
  testWidgets('Captura: subtítulo, etiqueta desglose, descargo y modo fechas', (
    WidgetTester tester,
  ) async {
    final provider = await _buildProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: CapturaView())),
      ),
    );
    await tester.pumpAndSettle();

    // ── Cambio 1: Subtítulo "Captura SIMPLIFICADA" ──
    expect(find.text('Captura SIMPLIFICADA'), findsOneWidget);

    // ── Cambio 2: Etiqueta de desglose ──
    // El titulo y el badge "(Desglose)" son Text separados en el mismo renglon.
    expect(
      find.text('Captura de salario promedio y Modalidad 40'),
      findsOneWidget,
    );
    expect(find.text('(Desglose)'), findsOneWidget);

    // ── Cambio 4: Descargo de responsabilidad como diálogo modal ──
    // Ya no es una tarjeta ExpansionTile al final del scroll; se abre desde
    // el botón de la esquina superior derecha como diálogo modal.
    expect(find.text('Descargo de Responsabilidad'), findsNothing);

    // Abrir el diálogo directamente (equivale a tocar el botón del AppBar)
    final ctx = tester.element(find.byType(CapturaView));
    DisclaimerCard.show(ctx);
    await tester.pumpAndSettle();

    // El diálogo debe mostrarse con el título y el contenido del README
    expect(find.text('Descargo de Responsabilidad'), findsOneWidget);
    expect(find.textContaining('herramienta de estimación'), findsWidgets);
    // Los datos de contacto (WhatsApp/correo) ya no deben aparecer
    expect(find.textContaining('info@tuplanderetiro.mx'), findsNothing);
    expect(find.textContaining('WhatsApp'), findsNothing);

    // Cerrar el diálogo con el botón "Entendido"
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('Descargo de Responsabilidad'), findsNothing);

    // ── Cambio 3: Toggle de modo fechas en el desglose ──
    // El desglose es un ExpansionTile colapsado por defecto; expandirlo.
    final desgloseTitle = find.text(
      'Captura de salario promedio y Modalidad 40',
    );
    expect(desgloseTitle, findsOneWidget);
    await tester.ensureVisible(desgloseTitle);
    await tester.pumpAndSettle();
    await tester.tap(desgloseTitle);
    await tester.pumpAndSettle();

    // Botón de calendario en las filas de periodo (primer periodo editable)
    final calendarButtons = find.byIcon(Icons.calendar_today);
    expect(calendarButtons, findsWidgets);

    // Llevar el primer toggle a la vista y activar el modo fechas
    await tester.ensureVisible(calendarButtons.first);
    await tester.pumpAndSettle();
    await tester.tap(calendarButtons.first);
    await tester.pumpAndSettle();

    // El toggle cambia a edit_calendar cuando la fila entra en modo fechas
    expect(find.byIcon(Icons.edit_calendar), findsWidgets);

    // Semanas auto-calculadas desde fechas: como los periodos base del Excel
    // ya tienen ambas fechas, la fila muestra "N.NN sem" y los botones
    // muestran la fecha formateada; si el periodo no tuviera fechas mostraría
    // la ayuda "Fechas → sem" y el rótulo "Inicio: —"/"Fin: —".
    final p0 = provider.periodos.first;
    if (p0.fechaInicio != null && p0.fechaTermino != null) {
      final esperadas =
          p0.fechaTermino!.difference(p0.fechaInicio!).inDays / 7.0;
      expect(find.text('${esperadas.toStringAsFixed(2)} sem'), findsWidgets);
    } else {
      expect(find.text('Fechas → sem'), findsWidgets);
      expect(find.text('Inicio: —'), findsWidgets);
      expect(find.text('Fin: —'), findsWidgets);
    }
  });

  test('PeriodoSalarial: semanas se calculan desde fechas (fin-inicio)/7', () {
    final inicio = DateTime(2020, 1, 1);
    final fin = DateTime(2020, 1, 29);
    final dias = fin.difference(inicio).inDays;
    expect(dias, 28);
    final semanas = dias / 7.0;
    expect(semanas, 4.0);

    // El modelo NO auto-deriva semanas desde fechas: el caller debe pasarlas
    // (la vista las calcula como (fin-inicio)/7 y las escribe al periodo).
    final periodo = PeriodoSalarial(
      salarioDiario: 500.0,
      semanas: semanas,
      fechaInicio: inicio,
      fechaTermino: fin,
      esMod40: false,
    );
    expect(periodo.resultado, closeTo(500.0 * semanas, 0.001));
  });
}
