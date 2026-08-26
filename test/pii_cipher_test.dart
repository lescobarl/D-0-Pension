import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/periodo_salarial.dart';
import 'package:d_0_pension/core/utils/pii_cipher.dart';
import 'package:d_0_pension/services/persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiiCipher', () {
    test('encode/decode round-trip for strings (incl. acentos)', () {
      const plain = 'texto sensible con acentos: José López';
      final encoded = PiiCipher.encode(plain);
      expect(encoded, isNot(plain));
      expect(PiiCipher.decode(encoded), plain);
    });

    test('encode/decode round-trip for doubles preserves exact precision', () {
      const values = [
        2914.9328685715745,
        1050486.2034887276,
        60.51,
        22.75,
        0.0,
        -3.25,
      ];
      for (final v in values) {
        final encoded = PiiCipher.encodeDouble(v);
        expect(encoded, isNot(v.toString()));
        expect(PiiCipher.decodeDouble(encoded), v);
      }
    });

    test('encode/decode round-trip for ints', () {
      for (final v in [0, 1, 1960, 2094, 2029]) {
        expect(PiiCipher.decodeInt(PiiCipher.encodeInt(v)), v);
      }
    });

    test('encode/decode round-trip for bools', () {
      expect(PiiCipher.decodeBool(PiiCipher.encodeBool(true)), isTrue);
      expect(PiiCipher.decodeBool(PiiCipher.encodeBool(false)), isFalse);
    });

    test('obfuscated output is not readable plaintext', () {
      final encoded = PiiCipher.encode('1960');
      expect(encoded, isNot('1960'));
      expect(encoded, isNot(contains('1960')));
    });
  });

  group('PersistenceService PII (v13 obfuscated storage)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<PersistenceService> newService() async {
      final prefs = await SharedPreferences.getInstance();
      return PersistenceService(prefs);
    }

    test('salario diario round-trips and is stored obfuscated', () async {
      final service = await newService();
      await service.saveSalarioDiario(2914.9328685715745);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.get('salario_diario');
      expect(stored, isA<String>());
      expect(stored, isNot('2914.9328685715745'));

      expect(service.loadSalarioDiario(defaultValue: 0), 2914.9328685715745);
    });

    test('fecha de nacimiento round-trips obfuscated', () async {
      final service = await newService();
      await service.saveFechaNacimiento(DateTime(1968, 5, 12));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get('fecha_nacimiento_year'), isA<String>());
      expect(prefs.get('fecha_nacimiento_year'), isNot('1968'));

      expect(
        service.loadFechaNacimiento(defaultValue: DateTime(2000)),
        DateTime(1968, 5, 12),
      );
    });

    test('fecha de cálculo round-trips obfuscated', () async {
      final service = await newService();
      await service.saveFechaCalculo(DateTime(2029, 7, 15));
      expect(
        service.loadFechaCalculo(defaultValue: DateTime(2000)),
        DateTime(2029, 7, 15),
      );
    });

    test('start/end dates round-trip obfuscated', () async {
      final service = await newService();
      await service.saveStartDate(DateTime(1990, 1, 1));
      await service.saveEndDate(DateTime(2029, 12, 31));

      expect(
        service.loadStartDate(defaultValue: DateTime(2000)),
        DateTime(1990, 1, 1),
      );
      expect(
        service.loadEndDate(defaultValue: DateTime(2000)),
        DateTime(2029, 12, 31),
      );
    });

    test('salario promedio 250 semanas round-trips obfuscated', () async {
      final service = await newService();
      await service.saveSalarioPromedio250Semanas(2281.5311428572486);
      expect(
        service.loadSalarioPromedio250Semanas(defaultValue: 0),
        2281.5311428572486,
      );
    });

    test('family fields round-trip obfuscated', () async {
      final service = await newService();
      await service.saveTieneEsposa(true);
      await service.saveNumeroHijos(2);
      await service.saveNumeroPadres(0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get('tiene_esposa'), isA<String>());

      expect(service.loadTieneEsposa(defaultValue: false), isTrue);
      expect(service.loadNumeroHijos(defaultValue: 0), 2);
      expect(service.loadNumeroPadres(defaultValue: 0), 0);
    });

    test('periodos round-trip obfuscated (JSON not stored in plain)', () async {
      final service = await newService();
      final periodos = [
        PeriodoSalarial(
          fechaInicio: DateTime(2020, 1, 1),
          fechaTermino: DateTime(2020, 12, 31),
          salarioDiario: 1500.5,
          semanas: 52,
          esMod40: true,
        ),
        PeriodoSalarial(
          fechaInicio: DateTime(2021, 1, 1),
          fechaTermino: DateTime(2021, 12, 31),
          salarioDiario: 1600.25,
          semanas: 51,
          esMod40: false,
        ),
      ];
      await service.savePeriodos(periodos);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.get('periodos_salariales');
      expect(stored, isA<String>());
      expect(
        (stored as String).startsWith('['),
        isFalse,
        reason: 'el JSON plano no debe quedar en claro',
      );

      final loaded = service.loadPeriodos();
      expect(loaded.length, 2);
      expect(loaded[0].salarioDiario, 1500.5);
      expect(loaded[0].esMod40, isTrue);
      expect(loaded[1].salarioDiario, 1600.25);
      expect(loaded[1].esMod40, isFalse);
    });

    test(
      'stale saved data is invalidated on version bump (auto-reset)',
      () async {
        SharedPreferences.setMockInitialValues({
          'data_version': 12,
          'salario_diario': 2500.0,
          'fecha_nacimiento_year': 1970,
          'fecha_nacimiento_month': 3,
          'fecha_nacimiento_day': 9,
          'tiene_esposa': true,
          'numero_hijos': 2,
          'semanas_cotizadas': 2090,
          'periodos_salariales':
              '[{"fechaInicio":null,"fechaTermino":null,'
              '"salarioDiario":1800.0,"semanas":52,"esMod40":false}]',
        });

        final service = await newService();
        final prefs = await SharedPreferences.getInstance();

        // Versión bump a la versión actual: overrides obsoletos invalidados.
        expect(prefs.getInt('data_version'), PersistenceService.dataVersion);
        expect(prefs.containsKey('salario_diario'), isFalse);
        expect(prefs.containsKey('fecha_nacimiento_year'), isFalse);
        expect(prefs.containsKey('semanas_cotizadas'), isFalse);
        expect(prefs.containsKey('periodos_salariales'), isFalse);

        // Los valores guardados ya NO ganan: los defaults toman efecto.
        expect(service.loadSalarioDiario(defaultValue: 0), 0);
        expect(
          service.loadFechaNacimiento(defaultValue: DateTime(2000)),
          DateTime(2000),
        );
        expect(service.loadTieneEsposa(defaultValue: false), isFalse);
        expect(service.loadNumeroHijos(defaultValue: 0), 0);
        expect(service.loadSemanasCotizadas(defaultValue: 1960), 1960);
        expect(service.loadPeriodos(), isEmpty);
      },
    );

    test('hasAnyData detects partial data (no single-key sentinel)', () async {
      // Sin datos persistidos: false.
      final empty = await newService();
      expect(empty.hasAnyData(), isFalse);

      // Un solo campo numérico basta para detectar datos parciales.
      SharedPreferences.setMockInitialValues({
        'data_version': PersistenceService.dataVersion,
        'numero_hijos': PiiCipher.encodeInt(2),
      });
      final prefs = await SharedPreferences.getInstance();
      final partial = PersistenceService(prefs);
      expect(
        partial.hasAnyData(),
        isTrue,
        reason: 'con datos parciales (solo numero_hijos) debe detectarse',
      );

      // Un solo campo booleano también cuenta.
      SharedPreferences.setMockInitialValues({
        'data_version': PersistenceService.dataVersion,
        'tiene_esposa': PiiCipher.encodeBool(true),
      });
      final prefs2 = await SharedPreferences.getInstance();
      final partial2 = PersistenceService(prefs2);
      expect(partial2.hasAnyData(), isTrue);
    });

    test(
      'corrupt obfuscated value self-heals: removed and default returned',
      () async {
        SharedPreferences.setMockInitialValues({
          'data_version': PersistenceService.dataVersion,
          'salario_diario': '!!not-a-valid-obfuscated-value!!',
          'tiene_esposa': '!!!corrupt-bool!!!',
        });
        final service = await newService();
        final prefs = await SharedPreferences.getInstance();

        // La lectura devuelve el default y auto-sanitiza el valor corrupto.
        expect(service.loadSalarioDiario(defaultValue: 100.0), 100.0);
        expect(
          prefs.containsKey('salario_diario'),
          isFalse,
          reason: 'el valor corrupto debe eliminarse al auto-sanitizar',
        );

        expect(service.loadTieneEsposa(defaultValue: true), isTrue);
        expect(prefs.containsKey('tiene_esposa'), isFalse);
      },
    );
  });
}
