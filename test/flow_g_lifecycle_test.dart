import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_0_pension/core/engine/formula_evaluator.dart';
import 'package:d_0_pension/core/models/result.dart';
import 'package:d_0_pension/presentation/screens/home_tabs_screen.dart';
import 'package:d_0_pension/presentation/screens/license_screen.dart';
import 'package:d_0_pension/presentation/screens/login_screen.dart';
import 'package:d_0_pension/presentation/screens/payment_screen.dart';
import 'package:d_0_pension/services/billing/play_billing_service.dart';
import 'package:d_0_pension/services/billing/play_purchase_success.dart';
import 'package:d_0_pension/services/persistence_service.dart';
import 'package:d_0_pension/services/retroactive_provider.dart';

import 'entry_flow_harness.dart';
import 'golden_fonts.dart';
import 'golden_harness.dart';

/// Flujo G — CICLO DE VIDA COMPLETO de un usuario NORMAL.
///
/// Emula, como un usuario real, los tres momentos clave de la app:
///
///   G1a  Operación diaria  — sesión activa con licencia vigente entra
///        DIRECTO a la calculadora (sin login ni pago). Sin spinners.
///   G1b  Operación diaria  — re-login de un usuario con licencia vigente
///        → calculadora. Y confirma la corrección de raíz: el LOGIN ya no
///        tiene 'Recuperar acceso' (era el punto que atrapaba al usuario en
///        el ciclo de recuperación sin salida).
///   G2   Cobro (alta)      — usuario NUEVO: registro → /payment → compra
///        semestral $599/6 meses → '¡Licencia Activada!' → licencia de 180
///        días + cuenta materializada + sesión abierta → calculadora.
///   G3   Renovación 6 meses— suscripción semestral VENCIDA con sesión:
///        'Licencia Expirada' → 'Renovar Licencia' → /payment → intenta
///        'Recuperar acceso' pero ya NO hay suscripción activa (lapsed) →
///        vista anti-ciclo 'No hay suscripción activa' → recompra semestral
///        → nueva licencia de 180 días + cuenta sincronizada + sesión
///        conservada → calculadora.
///
/// Billing: [FakeBillingService] para G1/G2 (tienda siempre disponible) y
/// [_LapsedBillingService] para G3 (restore falla con "no hay suscripción
/// activa", reproduciendo el escenario del ciclo original).
class _LapsedBillingService extends FakeBillingService {
  @override
  Future<Result<PlayPurchaseSuccess>> restoreSemestralLicense() async =>
      const Failure(kNoSubscriptionMessage);
}

