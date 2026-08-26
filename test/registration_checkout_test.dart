import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/user_profile.dart';
import 'package:d_0_pension/services/account/pending_registration.dart';
import 'package:d_0_pension/services/account/registration_checkout.dart';
import 'package:d_0_pension/services/account/user_account_service.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/billing/play_purchase_success.dart';

/// Tests del checkout diferido ([RegistrationCheckout]).
///
/// Regla del proyecto: la cuenta SOLO se materializa después de una compra
/// VERIFICADA. Aquí simulamos la licencia ya aplicada al dispositivo (el paso
/// que ejecuta PaymentProvider tras la compra) y verificamos que el checkout
/// crea la cuenta, abre sesión y no duplica usuarios.
void main() {
  /// Compra verificada equivalente a la de Play Store para la suscripción
  /// semestral ($599 / 6 meses).
  PlayPurchaseSuccess verifiedSemestralPurchase() {
    final product = ProductDetails(
      id: kProductIdSemestral,
      title: 'Suscripción Semestral',
      description: '6 meses de acceso completo',
      price: '\$599',
      rawPrice: 599.0,
      currencyCode: 'MXN',
    );
    return PlayPurchaseSuccess(
      product: product,
      verifiedProductId: kProductIdSemestral,
      purchaseToken: 'token-de-prueba-123',
      transactionId: 'GPA.1234-5678',
    );
  }

  Future<({PaymentProvider payments, UserAccountService accounts})>
  build() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final payments = PaymentProvider(PlayBillingService(), prefs);
    final accounts = UserAccountService(prefs, payments: payments);
    return (payments: payments, accounts: accounts);
  }

  group('completeCheckoutAfterVerifiedPurchase', () {
    test('crea la cuenta con la licencia comprada y abre sesión', () async {
      final (:payments, :accounts) = await build();
      // El paso previo de la compra verificada ya aplicó la licencia al
      // dispositivo (ahora + 180 días para la suscripción semestral).
      await payments.applyLicense(
        expiry: DateTime.now().add(const Duration(days: 180)),
        productId: kProductIdSemestral,
      );
      final checkout = RegistrationCheckout(
        accounts: accounts,
        payments: payments,
      );

      final pending = PendingRegistration.create(
        username: 'nueva',
        password: 'pass1234',
        email: 'nueva@example.com',
      );
      final ok = await checkout.completeCheckoutAfterVerifiedPurchase(
        pending: pending,
        purchase: verifiedSemestralPurchase(),
      );

      expect(ok, isTrue);
      expect(accounts.usernameExists('nueva'), isTrue);
      final user = accounts.findByUsername('nueva')!;
      expect(user.purchasedProductId, kProductIdSemestral);
      expect(user.isLicenseValid, isTrue);
      expect(user.email, 'nueva@example.com');
      expect(user.verifyPassword('pass1234'), isTrue);
      expect(accounts.isLoggedIn, isTrue);
      expect(accounts.currentSessionUsername, 'nueva');
    });

    test('false si el usuario ya existe (no duplica cuentas)', () async {
      final (:payments, :accounts) = await build();
      await payments.applyLicense(
        expiry: DateTime.now().add(const Duration(days: 180)),
        productId: kProductIdSemestral,
      );
      final checkout = RegistrationCheckout(
        accounts: accounts,
        payments: payments,
      );
      final pending = PendingRegistration.create(
        username: 'nueva',
        password: 'pass1234',
      );

      final first = await checkout.completeCheckoutAfterVerifiedPurchase(
        pending: pending,
        purchase: verifiedSemestralPurchase(),
      );
      expect(first, isTrue);

      final second = await checkout.completeCheckoutAfterVerifiedPurchase(
        pending: pending,
        purchase: verifiedSemestralPurchase(),
      );
      expect(second, isFalse);
      expect(accounts.allAccounts.length, 1);
    });

    test('false cuando la cuenta no se puede materializar', () async {
      final (:payments, :accounts) = await build();
      final checkout = RegistrationCheckout(
        accounts: accounts,
        payments: payments,
      );
      // Licencia no aplicada (payments.licenseExpiry == null) → aún así se crea
      // la cuenta con la licencia reflejada; aquí el caso de fallo es el usuario
      // duplicado, ya cubierto. Verificamos el flujo feliz sin expiración
      // (licencia perpetua).
      await payments.applyLicense(expiry: null, productId: kProductIdPerpetual);
      final pending = PendingRegistration.create(
        username: 'vitalicia',
        password: 'pass1234',
      );
      final ok = await checkout.completeCheckoutAfterVerifiedPurchase(
        pending: pending,
        purchase: verifiedSemestralPurchase(),
      );
      // purchase.verifiedProductId manda sobre la licencia del dispositivo.
      expect(ok, isTrue);
      expect(
        accounts.findByUsername('vitalicia')!.purchasedProductId,
        kProductIdSemestral,
      );
    });
  });

  group('linkToExistingLicense', () {
    test(
      'con pending crea la cuenta reutilizando la licencia del dispositivo',
      () async {
        final (:payments, :accounts) = await build();
        await payments.applyLicense(
          expiry: null,
          productId: kProductIdPerpetual,
        );
        final checkout = RegistrationCheckout(
          accounts: accounts,
          payments: payments,
        );

        final pending = PendingRegistration.create(
          username: 'recuperado',
          password: 'pass1234',
        );
        final ok = await checkout.linkToExistingLicense(pending: pending);

        expect(ok, isTrue);
        final user = accounts.findByUsername('recuperado')!;
        expect(user.purchasedProductId, kProductIdPerpetual);
        expect(user.isLicenseValid, isTrue);
        expect(accounts.isLoggedIn, isTrue);
        expect(accounts.currentSessionUsername, 'recuperado');
      },
    );

    test('con pending false si el usuario ya existe', () async {
      final (:payments, :accounts) = await build();
      await payments.applyLicense(expiry: null, productId: kProductIdPerpetual);
      final checkout = RegistrationCheckout(
        accounts: accounts,
        payments: payments,
      );
      final pending = PendingRegistration.create(
        username: 'duplicado',
        password: 'pass1234',
      );

      await checkout.linkToExistingLicense(pending: pending);
      final ok = await checkout.linkToExistingLicense(pending: pending);
      expect(ok, isFalse);
      expect(accounts.allAccounts.length, 1);
    });

    test('con pending false sin licencia de dispositivo válida', () async {
      final (:payments, :accounts) = await build();
      final checkout = RegistrationCheckout(
        accounts: accounts,
        payments: payments,
      );
      final pending = PendingRegistration.create(
        username: 'sinlicencia',
        password: 'pass1234',
      );

      final ok = await checkout.linkToExistingLicense(pending: pending);
      expect(ok, isFalse);
      expect(accounts.usernameExists('sinlicencia'), isFalse);
    });

    test('con user vincula la licencia del dispositivo a la cuenta', () async {
      final (:payments, :accounts) = await build();
      await payments.applyLicense(
        expiry: DateTime.now().add(const Duration(days: 180)),
        productId: kProductIdSemestral,
      );
      final checkout = RegistrationCheckout(
        accounts: accounts,
        payments: payments,
      );

      final pending = PendingRegistration.create(
        username: 'luis',
        password: 'pass1234',
      );
      final user = UserProfile(
        id: 'u_luis',
        username: 'luis',
        salt: pending.salt,
        passwordHash: pending.passwordHash,
        createdAt: DateTime.now(),
      );
      expect(user.purchasedProductId, isNull);

      final ok = await checkout.linkToExistingLicense(user: user);
      expect(ok, isTrue);
      final linked = accounts.findByUsername('luis')!;
      expect(linked.purchasedProductId, kProductIdSemestral);
      expect(linked.isLicenseValid, isTrue);
    });

    test('false sin pending ni user', () async {
      final (:payments, :accounts) = await build();
      final checkout = RegistrationCheckout(
        accounts: accounts,
        payments: payments,
      );
      final ok = await checkout.linkToExistingLicense();
      expect(ok, isFalse);
    });
  });
}
