import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/utils/input_validator.dart';
import 'package:d_0_pension/core/utils/pension_constants.dart';
import 'package:d_0_pension/presentation/screens/captura_view.dart';
import 'package:d_0_pension/presentation/widgets/validation_indicator.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Validación VISUAL (widget test) de la Regla A / Ley 73 para nacimiento
/// 1999-01-30:
///
/// El usuario reportó "Sigo sin ver la validación de 19990130". Este test
/// reproduce lo que se ve en pantalla: escribe 19990130 en el campo "Fecha de
/// Nacimiento" de CapturaView y comprueba que el mensaje de Regla A se pinta
/// UNA sola vez, en ROJO (0xFFC62828) en el banner superior de errores (sin
/// duplicarse inline bajo el campo), y que el proveedor queda con error
/// bloqueante (la Regla A es un requisito: "la Ley 73 probablemente no
/// aplica", por lo que se detiene el cálculo).
///
/// IMPORTANTE (hallazgo empírico en validacion_cambios_recientes_test.dart):
/// un segundo flujo completo "buildProvider + pumpWidget(CapturaView)" en el
/// MISMO proceso de test se cuelga en pumpWidget. Por eso todas las
/// verificaciones de widgets van en UN solo testWidgets por archivo; los
/// test() puros sí pueden repetirse en el mismo proceso.
void main() {
  Future<RetroactiveProvider> _buildProvider() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final persistenceService = PersistenceService(prefs);
    final provider = RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: persistenceService,
    );
    await provider.initialize();
    return provider;
  }

  testWidgets(
      'Captura: fecha nacimiento 19990130 muestra el error de Regla A '
      '(Ley 73) en rojo UNA vez (banner superior) y BLOQUEA el cálculo',
      (WidgetTester tester) async {
    final provider = await _buildProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: CapturaView())),
      ),
    );
    await tester.pumpAndSettle();

    // Localizar el TextField de "Fecha de Nacimiento" dentro de su
    // ValidatedDateField (el label es un Text hermano del TextField).
    final labelFinder = find.text('Fecha de Nacimiento');
    expect(labelFinder, findsOneWidget,
        reason: 'El campo "Fecha de Nacimiento" debe existir en CapturaView.');

    final fieldFinder = find.descendant(
      of: find.ancestor(
        of: labelFinder,
        matching: find.byType(ValidatedDateField),
      ),
      matching: find.byType(TextField),
    );
    expect(fieldFinder, findsOneWidget,
        reason: 'Debe existir un único TextField en el ValidatedDateField.');

    // Escribir 19990130 (YYYYMMDD), exactamente como lo captura el usuario.
    await tester.enterText(fieldFinder, '19990130');
    await tester.pumpAndSettle();

    // 1) El mensaje de Regla A debe pintarse UNA sola vez, en el banner
    //    superior de errores (rojo 0xFFC62828) de la pestaña Captura.
    //    NO debe duplicarse inline bajo el campo (sin 0xFFF44336).
    final msgFinder =
        find.textContaining('posterior al 1 de julio de 1997');
    expect(msgFinder, findsOneWidget,
        reason: 'El mensaje de Regla A debe verse UNA sola vez en Captura: '
            'en el banner superior de errores.');

    // Regla A es BLOQUEANTE → NO debe aparecer en amarillo informativo.
    final yellowMsg = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data?.contains('posterior al 1 de julio de 1997') ?? false) &&
          w.style?.color == const Color(0xFFF9A825),
    );
    expect(yellowMsg, findsNothing,
        reason: 'El mensaje de Regla A NO debe pintarse en amarillo: '
            'ahora es un error bloqueante (rojo).');

    // - NO inline bajo el campo (evita duplicar el mensaje).
    final inlineRedMsg = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data?.contains('posterior al 1 de julio de 1997') ?? false) &&
          w.style?.color == const Color(0xFFF44336),
    );
    expect(inlineRedMsg, findsNothing,
        reason: 'El mensaje de Regla A NO debe duplicarse inline bajo el '
            'campo (0xFFF44336): solo se muestra en el banner superior.');

    // - en el área de errores en rojo 0xFFC62828.
    final bannerRedMsg = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data?.contains('posterior al 1 de julio de 1997') ?? false) &&
          w.style?.color == const Color(0xFFC62828),
    );
    expect(bannerRedMsg, findsOneWidget,
        reason: 'El mensaje de Regla A debe verse en rojo 0xFFC62828 '
            'en el banner superior de errores.');

    // 2) El provider debe registrar la Regla A como ERROR BLOQUEANTE
    //    (isValid=false, isWarning=false) con el mensaje canónico de no
    //    aplicabilidad de la Ley 73. No debe aparecer como warning.
    final reglaAError = provider.validacionesGlobales.any(
      (v) =>
          !v.isValid &&
          !v.isWarning &&
          v.message.contains(PensionConstants.warningLey73NoAplica),
    );
    expect(reglaAError, isTrue,
        reason: 'validacionesGlobales debe contener Regla A como error '
            'bloqueante.');

    final reglaAWarning = provider.validacionesGlobales.any(
      (v) =>
          v.isWarning &&
          v.isValid &&
          v.message.contains(PensionConstants.warningLey73NoAplica),
    );
    expect(reglaAWarning, isFalse,
        reason: 'Regla A NO debe registrarse como warning (ahora es error).');

    expect(provider.hasBlockingErrors, isTrue,
        reason: 'Regla A es bloqueante: el proveedor debe quedar con '
            'hasBlockingErrors=true para 1999-01-30.');
  });

  test('validateDate acepta 19990130 y Regla A dispara para 1999-01-30', () {
    // La base de formato valida "19990130" sin errores...
    expect(InputValidator.validateDate('19990130').isValid, isTrue);

    // ...pero la Regla A (aplicabilidad Ley 73) debe disparar porque
    // 1999-01-30 NO es anterior a 1997-07-01.
    expect(
      !DateTime(1999, 1, 30).isBefore(PensionConstants.fechaLimiteLey73),
      isTrue,
      reason: '1999-01-30 es posterior a 1997-07-01 → Regla A debe disparar.',
    );
  });
}
