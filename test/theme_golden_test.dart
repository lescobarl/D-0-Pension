import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:d_0_pension/core/theme/app_theme.dart';
import 'package:d_0_pension/presentation/widgets/info_row.dart';
import 'package:d_0_pension/presentation/widgets/legal_note_card.dart';
import 'package:d_0_pension/presentation/widgets/result_row.dart';

import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Vitrina de la identidad visual (AppTheme por defecto): AppBar, TabBar,
/// botón, filas de resultado/info y nota legal. Golden de regresión visual del
/// tema completo (paleta verde petróleo / dorado).
class _ThemeShowcase extends StatelessWidget {
  const _ThemeShowcase();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calculadora Ley 73 IMSS'),
          actions: const [
            IconButton(
              tooltip: 'Descargo de Responsabilidad',
              onPressed: _noop,
              icon: Icon(Icons.info_outline, size: 20),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: AppTheme.primary,
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Captura'),
                    Tab(text: 'Pensión'),
                    Tab(text: 'Inversión'),
                    Tab(text: 'IA Experta'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const ElevatedButton(
                onPressed: _noop,
                child: Text('Calcular pensión'),
              ),
              const SizedBox(height: 16),
              const ResultRow(label: 'Salario diario', value: r'$2,914.93'),
              const ResultRow(
                label: 'Edad de retiro',
                value: '60.51 años',
                isBold: true,
              ),
              const ResultRow(
                label: 'Pensión mensual',
                value: r'$87,540.52',
                valueColor: AppTheme.successColor,
              ),
              const Divider(height: 24),
              const InfoRow(label: 'Semanas cotizadas', value: '2,094'),
              const InfoRow(
                label: 'Total cuantía básica anual',
                value: r'$153,528.06',
                isBold: true,
              ),
              const SizedBox(height: 16),
              const LegalNoteCard(
                note: 'Resultados estimados con base en la Ley 73 del IMSS. '
                    'Esta herramienta no constituye asesoría financiera.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _noop() {}

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('theme showcase matches golden (pixel-perfect)', (tester) async {
    setGoldenSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.fromConfig(null),
        home: const _ThemeShowcase(),
      ),
    );

    await expectLater(
      find.byType(_ThemeShowcase),
      matchesGoldenFile('goldens/theme_showcase.png'),
    );
  });
}