/// Providers extra necesarios para renderizar el shell real de la calculadora
/// ([HomeTabsScreen]) con su [RetroactiveProvider] inicializado.
List<SingleChildWidget> _calculatorProviders(SharedPreferences prefs) => [
  ChangeNotifierProvider(
    create: (_) => RetroactiveProvider(
      evaluator: FormulaEvaluator(),
      persistence: PersistenceService(prefs),
    )..initialize(),
  ),
];

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets(
    'G1a operación diaria: sesión activa + licencia vigente → calculadora',
    (tester) async {
      setGoldenSurface(tester);

      // Usuario con sesión abierta y licencia semestral vigente (~150 días).
      final expiry = DateTime.now().add(const Duration(days: 150));
      SharedPreferences.setMockInitialValues({
        'user_accounts': jsonEncode([
          seedUserJson(
            username: 'carlos',
            password: '1234',
            licenseExpiry: expiry,
            purchasedProductId: kProductIdSemestral,
          ),
        ]),
        'session_username': 'carlos',
        'license_expiry': expiry.toIso8601String(),
        'license_product_id': kProductIdSemestral,
        'onboarding_completed': true,
        'disclaimer_seen': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: FakeBillingService(),
          home: const HomeTabsScreen(),
          initialRoute: '/',
          extraProviders: _calculatorProviders(prefs),
        ),
      );

      // Operación diaria: entra DIRECTO a la calculadora, sin login ni pago.
      await pumpUntilFound(tester, find.byType(TabBar));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(HomeTabsScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(PaymentScreen), findsNothing);
      expect(find.byType(LicenseScreen), findsNothing);

      // La sesión se conserva y la licencia sigue vigente con ~150 días.
      expect(prefs.getString('session_username'), 'carlos');
      final storedExpiry = DateTime.parse(prefs.getString('license_expiry')!);
      expect(
        storedExpiry.difference(DateTime.now()).inDays,
        inInclusiveRange(149, 150),
        reason: 'la licencia sembrada conserva ~150 días de vigencia',
      );
    },
  );

  testWidgets('G1b operación diaria: re-login con licencia → calculadora (sin '
      "'Recuperar acceso' en el login)", (tester) async {
    setGoldenSurface(tester);

    // Cuenta existente con licencia vigente (~90 días), SIN sesión abierta.
    final expiry = DateTime.now().add(const Duration(days: 90));
    SharedPreferences.setMockInitialValues({
      'user_accounts': jsonEncode([
        seedUserJson(
          username: 'carlos',
          password: '1234',
          licenseExpiry: expiry,
          purchasedProductId: kProductIdSemestral,
        ),
      ]),
      'onboarding_completed': true,
      'disclaimer_seen': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      buildFlowApp(
        prefs: prefs,
        billing: FakeBillingService(),
        home: const HomeStub(),
        initialRoute: '/login',
      ),
    );
    await pumpUntilFound(tester, find.text('Iniciar sesión'));

    // CORRECCIÓN DE RAÍZ: el login ya no ofrece 'Recuperar acceso'
    // (era el callejón sin salida que atrapaba al usuario en el ciclo).
    expect(find.text('Recuperar acceso'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Recuperar acceso'), findsNothing);

    // Re-login con las credenciales de la cuenta sembrada.
    await tester.enterText(find.byType(TextFormField).at(0), 'carlos');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    final acceder = find.widgetWithText(ElevatedButton, 'Acceder');
    await tester.ensureVisible(acceder);
    await tester.tap(acceder);

    // Con la cuenta válida aterriza en la calculadora (home).
    await pumpUntilFound(tester, find.text('HOME_STUB_OK'));
    expect(prefs.getString('session_username'), 'carlos');
  });

  testWidgets(
    'G2 cobro (alta): registro → pago semestral \$599 → licencia 180 días '
    '+ cuenta + sesión → calculadora',
    (tester) async {
      setGoldenSurface(tester);

      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: FakeBillingService(),
          home: const HomeStub(),
          initialRoute: '/login',
        ),
      );
      await tester.pump();

      // 1) Registro de usuario nuevo.
      final toggle = find.text('¿No tienes cuenta? Regístrate');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(0), 'nuevouser');
      await tester.enterText(find.byType(TextFormField).at(1), '1234');
      await tester.enterText(find.byType(TextFormField).at(2), '1234');
      final crear = find.widgetWithText(ElevatedButton, 'Crear cuenta');
      await tester.ensureVisible(crear);
      await tester.tap(crear);

      // 2) /payment: selección de plan (sin errores fantasma heredados).
      await pumpUntilFound(tester, find.text('Elige tu plan'));
      expect(find.text('Suscripción Semestral'), findsOneWidget);
      expect(find.textContaining(r'$599'), findsWidgets);
      expect(find.text('Comprar Suscripción Semestral'), findsOneWidget);
      expect(find.text('No hay suscripción activa'), findsNothing);
      expect(find.text(kNoSubscriptionMessage), findsNothing);
      expect(find.text('Error de conexión'), findsNothing);

      // 3) Compra del semestre (cobro verificado).
      await tester.ensureVisible(find.text('Comprar Suscripción Semestral'));
      await tester.tap(find.text('Comprar Suscripción Semestral'));
      await pumpUntilFound(tester, find.text('¡Licencia Activada!'));

      // 4) Licencia semestral: 180 días (6 meses).
      expect(prefs.getString('license_product_id'), kProductIdSemestral);
      final semExpiry = DateTime.parse(prefs.getString('license_expiry')!);
      expect(
        semExpiry.difference(DateTime.now()).inDays,
        inInclusiveRange(179, 180),
        reason: 'la suscripción semestral dura 180 días (6 meses)',
      );

      // 5) Cuenta materializada + sesión abierta.
      final accounts = jsonDecode(prefs.getString('user_accounts')!) as List;
      expect(accounts, hasLength(1));
      expect((accounts.first as Map<String, dynamic>)['username'], 'nuevouser');
      expect(prefs.getString('session_username'), 'nuevouser');

      // 6) Pantalla de éxito: saluda a la sesión, sin 'Vincular a mi cuenta'.
      expect(find.text('Ir a la Calculadora'), findsOneWidget);
      expect(find.text('Vincular a mi cuenta'), findsNothing);
      expect(find.textContaining('nuevouser'), findsWidgets);

      // 7) Cobro completo → calculadora.
      await tester.tap(find.text('Ir a la Calculadora'));
      await pumpUntilFound(tester, find.text('HOME_STUB_OK'));
    },
  );

  testWidgets(
    'G3 renovación 6 meses: licencia vencida → renovar → sin suscripción '
    'activa → recomprar 180 días → calculadora',
    (tester) async {
      setGoldenSurface(tester);

      // Semestre anterior VENCIDO (hace 10 días) + sesión abierta. El restore
      // falla con "no hay suscripción activa" (suscripción lapsed en Play),
      // reproduciendo el escenario que antes encerraba al usuario en el ciclo.
      final oldExpiry = DateTime.now().subtract(const Duration(days: 10));
      SharedPreferences.setMockInitialValues({
        'user_accounts': jsonEncode([
          seedUserJson(
            username: 'renovador',
            password: '1234',
            licenseExpiry: oldExpiry,
            purchasedProductId: kProductIdSemestral,
          ),
        ]),
        'session_username': 'renovador',
        'license_expiry': oldExpiry.toIso8601String(),
        'license_product_id': kProductIdSemestral,
        'onboarding_completed': true,
        'disclaimer_seen': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        buildFlowApp(
          prefs: prefs,
          billing: _LapsedBillingService(),
          home: const HomeStub(),
        ),
      );

      // 1) Sesión + licencia vencida → pantalla de licencia con estado expirado.
      await pumpUntilFound(tester, find.text('Mi Licencia'));
      expect(find.text('Licencia Expirada'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Renovar Licencia'),
        findsOneWidget,
      );
      expect(find.text('Ir a la Calculadora'), findsNothing);

      // 2) Renovar → /payment (selección de plan, sin errores heredados).
      final renovar = find.widgetWithText(ElevatedButton, 'Renovar Licencia');
      await tester.ensureVisible(renovar);
      await tester.tap(renovar);
      await pumpUntilFound(tester, find.text('Elige tu plan'));
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(find.text('No hay suscripción activa'), findsNothing);
      expect(find.text('Error de conexión'), findsNothing);

      // 3) Intenta 'Recuperar acceso', pero la suscripción YA NO está activa
      //    (lapsed) → vista anti-ciclo 'No hay suscripción activa' con el
      //    camino accionable para recomprar.
      final recuperar = find.text('Recuperar acceso');
      await tester.ensureVisible(recuperar);
      await tester.tap(recuperar);
      await pumpUntilFound(tester, find.text('No hay suscripción activa'));
      expect(find.text('Comprar Suscripción Semestral'), findsOneWidget);
      expect(find.text('Volver'), findsOneWidget);

      // 4) Recompra el semestre desde la propia vista anti-ciclo.
      await tester.ensureVisible(find.text('Comprar Suscripción Semestral'));
      await tester.tap(find.text('Comprar Suscripción Semestral'));
      await pumpUntilFound(tester, find.text('¡Licencia Activada!'));

      // 5) Nueva licencia de 180 días (renovación: base = máx(ahora, anterior)).
      expect(prefs.getString('license_product_id'), kProductIdSemestral);
      final newExpiry = DateTime.parse(prefs.getString('license_expiry')!);
      expect(
        newExpiry.difference(DateTime.now()).inDays,
        inInclusiveRange(179, 180),
        reason: 'la renovación semestral extiende la licencia otros 180 días',
      );
      expect(
        newExpiry.isAfter(oldExpiry),
        isTrue,
        reason: 'la nueva licencia vence después de la anterior',
      );

      // 6) La sesión se conserva y la cuenta se sincroniza con la licencia
      //    renovada (linkDeviceLicenseToUser).
      expect(prefs.getString('session_username'), 'renovador');
      final accounts = jsonDecode(prefs.getString('user_accounts')!) as List;
      final renewed = accounts.first as Map<String, dynamic>;
      expect(renewed['username'], 'renovador');
      final accountExpiry = DateTime.parse(renewed['licenseExpiry'] as String);
      expect(
        accountExpiry.isAfter(DateTime.now()),
        isTrue,
        reason: 'la licencia de la cuenta se sincroniza tras la renovación',
      );

      // 7) Ya hay sesión → sin 'Vincular a mi cuenta' → calculadora.
      expect(find.text('Vincular a mi cuenta'), findsNothing);
      expect(find.textContaining('renovador'), findsWidgets);
      await tester.tap(find.text('Ir a la Calculadora'));
      await pumpUntilFound(tester, find.text('HOME_STUB_OK'));
    },
  );
}
