import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/models/app_metadata.dart';
import 'package:d_0_pension/core/theme/app_theme.dart';
import 'package:d_0_pension/presentation/screens/login_screen.dart';
import 'package:d_0_pension/services/account/user_account_service.dart';
import 'package:d_0_pension/services/account/validation_privileges_service.dart';
import 'package:d_0_pension/services/billing/payment_provider.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';

import 'golden_fonts.dart';

/// Acceso libre SOLO para la cuenta de validación integrada
/// (`builtin_account` en app_metadata.json). El resto sigue el flujo normal.
///
/// Incluye:
/// 1. Tests unitarios de [PaymentProvider.grantValidatorAccess] (sin pump):
///    concede con credenciales correctas (trim + case-insensitive), rechaza
///    usuario/contraseña incorrectos y rechaza si no hay cuenta configurada.
/// 2. Golden del LoginScreen en formato 9:16 (1080×1920, dpr 3.0) →
///    `test/store_screenshots/05_login.png` (la subida a 1080×1920 físicos la
///    hace scripts/upscale_screenshots.ps1 → capturas_tienda/05_login.png).
///
/// NOTA (convención del repo): un solo flujo "pumpWidget" por archivo.
void main() {
  setUpAll(loadGoldenFonts);

  const builtin = BuiltinAccountConfig(
    enabled: true,
    username: 'lescobar69',
    password: '1234',
    licenseDays: 365,
  );

  PaymentProvider buildProvider(
    SharedPreferences prefs, {
    BuiltinAccountConfig? builtinAccount,
  }) {
    return PaymentProvider(
      PlayBillingService(),
      prefs,
      builtinAccount: builtinAccount,
    );
  }

  group('PaymentProvider.grantValidatorAccess', () {
    test(
      'concede acceso libre al usuario de validación (flujo completo)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final provider = buildProvider(prefs, builtinAccount: builtin);

        expect(provider.isLoggedIn, isFalse);
        expect(provider.hasValidLicense, isFalse);

        final granted = await provider.grantValidatorAccess(
          'lescobar69',
          '1234',
        );

        expect(granted, isTrue);
        expect(provider.isLoggedIn, isTrue);
        expect(provider.loginUsername, 'lescobar69');
        expect(provider.hasValidLicense, isTrue);
        expect(provider.licenseProductId, kProductIdSemestral);
        expect(
          provider.licenseExpiry,
          isNotNull,
          reason: 'licencia con vencimiento (now + license_days)',
        );
        expect(
          provider.licenseExpiry!.isAfter(DateTime.now()),
          isTrue,
          reason: 'la licencia no debe estar vencida al otorgarse',
        );
        expect(provider.isOnboardingCompleted, isTrue);

        // El reset limpia también el usuario de login (sesión cerrada).
        await provider.resetLicense();
        expect(provider.isLoggedIn, isFalse);
        expect(provider.hasValidLicense, isFalse);
        expect(provider.loginUsername, isNull);
      },
    );

    test(
      'acepta usuario con mayúsculas y espacios (trim + case-insensitive)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final provider = buildProvider(prefs, builtinAccount: builtin);

        final granted = await provider.grantValidatorAccess(
          '  LESCOBAR69  ',
          '1234',
        );

        expect(granted, isTrue);
        expect(provider.loginUsername, 'lescobar69');
        expect(provider.hasValidLicense, isTrue);
      },
    );

    test('rechaza contraseña incorrecta', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = buildProvider(prefs, builtinAccount: builtin);

      final granted = await provider.grantValidatorAccess(
        'lescobar69',
        'incorrecta',
      );

      expect(granted, isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.loginUsername, isNull);
      expect(provider.hasValidLicense, isFalse);
      expect(provider.isOnboardingCompleted, isFalse);
    });

    test('rechaza usuario incorrecto', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = buildProvider(prefs, builtinAccount: builtin);

      final granted = await provider.grantValidatorAccess(
        'otro_usuario',
        '1234',
      );

      expect(granted, isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.hasValidLicense, isFalse);
    });

    test('rechaza acceso si no hay cuenta integrada configurada', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = buildProvider(prefs); // sin builtinAccount

      final granted = await provider.grantValidatorAccess('lescobar69', '1234');

      expect(granted, isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.hasValidLicense, isFalse);
    });
  });

  testWidgets('Golden login 9:16 — 1080x1920', (tester) async {
    // Superficie determinista 9:16: física 1080×1920, dpr 3.0 → 360×640 lógicos.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PaymentProvider>(
            create: (_) => PaymentProvider(PlayBillingService(), prefs),
          ),
          ChangeNotifierProvider<UserAccountService>(
            create: (context) => UserAccountService(
              prefs,
              payments: context.read<PaymentProvider>(),
            ),
          ),
          Provider<ValidationPrivilegesService>(
            create: (_) => const ValidationPrivilegesService(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.fromConfig(null),
          home: const LoginScreen(),
        ),
      ),
    );

    await tester.pump();

    // El branding usa Image.asset (logo oficial). La decodificación de imagen
    // requiere I/O real: se precarga en un bloque runAsync para que el golden
    // capture el logo renderizado (si no, quedaría un recuadro vacío).
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(LoginScreen));
      await precacheImage(
        const AssetImage('assets/icons/app_icon_512.png'),
        ctx,
      );
    });
    await tester.pump();

    // Formulario usuario/contraseña y botón Acceder (sin credenciales demo).
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Usuario'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Acceder'), findsOneWidget);
    expect(find.text('Acceso de demostración'), findsNothing);

    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('store_screenshots/05_login.png'),
    );
  });
}
