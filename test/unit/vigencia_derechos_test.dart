import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/utils/pension_constants.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

/// Pruebas unitarias de VIGENCIA / CONSERVACIÓN DE DERECHOS
/// (Art. 150 LSS 1973):
///
/// El asegurado que deja de cotizar conserva sus derechos por la CUARTA PARTE
/// del tiempo cotizado (mínimo 12 meses), contado desde la fecha de baja
/// (última cotización). Si la fecha de cálculo de la pensión supera esa fecha
/// límite, el derecho a la pensión se pierde (debe reincorporar la cotización
/// antes del límite).
///
/// IMPORTANTE: la app es una herramienta de PROYECCIÓN, por lo que esta regla
/// se evalúa como ADVERTENCIA (no bloquea el cálculo). Solo se evalúa cuando
/// el usuario captura su fecha de última cotización/baja.
///
/// Incluye el caso real del usuario (1960 semanas, baja 2027-02-01, cálculo
/// ~2029): el límite queda en ~2036, por lo que NO debe aparecer la advertencia.
///
/// Run with: flutter test test/unit/vigencia_derechos_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ley 73 - Constantes de vigencia de derechos (Art. 150)', () {
    test(
      'La conservación de derechos es la cuarta parte del tiempo cotizado',
      () {
        expect(PensionConstants.fraccionConservacionDerechos, 0.25);
      },
    );

    test('Piso legal de 12 meses de conservación (Art. 150)', () {
      expect(PensionConstants.minMesesConservacionDerechos, 12);
    });

    test('52 semanas por año para convertir semanas cotizadas a años', () {
      expect(PensionConstants.semanasPorAnio, 52.0);
    });

    test('Existe el mensaje de advertencia de vigencia excedida', () {
      expect(
        PensionConstants.warningVigenciaDerechosExcedida,
        contains('Art. 150'),
      );
    });
  });

  group('RetroactiveProvider - Vigencia de derechos (Art. 150)', () {
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

    /// Configura un escenario limpio: sin desglose (para que el total cotizado
    /// sea exactamente [semanas]) con las fechas dadas.
    Future<void> configurarEscenario({
      required double semanas,
      required DateTime fechaCalculo,
      DateTime? fechaUltimaCotizacion,
    }) async {
      provider.setFechaNacimiento(DateTime(1966, 5, 15));
      provider.setFechaCalculo(fechaCalculo);
      await provider.setEdadRetiro(60);
      provider.setPeriodos([]);
      provider.setSemanasAntesMod40(semanas);
      if (fechaUltimaCotizacion != null) {
        provider.setFechaUltimaCotizacion(fechaUltimaCotizacion);
      }
    }

    List<String> advertenciasArt150() => provider.validacionesGlobales
        .where((v) => v.isWarning && v.message.contains('Art. 150'))
        .map((v) => v.message)
        .toList();

    test(
      'Sin fecha de última cotización: la regla no se evalúa (sin warning)',
      () async {
        await configurarEscenario(
          semanas: 1960,
          fechaCalculo: DateTime(2029, 1, 1),
        );

        expect(provider.fechaUltimaCotizacion, isNull);
        expect(provider.fechaLimiteConservacionDerechos, isNull);
        expect(provider.vigenciaDerechosExcedida, false);
        expect(advertenciasArt150(), isEmpty);
      },
    );

    test('Caso usuario (1960 semanas, baja 2027-02-01, cálculo 2029): '
        'límite ~2036 y NO hay advertencia', () async {
      await configurarEscenario(
        semanas: 1960,
        fechaCalculo: DateTime(2029, 1, 1),
        fechaUltimaCotizacion: DateTime(2027, 2, 1),
      );

      expect(provider.totalSemanasCotizadas, 1960);
      // 1960/52 = 37.69 años cotizados; ¼ ≈ 9.42 años → límite ≈ 2036.
      final limite = provider.fechaLimiteConservacionDerechos!;
      expect(limite.year, greaterThanOrEqualTo(2036));
      // La fecha de cálculo (2029) es ANTERIOR al límite → sin advertencia.
      expect(provider.vigenciaDerechosExcedida, false);
      expect(advertenciasArt150(), isEmpty);
      // La regla agrega un resultado válido, nunca bloquea la proyección.
      expect(provider.hasBlockingErrors, false);
    });

    test('Piso legal de 12 meses: con pocas semanas la ventana se amplía a '
        '1 año desde la baja', () async {
      // 100 semanas → ¼ = 0.48 años, pero el piso legal (Art. 150) la amplía
      // a 12 meses completos: límite ≈ 2027-02-01 + 12 meses = 2028-02-01.
      await configurarEscenario(
        semanas: 100,
        fechaCalculo: DateTime(2028, 6, 1),
        fechaUltimaCotizacion: DateTime(2027, 2, 1),
      );

      final limite = provider.fechaLimiteConservacionDerechos!;
      expect(
        limite.year,
        2028,
        reason:
            'El piso de 12 meses debe llevar el límite a 2028, '
            'no a ~2027-07 (que sería la cuarta parte sin piso)',
      );
      // Cálculo 2028-06-01 es posterior al límite 2028-02-01 → advertencia.
      expect(provider.vigenciaDerechosExcedida, true);
      expect(advertenciasArt150(), hasLength(1));
    });

    test('Vigencia excedida (1960 semanas, cálculo 2040): se produce la '
        'advertencia informativa (no bloquea)', () async {
      await configurarEscenario(
        semanas: 1960,
        fechaCalculo: DateTime(2040, 1, 1),
        fechaUltimaCotizacion: DateTime(2027, 2, 1),
      );

      expect(provider.vigenciaDerechosExcedida, true);
      final avisos = advertenciasArt150();
      expect(avisos, hasLength(1));
      expect(avisos.first, contains('límite'));
      expect(avisos.first, contains('2027-02-01')); // fecha de baja
      // Es una ADVERTENCIA: no bloquea la proyección.
      expect(provider.hasBlockingErrors, false);
    });

    test('La fecha de cálculo exactamente en el límite NO se considera '
        'excedida', () async {
      // baja 2027-02-01 + 12 meses (piso) = 2028-02-01.
      await configurarEscenario(
        semanas: 100,
        fechaCalculo: DateTime(2028, 2, 1),
        fechaUltimaCotizacion: DateTime(2027, 2, 1),
      );

      // isAfter es estricto: en el límite exacto no hay advertencia.
      expect(provider.vigenciaDerechosExcedida, false);
      expect(advertenciasArt150(), isEmpty);
    });

    test(
      'setFechaUltimaCotizacion: setter con notificación y borrado con null',
      () async {
        var notified = 0;
        provider.addListener(() => notified++);

        provider.setFechaUltimaCotizacion(DateTime(2027, 2, 1));
        expect(provider.fechaUltimaCotizacion, DateTime(2027, 2, 1));
        expect(provider.fechaLimiteConservacionDerechos, isNotNull);
        expect(notified, 1);

        // Mismo valor → no notifica.
        provider.setFechaUltimaCotizacion(DateTime(2027, 2, 1));
        expect(notified, 1);

        // null borra el valor y la regla deja de evaluarse.
        provider.setFechaUltimaCotizacion(null);
        expect(provider.fechaUltimaCotizacion, isNull);
        expect(provider.fechaLimiteConservacionDerechos, isNull);
        expect(provider.vigenciaDerechosExcedida, false);
        expect(notified, 2);
      },
    );

    test(
      'Persistencia: la fecha de última cotización se guarda y se recarga',
      () async {
        // El setter dispara un guardado asíncrono fire-and-forget (igual que
        // setFechaAlta); para validar el round-trip hay que esperar la
        // escritura real antes de recargar.
        provider.setFechaUltimaCotizacion(DateTime(2027, 2, 1));
        await provider.persistence.saveFechaUltimaCotizacion(
          DateTime(2027, 2, 1),
        );

        // Re-crear el provider con el mismo almacén simulado.
        final prefs = await SharedPreferences.getInstance();
        final provider2 = RetroactiveProvider(
          persistence: PersistenceService(prefs),
          evaluator: evaluator,
        );
        await provider2.initialize();

        expect(provider2.fechaUltimaCotizacion, DateTime(2027, 2, 1));
        expect(
          provider2.fechaLimiteConservacionDerechos,
          isNotNull,
          reason: 'Al recargar la fecha de baja el límite debe recalcularse',
        );
      },
    );

    test('Persistencia: guardar null borra la fecha recargada', () async {
      provider.setFechaUltimaCotizacion(DateTime(2027, 2, 1));
      await provider.persistence.saveFechaUltimaCotizacion(
        DateTime(2027, 2, 1),
      );

      provider.setFechaUltimaCotizacion(null);
      await provider.persistence.saveFechaUltimaCotizacion(null);

      final prefs = await SharedPreferences.getInstance();
      final provider2 = RetroactiveProvider(
        persistence: PersistenceService(prefs),
        evaluator: evaluator,
      );
      await provider2.initialize();

      expect(provider2.fechaUltimaCotizacion, isNull);
      expect(provider2.fechaLimiteConservacionDerechos, isNull);
    });
  });
}
