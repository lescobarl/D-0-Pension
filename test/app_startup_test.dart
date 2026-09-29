import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/user_profile.dart';
import 'package:d_0_pension/services/account/app_startup.dart';
import 'package:d_0_pension/services/account/pending_registration.dart';
import 'package:d_0_pension/services/account/user_account_service.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

/// Tests del resolvedor único de entrada ([AppStartup]).
///
/// Cubre los flujos de arranque:
///  - A: nuevo usuario sin onboarding → onboarding.
///  - B: sesión de cuenta con licencia válida → home.
///  - C: sesión de cuenta con licencia vencida → license (renovar).
///  - D: sin nada → login; licencia de dispositivo vigente → home.
///  - E: licencia de dispositivo vencida → license (renovar).
///  - F: validator con acceso libre → home.
void main() {
  late SharedPreferences prefs;
  late PaymentProvider payments;
  late UserAccountService accounts;

  Future<void> setup(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    prefs = await SharedPreferences.getInstance();
    payments = PaymentProvider(PlayBillingService(), prefs);
    accounts = UserAccountService(prefs, payments: payments);
  }

  UserProfile makeUser(
    String username, {
    String password = 'pass1234',
    DateTime? licenseExpiry,
    String? productId,
  }) {
    final pending = PendingRegistration.create(
      username: username,
      password: password,
    );
    return UserProfile(
      id: 'u_$username',
      username: username,
      salt: pending.salt,
      passwordHash: pending.passwordHash,
      licenseExpiry: licenseExpiry,
      purchasedProductId: productId,
      createdAt: DateTime.now(),
    );
  }

  Map<String, Object> seedAccounts(List<UserProfile> users, {String? session}) {
    final map = <String, Object>{
      'user_accounts': jsonEncode(users.map((u) => u.toJson()).toList()),
      'onboarding_completed': true,
    };
    if (session != null) map['session_username'] = session;
    return map;
  }

  StartupDestination resolve() => AppStartup.resolveStartupDestination(
    payments: payments,
    accounts: accounts,
  );

  group('resolveStartupDestination', () {
    test('sin inicializar → splash', () async {
      await setup({});
      expect(resolve(), StartupDestination.splash);
    });

    test('sin onboarding → onboarding (flujo A, usuario nuevo)', () async {
      await setup({'onboarding_completed': false});
      await payments.initialize();
      expect(resolve(), StartupDestination.onboarding);
    });

    test('sesión de cuenta con licencia válida → home (flujo B)', () async {
      final user = makeUser(
        'luis',
        licenseExpiry: DateTime.now().add(const Duration(days: 30)),
        productId: kProductIdAnnual,
      );
      await setup(seedAccounts([user], session: 'luis'));
      await payments.initialize();
      expect(resolve(), StartupDestination.home);
    });

    test('sesión de cuenta con licencia vencida → license (flujo C)', () async {
      final user = makeUser(
        'luis',
        licenseExpiry: DateTime.now().subtract(const Duration(days: 1)),
        productId: kProductIdAnnual,
      );
      await setup(seedAccounts([user], session: 'luis'));
      await payments.initialize();
      expect(resolve(), StartupDestination.license);
    });

    test('sesión de cuenta perpetua → home', () async {
      final user = makeUser(
        'luis',
        licenseExpiry: null,
        productId: kProductIdPerpetual,
      );
      await setup(seedAccounts([user], session: 'luis'));
      await payments.initialize();
      expect(resolve(), StartupDestination.home);
    });

    test('validator con licencia válida → home (flujo F)', () async {
      await setup({
        'onboarding_completed': true,
        'login_username': 'lescobar69',
        'license_product_id': kProductIdAnnual,
        'license_expiry': DateTime.now()
            .add(const Duration(days: 30))
            .toIso8601String(),
      });
      await payments.initialize();
      expect(resolve(), StartupDestination.home);
    });

    test('validator con licencia vencida → license', () async {
      await setup({
        'onboarding_completed': true,
        'login_username': 'lescobar69',
        'license_product_id': kProductIdAnnual,
        'license_expiry': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });
      await payments.initialize();
      expect(resolve(), StartupDestination.license);
    });

    test(
      'licencia de dispositivo vigente (perpetua) → home (flujo D)',
      () async {
        await setup({
          'onboarding_completed': true,
          'license_product_id': kProductIdPerpetual,
        });
        await payments.initialize();
        expect(resolve(), StartupDestination.home);
      },
    );

    test(
      'licencia de dispositivo vencida → license (flujo E, renovar)',
      () async {
        await setup({
          'onboarding_completed': true,
          'license_product_id': kProductIdAnnual,
          'license_expiry': DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        });
        await payments.initialize();
        expect(resolve(), StartupDestination.license);
      },
    );

    test('sin nada → login', () async {
      await setup({'onboarding_completed': true});
      await payments.initialize();
      expect(resolve(), StartupDestination.login);
    });

    test('sesión activa manda sobre la licencia de dispositivo', () async {
      final user = makeUser(
        'luis',
        licenseExpiry: DateTime.now().add(const Duration(days: 30)),
        productId: kProductIdAnnual,
      );
      await setup(seedAccounts([user], session: 'luis'));
      // Dispositivo con licencia vencida (debería ignorarse por la sesión).
      await payments.applyLicense(
        expiry: DateTime.now().subtract(const Duration(days: 1)),
        productId: kProductIdAnnual,
      );
      await payments.initialize();
      expect(resolve(), StartupDestination.home);
    });
  });

  group('bootstrapGuest', () {
    test(
      'completa el onboarding cuando hay sesión restaurada (idempotente)',
      () async {
        final user = makeUser(
          'luis',
          licenseExpiry: DateTime.now().add(const Duration(days: 30)),
          productId: kProductIdAnnual,
        );
        final seed = seedAccounts([user], session: 'luis')
          ..remove('onboarding_completed');
        await setup(seed);
        await payments.initialize();
        expect(payments.isOnboardingCompleted, isFalse);

        await AppStartup.bootstrapGuest(payments: payments, accounts: accounts);
        expect(payments.isOnboardingCompleted, isTrue);

        // Idempotente: volver a llamar no rompe nada.
        await AppStartup.bootstrapGuest(payments: payments, accounts: accounts);
        expect(payments.isOnboardingCompleted, isTrue);
      },
    );
  });

  group('syncExpiredLicenseFlags', () {
    test('detecta solo licencias con vencimiento superado', () async {
      await setup({'onboarding_completed': true});
      expect(AppStartup.syncExpiredLicenseFlags(payments: payments), isFalse);

      await payments.applyLicense(
        expiry: DateTime.now().subtract(const Duration(days: 1)),
        productId: kProductIdAnnual,
      );
      expect(AppStartup.syncExpiredLicenseFlags(payments: payments), isTrue);

      // Perpetua (sin vencimiento) nunca cuenta como vencida.
      await payments.applyLicense(expiry: null, productId: kProductIdPerpetual);
      expect(AppStartup.syncExpiredLicenseFlags(payments: payments), isFalse);
    });
  });
}
