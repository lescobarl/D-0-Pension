import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/utils/input_validator.dart';
import 'package:d_0_pension/core/utils/pension_constants.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Pruebas unitarias de elegibilidad legal de pensión (Ley del Seguro Social
/// 1973):
/// - Mínimo 500 semanas cotizadas (Art. 154/162 LSS 1973).
/// - Edad de retiro alcanzada (Cesantía en Edad Avanzada: 60 años Art. 154;
///   Vejez al 100%: 65 años Art. 162).
///
/// Incluye el caso real del usuario: 59.51 años de edad, que aún NO permite
/// pensión (debe cumplir 60).
///
/// Run with: flutter test test/unit/pension_eligibility_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ley 73 - Constantes legales', () {
    test('Mínimo de 500 semanas cotizadas (Art. 154/162 LSS 1973)', () {
      expect(PensionConstants.minSemanasLey73, 500);
    });

    test('Edad mínima de 60 años para Cesantía en Edad Avanzada (Art. 154)',
        () {
      expect(PensionConstants.minEdadPensionLey73, 60);
    });

    test('Edad de 65 años para Vejez al 100% (Art. 162)', () {
      expect(PensionConstants.edadVejezLey73, 65);
    });
  });

  group('calcularEdadActual', () {
    test('Edad exacta de 60 años', () {
      final edad = InputValidator.calcularEdadActual(
        DateTime(1965, 5, 15),
        DateTime(2025, 5, 15),
      );
      expect(edad, closeTo(60.0, 0.05));
    });

    test('Caso usuario: 59.51 años (aún NO alcanza 60)', () {
      final edad = InputValidator.calcularEdadActual(
        DateTime(1966, 5, 15),
        DateTime(2025, 11, 18),
      );
      expect(edad, closeTo(59.51, 0.02));
      expect(edad < 60.0, true,
          reason: 'El usuario con 59.51 años debe quedar por debajo de 60');
    });

    test('fechaCalculo anterior a nacimiento retorna 0', () {
      final edad = InputValidator.calcularEdadActual(
        DateTime(2000, 1, 1),
        DateTime(1999, 1, 1),
      );
      expect(edad, 0);
    });
  });

  group('validateMinSemanasLey73', () {
    test('Menos de 500 semanas genera warning', () {
      final r = InputValidator.validateMinSemanasLey73(499);
      expect(r.isWarning, true);
      expect(r.isValid, true); // warning permite captura, pero alerta
      expect(r.message, contains('500'));
    });

    test('Exactamente 500 semanas es válido', () {
      final r = InputValidator.validateMinSemanasLey73(500);
      expect(r.isValid, true);
      expect(r.isWarning, false);
    });

    test('Más de 500 semanas es válido', () {
      final r = InputValidator.validateMinSemanasLey73(800);
      expect(r.isValid, true);
      expect(r.isWarning, false);
    });
  });

  group('RetroactiveProvider - Elegibilidad (Ley 73)', () {
    late FormulaEvaluator evaluator;
    late RetroactiveProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      evaluator = FormulaEvaluator();
      await evaluator.initialize();
      provider = RetroactiveProvider(
        persistence: PersistenceService(prefs),
        evaluator: evaluator,
      );
      await provider.initialize();
    });

    /// Los defaults de metadata siembran periodos baseline (134 semanas en
    /// Mod40) y `_recalculatePromedioFromPeriodos` re-deriva `semanasEnMod40`
    /// desde esos periodos. Se limpia la lista con `setPeriodos([])` para que
    /// el total cotizado sea exactamente `semanasAntesMod40`.
    test('Caso usuario (59.51 años, edad retiro 60, 400 semanas) NO aplica',
        () async {
      provider.setFechaNacimiento(DateTime(1966, 5, 15));
      provider.setFechaCalculo(DateTime(2025, 11, 18));
      await provider.setEdadRetiro(60);
      provider.setPeriodos([]);
      provider.setSemanasAntesMod40(400);

      expect(provider.edadActual, closeTo(59.51, 0.02));
      expect(provider.totalSemanasCotizadas, 400);
      expect(provider.cumpleMinimoSemanas, false);
      expect(provider.cumpleEdadRetiro, false);
      expect(provider.esPensionAplicable, false);
      expect(provider.requisitosPensionFaltantes.length, 2);
    });

    test('500 semanas pero 59.51 años: aún NO aplica (falta la edad)',
        () async {
      provider.setFechaNacimiento(DateTime(1966, 5, 15));
      provider.setFechaCalculo(DateTime(2025, 11, 18));
      await provider.setEdadRetiro(60);
      provider.setPeriodos([]);
      provider.setSemanasAntesMod40(500);

      expect(provider.totalSemanasCotizadas, 500);
      expect(provider.cumpleMinimoSemanas, true);
      expect(provider.cumpleEdadRetiro, false);
      expect(provider.esPensionAplicable, false);
      expect(provider.requisitosPensionFaltantes.length, 1);
    });

    test('60 años cumplidos + 500 semanas: la pensión SÍ aplica', () async {
      provider.setFechaNacimiento(DateTime(1965, 5, 15));
      provider.setFechaCalculo(DateTime(2025, 5, 15));
      await provider.setEdadRetiro(60);
      provider.setPeriodos([]);
      provider.setSemanasAntesMod40(500);

      expect(provider.totalSemanasCotizadas, 500);
      expect(provider.cumpleMinimoSemanas, true);
      expect(provider.cumpleEdadRetiro, true);
      expect(provider.esPensionAplicable, true);
      expect(provider.requisitosPensionFaltantes, isEmpty);
    });
  });
}
