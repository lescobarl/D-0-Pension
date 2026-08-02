import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:d_0_pension/core/theme/app_theme.dart';
import 'package:d_0_pension/presentation/widgets/info_row.dart';
import 'package:d_0_pension/presentation/widgets/legal_note_card.dart';
import 'package:d_0_pension/presentation/widgets/pension_card.dart';
import 'package:d_0_pension/presentation/widgets/result_row.dart';

import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Golden de la tarjeta principal de pensión con las cifras reales validadas
/// contra el Excel (paridad: Pensión Anual 1,050,486.20 / Mensual 87,540.52).
void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('pension card matches golden (pixel-perfect)', (tester) async {
    setGoldenSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.fromConfig(null),
        home: const Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PensionCard(
                  title: 'Pensión con Mod 40',
                  annualAmount: 1050486.2034887276,
                  monthlyAmount: 87540.51695739396,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(PensionCard),
      matchesGoldenFile('goldens/pension_card.png'),
    );
  });

  testWidgets('result/info rows and legal note match golden (pixel-perfect)',
      (tester) async {
    setGoldenSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.fromConfig(null),
        home: const Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResultRow(label: 'Salario diario', value: r'$2,914.93'),
                ResultRow(
                  label: 'Edad de retiro',
                  value: '60.51 años',
                  isBold: true,
                ),
                ResultRow(
                  label: 'Semanas cotizadas',
                  value: '2,094',
                  valueColor: AppTheme.successColor,
                ),
                Divider(height: 20),
                InfoRow(
                  label: 'Total cuantía básica anual',
                  value: r'$153,528.06',
                ),
                InfoRow(
                  label: 'Pensión mensual',
                  value: r'$87,540.52',
                  isBold: true,
                ),
                SizedBox(height: 12),
                LegalNoteCard(
                  note: 'Cifras de referencia validadas contra la '
                      'calculadora Excel Ley 73 del IMSS.',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/rows_and_notes.png'),
    );
  });
}
