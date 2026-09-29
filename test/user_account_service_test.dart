import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/user_profile.dart';
import 'package:d_0_pension/services/account/pending_registration.dart';
import 'package:d_0_pension/services/account/user_account_service.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

/// Tests unitarios de la capa de cuentas locales ([UserAccountService]).
///
/// Cubre el ciclo completo de la cuenta: login (ok / no existe / contraseña
/// incorrecta), sesión (recordarme), sincronización de licencia cuenta↔
/// dispositivo, creación de cuenta con licencia comprada, creación con licencia
/// de dispositivo, renovación, vinculación y cierre de sesión (la licencia de
/// la CUENTA se conserva; el dispositivo la limpia la UI).
void main() {
  Future<({PaymentProvider payments, UserAccountService accounts})>
  buildService({Map<String, Object> seed = const {}}) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    final payments = PaymentProvider(PlayBillingService(), prefs);
    final accounts = UserAccountService(prefs, payments: payments);
    return (payments: payments, accounts: accounts);
  }

  PendingRegistration pendingFor(
    String username, {
    String password = 'pass1234',
  }) => PendingRegistration.create(username: username, password: password);

  UserProfile bareUser(String username, {String password = 'pass1234'}) {
    final pending = pendingFor(username, password: password);
    return UserProfile(
      id: 'u_$username',
      username: username,
      salt: pending.salt,
      passwordHash: pending.passwordHash,
      createdAt: DateTime.now(),
    );
  }

  group('normalización y búsqueda', () {
    test('normalize: trim + minúsculas', () {
      expect(UserAccountService.normalize('  Juan  '), 'juan');
      expect(UserAccountService.normalize('LESCOBAR69'), 'lescobar69');
      expect(UserAccountService.normalize('Ana'), 'ana');
    });

    test('usernameExists / findByUsername son case-insensitive', () async {
      final (:accounts, :payments) = await buildService();
      await accounts.createAccountWithLicense(
        pending: pendingFor('Ana'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      expect(accounts.usernameExists('ANA'), isTrue);
      expect(accounts.usernameExists('  ana '), isTrue);
      expect(accounts.findByUsername('ANA'), isNotNull);
      expect(accounts.findByUsername('otro'), isNull);
      expect(payments.hasValidLicense, isTrue);
    });
  });

  group('loginUser', () {
    test('notFound para un usuario inexistente', () async {
      final (:accounts, :payments) = await buildService();
      final result = await accounts.loginUser('ghost', 'pass1234');
      expect(result, AccountLoginResult.notFound);
      expect(accounts.isLoggedIn, isFalse);
      expect(accounts.currentUser, isNull);
      expect(payments.hasValidLicense, isFalse);
    });

    test('wrongPassword con contraseña incorrecta', () async {
      final (:accounts, :payments) = await buildService();
      await accounts.createAccountWithLicense(
        pending: pendingFor('maria'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      final result = await accounts.loginUser('maria', 'incorrecta');
      expect(result, AccountLoginResult.wrongPassword);
      expect(accounts.isLoggedIn, isFalse);
      expect(
        payments.hasValidLicense,
        isTrue,
        reason: 'la licencia de la cuenta se aplicó al crearla',
      );
    });

    test(
      'ok con credenciales correctas (sesión + licencia al dispositivo)',
      () async {
        final (:accounts, :payments) = await buildService();
        await accounts.createAccountWithLicense(
          pending: pendingFor('juan'),
          licenseExpiry: null,
          productId: kProductIdPerpetual,
        );
        final result = await accounts.loginUser('juan', 'pass1234');
        expect(result, AccountLoginResult.ok);
        expect(accounts.isLoggedIn, isTrue);
        expect(accounts.currentSessionUsername, 'juan');
        expect(accounts.rememberMe, isTrue);
        expect(payments.hasValidLicense, isTrue);
        expect(payments.licenseProductId, kProductIdPerpetual);
      },
    );
  });

  group('openSession', () {
    test('sincroniza la licencia de la cuenta al dispositivo', () async {
      final (:accounts, :payments) = await buildService();
      final expiry = DateTime.now().add(const Duration(days: 180));
      final user = await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: expiry,
        productId: kProductIdSemestral,
      );

      // Simula otro contexto: dispositivo sin licencia.
      await payments.logout();
      expect(payments.hasValidLicense, isFalse);

      await accounts.openSession(user!);
      expect(payments.hasValidLicense, isTrue);
      expect(payments.licenseProductId, kProductIdSemestral);
      expect(payments.licenseExpiry, isNotNull);
    });

    test(
      'vincula la licencia de dispositivo a una cuenta sin licencia',
      () async {
        final (:accounts, :payments) = await buildService();
        await payments.applyLicense(
          expiry: null,
          productId: kProductIdPerpetual,
        );

        final user = bareUser('luis');
        expect(user.purchasedProductId, isNull);

        await accounts.openSession(user);
        final linked = accounts.findByUsername('luis')!;
        expect(linked.purchasedProductId, kProductIdPerpetual);
        expect(linked.isLicenseValid, isTrue);
        expect(accounts.isLoggedIn, isTrue);
      },
    );
  });

  group('createAccountWithLicense', () {
    test('crea cuenta con licencia y la refleja en el dispositivo', () async {
      final (:accounts, :payments) = await buildService();
      final expiry = DateTime.now().add(const Duration(days: 180));
      final user = await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: expiry,
        productId: kProductIdSemestral,
      );

      expect(user, isNotNull);
      expect(accounts.usernameExists('luis'), isTrue);
      expect(user!.isLicenseValid, isTrue);
      expect(user.purchasedProductId, kProductIdSemestral);
      // La contraseña NUNCA se guarda en claro.
      expect(user.verifyPassword('pass1234'), isTrue);
      expect(user.passwordHash, isNot('pass1234'));
      expect(payments.hasValidLicense, isTrue);
      expect(payments.licenseProductId, kProductIdSemestral);
      expect(payments.licenseExpiry, isNotNull);
    });

    test('licencia perpetua: sin vencimiento y válida', () async {
      final (:accounts, :payments) = await buildService();
      final user = await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      expect(user!.isLicenseValid, isTrue);
      expect(user.licenseExpiry, isNull);
      expect(payments.hasValidLicense, isTrue);
      expect(payments.licenseExpiry, isNull);
    });

    test('null si el usuario ya existe (no duplica)', () async {
      final (:accounts, :payments) = await buildService();
      await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      final dup = await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      expect(dup, isNull);
      expect(accounts.allAccounts.length, 1);
    });
  });

  group('createAccountWithDeviceLicense', () {
    test('reutiliza la licencia de dispositivo vigente', () async {
      final (:accounts, :payments) = await buildService();
      await payments.applyLicense(expiry: null, productId: kProductIdPerpetual);

      final user = await accounts.createAccountWithDeviceLicense(
        pending: pendingFor('luis'),
      );
      expect(user, isNotNull);
      expect(user!.purchasedProductId, kProductIdPerpetual);
      expect(user.isLicenseValid, isTrue);
    });

    test('null sin licencia de dispositivo válida', () async {
      final (:accounts, :payments) = await buildService();
      final user = await accounts.createAccountWithDeviceLicense(
        pending: pendingFor('luis'),
      );
      expect(user, isNull);
      expect(accounts.usernameExists('luis'), isFalse);
      expect(payments.hasValidLicense, isFalse);
    });

    test('null si el usuario ya existe', () async {
      final (:accounts, :payments) = await buildService();
      await payments.applyLicense(expiry: null, productId: kProductIdPerpetual);
      await accounts.createAccountWithDeviceLicense(
        pending: pendingFor('luis'),
      );

      final dup = await accounts.createAccountWithDeviceLicense(
        pending: pendingFor('luis'),
      );
      expect(dup, isNull);
      expect(accounts.allAccounts.length, 1);
    });
  });

  group('renewLicenseForUser', () {
    test('renueva vencimiento y producto de la cuenta', () async {
      final (:accounts, :payments) = await buildService();
      await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: DateTime.now().subtract(const Duration(days: 1)),
        productId: kProductIdAnnual,
      );
      final expired = accounts.findByUsername('luis')!;
      expect(expired.isLicenseValid, isFalse);

      final newExpiry = DateTime.now().add(const Duration(days: 365));
      final renewed = await accounts.renewLicenseForUser(
        expired,
        licenseExpiry: newExpiry,
        productId: kProductIdAnnual,
      );
      expect(renewed, isTrue);
      final after = accounts.findByUsername('luis')!;
      expect(after.isLicenseValid, isTrue);
      expect(payments.licenseExpiry, isNotNull);
      expect(payments.licenseProductId, kProductIdAnnual);
    });
  });

  group('linkDeviceLicenseToUser', () {
    test('vincula la licencia del dispositivo a la cuenta', () async {
      final (:accounts, :payments) = await buildService();
      await payments.applyLicense(expiry: null, productId: kProductIdPerpetual);

      final user = bareUser('luis');
      expect(user.purchasedProductId, isNull);

      await accounts.linkDeviceLicenseToUser(user);
      final linked = accounts.findByUsername('luis')!;
      expect(linked.purchasedProductId, kProductIdPerpetual);
      expect(linked.isLicenseValid, isTrue);
    });

    test('no hace nada sin licencia de dispositivo', () async {
      final (:accounts, :payments) = await buildService();
      final user = bareUser('luis');
      await accounts.linkDeviceLicenseToUser(user);
      expect(
        accounts.findByUsername('luis'),
        isNull,
        reason: 'sin licencia de dispositivo no debe materializar la cuenta',
      );
    });
  });

  group('logoutUser', () {
    test('cierra la sesión pero conserva la licencia de la cuenta', () async {
      final (:accounts, :payments) = await buildService();
      await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      await accounts.openSession(accounts.findByUsername('luis')!);
      expect(accounts.isLoggedIn, isTrue);

      await accounts.logoutUser();
      expect(accounts.isLoggedIn, isFalse);
      expect(accounts.currentSessionUsername, isNull);
      // La cuenta y su licencia persisten.
      final stored = accounts.findByUsername('luis')!;
      expect(stored.isLicenseValid, isTrue);
      // El dispositivo conserva la licencia: la UI llama a payments.logout()
      // para limpiarla al regresar al login.
      expect(payments.hasValidLicense, isTrue);
    });
  });

  group('rememberMe', () {
    test('true persiste session_username; false no la persiste', () async {
      final (:accounts, :payments) = await buildService();
      await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );

      await accounts.loginUser('luis', 'pass1234', rememberMe: true);
      expect(accounts.rememberMe, isTrue);

      // Nueva instancia con los mismos prefs recupera la sesión.
      final restored = UserAccountService(
        await SharedPreferences.getInstance(),
        payments: payments,
      );
      expect(restored.isLoggedIn, isTrue);
      expect(restored.currentSessionUsername, 'luis');
      expect(restored.rememberMe, isTrue);

      // Cerrar y entrar de nuevo sin recordarme.
      await accounts.logoutUser();
      await accounts.loginUser('luis', 'pass1234', rememberMe: false);
      expect(accounts.isLoggedIn, isTrue);
      expect(accounts.rememberMe, isFalse);

      final notRestored = UserAccountService(
        await SharedPreferences.getInstance(),
        payments: payments,
      );
      expect(notRestored.isLoggedIn, isFalse);
      expect(notRestored.rememberMe, isFalse);
    });
  });

  group('persistencia', () {
    test(
      'una nueva instancia carga las cuentas y licencias guardadas',
      () async {
        final (:accounts, :payments) = await buildService();
        await accounts.createAccountWithLicense(
          pending: pendingFor('luis'),
          licenseExpiry: null,
          productId: kProductIdPerpetual,
        );
        await accounts.createAccountWithDeviceLicense(
          pending: pendingFor('ana'),
        );
        expect(accounts.allAccounts.length, 2);

        final reloaded = UserAccountService(
          await SharedPreferences.getInstance(),
          payments: payments,
        );
        expect(reloaded.allAccounts.length, 2);
        expect(reloaded.usernameExists('luis'), isTrue);
        expect(reloaded.usernameExists('ana'), isTrue);
        expect(
          reloaded.findByUsername('luis')!.verifyPassword('pass1234'),
          isTrue,
        );
        expect(
          reloaded.findByUsername('ana')!.purchasedProductId,
          kProductIdPerpetual,
        );
      },
    );
  });

  group('estado de sesión', () {
    test('currentUser e isAccountLicenseValid reflejan la sesión', () async {
      final (:accounts, :payments) = await buildService();
      expect(accounts.currentUser, isNull);
      expect(accounts.isAccountLicenseValid, isFalse);

      await accounts.createAccountWithLicense(
        pending: pendingFor('luis'),
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      await accounts.openSession(accounts.findByUsername('luis')!);
      expect(accounts.currentUser?.username, 'luis');
      expect(accounts.isAccountLicenseValid, isTrue);
    });
  });
}
