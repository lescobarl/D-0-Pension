import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/periodo_salarial.dart';
import 'package:d_0_pension/core/utils/pii_cipher.dart';
import 'package:d_0_pension/services/billing/login_provider.dart';
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
      expect((stored as String).startsWith('['), isFalse,
          reason: 'el JSON plano no debe quedar en claro');

      final loaded = service.loadPeriodos();
      expect(loaded.length, 2);
      expect(loaded[0].salarioDiario, 1500.5);
      expect(loaded[0].esMod40, isTrue);
      expect(loaded[1].salarioDiario, 1600.25);
      expect(loaded[1].esMod40, isFalse);
    });

    test('v12 legacy plaintext migrates to obfuscated without data loss',
        () async {
      SharedPreferences.setMockInitialValues({
        'data_version': 12,
        'salario_diario': 2500.0,
        'fecha_nacimiento_year': 1970,
        'fecha_nacimiento_month': 3,
        'fecha_nacimiento_day': 9,
        'tiene_esposa': true,
        'numero_hijos': 2,
        'periodos_salariales':
            '[{"fechaInicio":null,"fechaTermino":null,'
            '"salarioDiario":1800.0,"semanas":52,"esMod40":false}]',
      });

      final service = await newService();
      final prefs = await SharedPreferences.getInstance();

      // Version bumped and PII re-written obfuscated.
      expect(prefs.getInt('data_version'), 13);
      expect(prefs.get('salario_diario'), isA<String>());
      expect(prefs.get('salario_diario'), isNot(2500.0));
      expect(prefs.get('fecha_nacimiento_year'), isA<String>());
      expect(prefs.get('periodos_salariales').toString().startsWith('['), isFalse);

      // No data loss after migration.
      expect(service.loadSalarioDiario(defaultValue: 0), 2500.0);
      expect(
        service.loadFechaNacimiento(defaultValue: DateTime(2000)),
        DateTime(1970, 3, 9),
      );
      expect(service.loadTieneEsposa(defaultValue: false), isTrue);
      expect(service.loadNumeroHijos(defaultValue: 0), 2);
      final loaded = service.loadPeriodos();
      expect(loaded.length, 1);
      expect(loaded[0].salarioDiario, 1800.0);
    });
  });

  group('LoginProvider (email PII at rest)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('email is stored obfuscated and restored on initialize()', () async {
      final prefs = await SharedPreferences.getInstance();
      final provider = LoginProvider(prefs);
      final ok = await provider.signIn(
        email: 'usuario.ejemplo@correo.com',
        password: 'secreto123',
      );
      expect(ok, isTrue);

      // No se guarda el email en claro.
      final stored = prefs.get('user_email');
      expect(stored, isA<String>());
      expect(stored, isNot('usuario.ejemplo@correo.com'));
      expect((stored as String).contains('@'), isFalse,
          reason: 'el email no debe quedar legible en el almacenamiento');

      // Un provider nuevo (p. ej. reinicio de app) restaura la sesión.
      final restored = LoginProvider(prefs);
      restored.initialize();
      expect(restored.isLoggedIn, isTrue);
      expect(restored.userEmail, 'usuario.ejemplo@correo.com');
    });

    test('legacy plaintext email is still readable after initialize()', () async {
      // Simula datos guardados por una versión anterior (email en claro).
      SharedPreferences.setMockInitialValues({
        'user_logged_in': true,
        'user_email': 'antiguo@correo.com',
      });
      final prefs = await SharedPreferences.getInstance();
      final restored = LoginProvider(prefs);
      restored.initialize();
      expect(restored.isLoggedIn, isTrue);
      expect(restored.userEmail, 'antiguo@correo.com');
    });
  });
}
