import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:d_0_pension/presentation/widgets/incremento_ladder_card.dart';
import 'package:d_0_pension/services/retroactive/incremento_ladder.dart';

import 'golden_fonts.dart';

/// Prueba de widget del bloque de recomendación "Escalón de tus Incrementos".
///
/// Verifica que las 3 secciones (sin cabecera ni "La regla (Art. 167)") se
/// rendericen con sus títulos exactos, que los detalles formateados aparezcan
/// correctamente (semanas y meses SIN decimales) y que NO haya desbordamiento
/// (overflow) en la pantalla estándar de 390×844.
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('IncrementoLadderCard muestra las 3 secciones sin overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const advice = IncrementoLadderAdvice(
      incrementosActuales: 31.0,
      semanasTotales: 2090.29,
      semanasEnMod40: 130.29,
      pisoActualSemanas: 2087.0,
      semanasRecortablesSinPerder: 3.29,
      siguienteIncremento: 31.5,
      pisoSiguienteSemanas: 2125.0,
      semanasParaSiguiente: 34.71,
      pisoAnteriorSemanas: 2073.0,
      beneficioIncrementoCompletoMensual: 1917.25,
      beneficioMedioIncrementoMensual: 958.63,
      costoPorSemanaM40: 3970.09,
      ahorroEstimado: 13061.59,
      fraccionMedioIncremento: 13 / 52,
      fraccionIncrementoCompleto: 27 / 52,
      semanasPorMes: 52 / 12,
      recomiendaSubir: false,
      costoParaSubir: 34.71 * 3970.09,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: IncrementoLadderCard(advice: advice),
          ),
        ),
      ),
    );

    // Títulos exactos de las 3 secciones que se mantienen (sin cabecera
    // "ESCALÓN DE TUS INCREMENTOS" ni "La regla (Art. 167)").
    expect(find.text('Estás en 31 incrementos'), findsOneWidget);
    expect(find.text('No conviene seguir aportando'), findsOneWidget);
    expect(find.text('AHORRAR sin perder escalón'), findsOneWidget);
    expect(find.text('ESCALÓN DE TUS INCREMENTOS'), findsNothing);
    expect(find.text('La regla (Art. 167)'), findsNothing);

    // Detalles formateados SIN decimales en semanas y meses (1960.00 → 1,960).
    expect(find.textContaining('Con 2,090 semanas cotizadas'), findsOneWidget);
    expect(find.textContaining('(1,960 antes + 130 Mod40)'), findsOneWidget);
    expect(find.textContaining('Faltan 35 semanas Mod40'), findsOneWidget);
    expect(find.textContaining('≈ 8 meses'), findsOneWidget);
    expect(
      find.textContaining('Puedes dejar de pagar 3 semanas Mod40'),
      findsOneWidget,
    );
    expect(find.textContaining('Medio escalón'), findsNothing);
    expect(find.textContaining('completo desde'), findsNothing);

    // Sin desbordamientos (RenderFlex overflow / errores de layout).
    expect(tester.takeException(), isNull);
  });
}
