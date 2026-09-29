import 'dart:async';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../core/models/result.dart';
import 'play_purchase_success.dart';
import 'play_purchase_verifier.dart';

// ---------------------------------------------------------------------------
// Timeout constants (from machote)
// ---------------------------------------------------------------------------
/// How long we wait for the store to emit *any* purchase update before
/// concluding the store is silent (e.g. no UI shown).
const _storeSilenceTimeout = Duration(seconds: 25);

/// How long we wait for the user to complete a purchase in the Play overlay
/// before timing out the entire operation.
const _pendingTimeout = Duration(seconds: 90);

/// How long we wait for a restore to complete.
const _restoreTimeout = Duration(seconds: 15);

/// How long we wait for the startup "active subscription" check.
const _activeCheckTimeout = Duration(seconds: 15);

// ---------------------------------------------------------------------------
// Product IDs (adjust when you publish on Play Console)
// ---------------------------------------------------------------------------
const String kProductIdAnnual = 'subscription_annual_ley73';
const String kProductIdPerpetual = 'license_perpetual_ley73';
const String kProductIdSemestral = 'subscription_semestral_ley73';

/// Friendly message shown when Play Billing is not available on the platform
/// (e.g. web, where `in_app_purchase` has no implementation).
const String kBillingUnavailableMessage =
    'Google Play no está disponible en este dispositivo. '
    'La compra solo se puede realizar en la aplicación para Android o iOS.';

// ---------------------------------------------------------------------------
// PlayBillingService
// ---------------------------------------------------------------------------

/// High-level service that wraps `in_app_purchase` and provides a
/// session-based purchase / restore API.
///
/// Ported from machote's `PlayBillingService` (~440 lines), which is the
/// reference implementation that works correctly in production.
///
/// Adaptations:
///   - `dartz` `Either<Failure, PlayPurchaseSuccess>` → `Result<PlayPurchaseSuccess>`
///   - `Failure` → `String message` inside `Failure`
///   - All BLoC / cubit references removed.
///
/// ## Renovación (regla: deben pagar)
///
/// La suscripción semestral `subscription_semestral_ley73` es RECURRENTE en
/// Google Play: Google cobra la renovación automáticamente a la cuenta Google
/// que compró. Esta app NUNCA concede acceso gratis:
///
///   - `restorePurchases()` de Google Play solo devuelve suscripciones ACTIVAS
///     y PAGADAS de la cuenta Google actual. Si la suscripción caducó (no se
///     cobró la renovación), NO aparece en la lista, así que el usuario debe
///     volver a pagar.
///   - `checkActiveSubscription()` (al iniciar la app) consulta esa misma lista
///     y solo extiende la licencia local cuando existe una suscripción activa
///     y pagada en la misma cuenta.
///   - Los eventos de renovación que llegan sin sesión activa se verifican con
///     la cuenta Google (`verifyPlayStoreRestore`) y solo entonces se notifica
///     vía [onRenewalDetected] para extender la licencia local.
class PlayBillingService {
  late final InAppPurchase _store;

  /// Whether the billing API is available on this device.
  bool _available = false;

  /// Currently active billing session (only one at a time).
  _BillingSession? _session;

  /// Latest product details fetched from the store.
  List<ProductDetails> _products = [];

  /// Subscription to the store's purchase stream.
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Whether we have already subscribed to the purchase stream.
  bool _listening = false;

  /// Completer for the startup "active subscription" check.
  Completer<Result<PlayPurchaseSuccess?>>? _activeCheckCompleter;
  Timer? _activeCheckTimer;
  String? _activeCheckProductId;

  /// Callback invoked when a PAID renewal / existing subscription is detected
  /// on the same Google account (outside any interactive session).
  ///
  /// This is the DI seam (Rule 0.2): [PaymentProvider] registers a handler in
  /// its constructor so the service never calls into the provider directly.
  void Function(PlayPurchaseSuccess success)? onRenewalDetected;

  /// Whether we have already fetched products.
  bool get hasProducts => _products.isNotEmpty;

  /// The list of fetched products.
  List<ProductDetails> get products => List.unmodifiable(_products);

  /// Whether billing is available.
  bool get isAvailable => _available;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /// Initialise the service: check availability, listen to the stream and
  /// fetch products.
  Future<Result<bool>> initialize() async {
    try {
      // Initialize lazily inside try/catch so web (which has no
      // in_app_purchase implementation) doesn't crash at construction time.
      _store = InAppPurchase.instance;
      _available = await _store.isAvailable();
      if (!_available) {
        return const Failure(
          'Google Play Store no está disponible en este '
          'dispositivo.',
        );
      }

      // Listen for purchase updates (must be done once).
      _ensureListening();

      // Fetch product details.
      final productIds = <String>{
        kProductIdAnnual,
        kProductIdPerpetual,
        kProductIdSemestral,
      };
      final productResponse = await _store.queryProductDetails(productIds);

      if (productResponse.error != null) {
        return Failure(
          'Error al consultar productos: '
          '${productResponse.error!.message}',
        );
      }

      _products = productResponse.productDetails;
      return const Success(true);
    } catch (e) {
      if (_isPlatformBillingUnavailable(e)) {
        return const Failure(kBillingUnavailableMessage);
      }
      return Failure('Error al inicializar Play Billing: $e');
    }
  }

  /// Whether [error] indicates that Play Billing is simply not implemented on
  /// this platform (e.g. web), rather than a real store failure.
  bool _isPlatformBillingUnavailable(Object error) {
    final text = error.toString().toLowerCase();
    return error is MissingPluginException ||
        text.contains('missingpluginexception') ||
        text.contains('unsupported platform') ||
        text.contains('no implementation') ||
        text.contains('not implemented on this platform');
  }

  /// Subscribes to the purchase stream exactly once.
  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _subscription = _store.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (Object e, StackTrace st) {
        _closeSession(Failure<PlayPurchaseSuccess>('Error en billing: $e'));
      },
    );
  }

  /// Dispose the service, cancelling any active session and timers.
  void dispose() {
    final session = _session;
    session?.pendingTimer?.cancel();
    session?.storeSilenceTimer?.cancel();
    _session = null;

    _activeCheckTimer?.cancel();
    _activeCheckTimer = null;
    _activeCheckCompleter = null;
    _activeCheckProductId = null;

    _subscription?.cancel();
    _subscription = null;
    _listening = false;
  }

  // -----------------------------------------------------------------------
  // Purchase
  // -----------------------------------------------------------------------

  /// Purchase the annual subscription license.
  Future<Result<PlayPurchaseSuccess>> purchaseAnnualLicense() {
    return _runExclusive(
      intent: _BillingIntent.purchase,
      productId: kProductIdAnnual,
      start: (product) async {
        final started = await _store.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product),
        );
        if (!started) {
          _closeSession(
            const Failure<PlayPurchaseSuccess>(
              'Google Play no abrió el pago. Si ya tienes la suscripción en '
              'esta cuenta, usa «Recuperar acceso».',
            ),
          );
          return;
        }
        final active = _session;
        if (active != null && active.intent == _BillingIntent.purchase) {
          _scheduleStoreSilenceWatch(active);
        }
      },
      timeout: const Duration(seconds: 40),
      timeoutMessage:
          'Tiempo de espera agotado. Si ya pagaste, usa '
          '«Recuperar acceso».',
    );
  }

  /// Purchase the perpetual license.
  Future<Result<PlayPurchaseSuccess>> purchasePerpetualLicense() {
    return _runExclusive(
      intent: _BillingIntent.purchase,
      productId: kProductIdPerpetual,
      start: (product) async {
        final started = await _store.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product),
        );
        if (!started) {
          _closeSession(
            const Failure<PlayPurchaseSuccess>(
              'Google Play no abrió el pago. Si ya tienes la suscripción en '
              'esta cuenta, usa «Recuperar acceso».',
            ),
          );
          return;
        }
        final active = _session;
        if (active != null && active.intent == _BillingIntent.purchase) {
          _scheduleStoreSilenceWatch(active);
        }
      },
      timeout: const Duration(seconds: 40),
      timeoutMessage:
          'Tiempo de espera agotado. Si ya pagaste, usa '
          '«Recuperar acceso».',
    );
  }

  /// Purchase the semestral subscription license.
  Future<Result<PlayPurchaseSuccess>> purchaseSemestralLicense() {
    return _runExclusive(
      intent: _BillingIntent.purchase,
      productId: kProductIdSemestral,
      start: (product) async {
        final started = await _store.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product),
        );
        if (!started) {
          _closeSession(
            const Failure<PlayPurchaseSuccess>(
              'Google Play no abrió el pago. Si ya tienes la suscripción en '
              'esta cuenta, usa «Recuperar acceso».',
            ),
          );
          return;
        }
        final active = _session;
        if (active != null && active.intent == _BillingIntent.purchase) {
          _scheduleStoreSilenceWatch(active);
        }
      },
      timeout: const Duration(seconds: 40),
      timeoutMessage:
          'Tiempo de espera agotado. Si ya pagaste, usa '
          '«Recuperar acceso».',
    );
  }

  /// Restore ("Recuperar acceso") an existing semestral subscription.
  ///
  /// Google Play returns ONLY active, paid subscriptions for the current
  /// Google account. If the subscription lapsed, it won't be in the list and
  /// we report [kNoSubscriptionMessage] so the user pays again.
  Future<Result<PlayPurchaseSuccess>> restoreSemestralLicense() {
    return _runExclusive(
      intent: _BillingIntent.restore,
      productId: kProductIdSemestral,
      start: (product) async {
        await _store.restorePurchases();
      },
      timeout: _restoreTimeout,
      timeoutMessage: kNoSubscriptionMessage,
    );
  }

  /// Checks (at startup, fire-and-forget) whether the current Google account
  /// has an ACTIVE, PAID subscription for [productId].
  ///
  /// Returns `Success(null)` when there is no active subscription, when billing
  /// is unavailable, or when the check times out. This is the authoritative
  /// "deben pagar" signal: it NEVER grants access for a lapsed subscription.
  Future<Result<PlayPurchaseSuccess?>> checkActiveSubscription({
    required String productId,
  }) async {
    if (_activeCheckCompleter != null) return _activeCheckCompleter!.future;
    if (!_available) return const Success<PlayPurchaseSuccess?>(null);

    _activeCheckProductId = productId;
    final completer = Completer<Result<PlayPurchaseSuccess?>>();
    _activeCheckCompleter = completer;
    _activeCheckTimer = Timer(_activeCheckTimeout, () {
      _finishActiveCheck(const Success<PlayPurchaseSuccess?>(null));
    });

    try {
      _ensureListening();
      await _store.restorePurchases();
    } catch (_) {
      _finishActiveCheck(const Success<PlayPurchaseSuccess?>(null));
    }
    return completer.future;
  }

  /// Completes the active-subscription check, cancelling its timer.
  void _finishActiveCheck(Result<PlayPurchaseSuccess?> result) {
    _activeCheckTimer?.cancel();
    _activeCheckTimer = null;
    final completer = _activeCheckCompleter;
    _activeCheckCompleter = null;
    _activeCheckProductId = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  // -----------------------------------------------------------------------
  // Internal – exclusive session runner
  // -----------------------------------------------------------------------

  /// Runs a billing session exclusively – only one session at a time.
  ///
  /// Unlike the old version, this NEVER cancels an in-flight session; it just
  /// reports [_operationBusyMessage] so the UI can show a friendly message
  /// instead of the confusing "Operación cancelada." / timeout cascade.
  Future<Result<PlayPurchaseSuccess>> _runExclusive({
    required _BillingIntent intent,
    required String productId,
    required Future<void> Function(ProductDetails product) start,
    required Duration timeout,
    required String timeoutMessage,
  }) async {
    if (_session?.isOpen == true) {
      return const Failure<PlayPurchaseSuccess>(_operationBusyMessage);
    }
    if (!_available) {
      return const Failure<PlayPurchaseSuccess>(kBillingUnavailableMessage);
    }

    _ensureListening();

    final product = await _querySingleProduct(productId);
    if (product == null) {
      return Failure<PlayPurchaseSuccess>(
        'Producto no encontrado en Play Console. ID esperado: $productId',
      );
    }

    final session = _BillingSession(
      intent: intent,
      productId: productId,
      product: product,
    );
    _session = session;

    try {
      await start(session.product);
      if (!session.isOpen) return await session.completer.future;
      return await session.completer.future.timeout(
        timeout,
        onTimeout: () {
          final result = Failure<PlayPurchaseSuccess>(timeoutMessage);
          _closeSession(result);
          return result;
        },
      );
    } catch (e) {
      final fail = Failure<PlayPurchaseSuccess>('Error de Google Play: $e');
      _closeSession(fail);
      return fail;
    }
  }

  /// Queries a single product from the store (fresh, per-operation) and caches
  /// it so renewal events can be verified later. Returns `null` if the product
  /// is not configured in Play Console.
  Future<ProductDetails?> _querySingleProduct(String productId) async {
    final response = await _store.queryProductDetails({productId});
    if (response.productDetails.isEmpty) return null;
    final product = response.productDetails.first;
    if (!_products.any((p) => p.id == product.id)) {
      _products = [..._products, product];
    }
    return product;
  }

  /// Finds a cached product by id, or `null` if not present.
  ProductDetails? _findProduct(String productId) {
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Purchase stream handler
  // -----------------------------------------------------------------------

  /// Called whenever the store emits a purchase update.
  ///
  /// - With an open session: routes restore vs purchase events.
  /// - Without a session: acknowledges leftover pending purchases, answers the
  ///   startup active-subscription check, and finally detects auto-renewals.
  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    final session = _session;
    if (session != null && session.isOpen) {
      // Una sesión de "Recuperar acceso" (o una compra que cayó en fallback de
      // restore por "ya la tienes") SIEMPRE se resuelve con _handleRestoreResponse.
      // Sin esta ruta, el fallback cuya restore devuelve vacío dejaba la sesión
      // colgada (sin timers activos) hasta el timeout de compra.
      if (session.intent == _BillingIntent.restore ||
          session.restoreFallbackFromPurchase) {
        await _handleRestoreResponse(session, purchases);
        return;
      }
      for (final purchase in purchases) {
        await _handlePurchaseEvent(session, purchase);
      }
      return;
    }

    // No active session: acknowledge any purchases left pending.
    for (final purchase in purchases) {
      if (purchase.pendingCompletePurchase) {
        await _safeCompletePurchase(purchase);
      }
    }

    if (_activeCheckCompleter != null) {
      await _handleActiveCheckResponse(purchases);
      return;
    }

    // Auto-renewal events from Google Play (no interactive session): the user
    // already paid, so we extend the local license.
    for (final purchase in purchases) {
      await _notifyRenewalIfVerified(purchase);
    }
  }

  /// Handles the response of a restore ("Recuperar acceso") operation.
  ///
  /// If the list is empty (no active subscription in this Google account) we
  /// report [kNoSubscriptionMessage] — the subscription lapsed or was never
  /// purchased, so the user must pay.
  Future<void> _handleRestoreResponse(
    _BillingSession session,
    List<PurchaseDetails> purchases,
  ) async {
    session.storeEventReceived = true;
    session.storeSilenceTimer?.cancel();

    PurchaseDetails? match;
    for (final purchase in purchases) {
      if (purchase.productID == session.productId) {
        match = purchase;
      } else if (purchase.pendingCompletePurchase) {
        await _safeCompletePurchase(purchase);
      }
    }

    if (match == null) {
      _closeSession(const Failure<PlayPurchaseSuccess>(kNoSubscriptionMessage));
      return;
    }
    await _handlePurchaseEvent(session, match);
  }

  /// Handles the response of the startup active-subscription check.
  ///
  /// Only an ACTIVE, PAID subscription for the checked product on the current
  /// Google account produces a result; anything else yields `Success(null)`.
  Future<void> _handleActiveCheckResponse(
    List<PurchaseDetails> purchases,
  ) async {
    final productId = _activeCheckProductId;
    if (productId == null) return;

    for (final purchase in purchases) {
      if (purchase.productID != productId) continue;
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final product = _findProduct(productId);
      if (product == null) {
        _finishActiveCheck(const Success<PlayPurchaseSuccess?>(null));
        return;
      }
      final verification = PlayPurchaseVerifier.verifyPlayStoreRestore(
        product: product,
        purchase: purchase,
        expectedProductId: productId,
      );
      if (verification is Success<PlayPurchaseSuccess>) {
        _finishActiveCheck(Success<PlayPurchaseSuccess?>(verification.value));
        return;
      }
    }
    _finishActiveCheck(const Success<PlayPurchaseSuccess?>(null));
  }

  /// Verifies a purchase event that arrived without an interactive session
  /// (Google Play auto-renewal) and, if it is a valid PAID subscription on the
  /// same Google account, notifies via [onRenewalDetected].
  Future<void> _notifyRenewalIfVerified(PurchaseDetails purchase) async {
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return;
    }
    final product = _findProduct(purchase.productID);
    if (product == null) return;

    final verification = PlayPurchaseVerifier.verifyPlayStoreRestore(
      product: product,
      purchase: purchase,
      expectedProductId: purchase.productID,
    );
    if (verification is Success<PlayPurchaseSuccess>) {
      final success = verification.value;
      if (success.verifiedProductId == kProductIdSemestral ||
          success.verifiedProductId == kProductIdAnnual) {
        onRenewalDetected?.call(success);
      }
    }
  }

  /// Handles a single purchase event for the given open session.
  Future<void> _handlePurchaseEvent(
    _BillingSession session,
    PurchaseDetails purchase,
  ) async {
    if (purchase.productID != session.productId) {
      // Unrelated product: acknowledge so it doesn't get re-sent.
      if (purchase.pendingCompletePurchase) {
        await _safeCompletePurchase(purchase);
      }
      return;
    }

    session.storeEventReceived = true;
    session.storeSilenceTimer?.cancel();

    switch (purchase.status) {
      case PurchaseStatus.pending:
        _schedulePendingTimeout(session);
        break;
      case PurchaseStatus.error:
        session.pendingTimer?.cancel();
        await _safeCompletePurchase(purchase);
        // El fallback se ejecuta UNA sola vez: si el propio restore de respaldo
        // devuelve un error, cerramos con un mensaje claro en lugar de entrar
        // en un bucle infinito de restores.
        if (!session.restoreFallbackFromPurchase &&
            _looksLikeAlreadyOwnedSubscription(purchase.error?.message)) {
          // The user already has this subscription in this Google account:
          // fall back to a restore so they recover access instead of failing.
          session.restoreFallbackFromPurchase = true;
          await _store.restorePurchases();
          break;
        }
        _closeSession(
          Failure<PlayPurchaseSuccess>(_mapStoreError(purchase.error?.message)),
        );
        break;
      case PurchaseStatus.canceled:
        session.pendingTimer?.cancel();
        await _safeCompletePurchase(purchase);
        _closeSession(const Failure<PlayPurchaseSuccess>('Compra cancelada.'));
        break;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        session.pendingTimer?.cancel();
        await _finalizeSuccessfulPurchase(session, purchase);
        break;
    }
  }

  /// Whether the error message suggests the user already owns this
  /// subscription on the current Google account.
  bool _looksLikeAlreadyOwnedSubscription(String? raw) {
    if (raw == null) return false;
    final lower = raw.toLowerCase();
    return lower.contains('already') ||
        lower.contains('owned') ||
        lower.contains('suscrib') ||
        lower.contains('duplicate');
  }

  /// Maps a raw store error message to a user-friendly one.
  ///
  /// Ported from machote: network-like errors get a clear "services of Google"
  /// explanation (NOT "your Wi-Fi is off"), and "already subscribed" errors
  /// point the user to «Recuperar acceso».
  String _mapStoreError(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Error en la compra con Google Play.';
    }
    final lower = raw.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('red') ||
        lower.contains('connection') ||
        lower.contains('internet') ||
        lower.contains('wifi')) {
      return 'Google Play no pudo completar la operación. Suele ser un fallo '
          'temporal de los servicios de Google (no significa que tu Wi‑Fi esté '
          'apagado). Abre Play Store, espera un momento e inténtalo de nuevo.';
    }
    if (lower.contains('suscrib') || lower.contains('already subscribed')) {
      return 'Esta cuenta de Google ya tiene la suscripción. Usa '
          '«Recuperar acceso».';
    }
    return raw;
  }

  /// Schedules the store-silence watch (purchase only, 25s).
  ///
  /// If the store never emits an event after we started the purchase, we first
  /// try to recover access via restore. This covers the native "ya te
  /// suscribiste" dialog (which emits no event) and charges that still need to
  /// propagate. The flag guarantees a single restore; only a second silence
  /// closes the session.
  void _scheduleStoreSilenceWatch(_BillingSession session) {
    session.storeSilenceTimer?.cancel();
    session.storeSilenceTimer = Timer(_storeSilenceTimeout, () {
      if (!session.isOpen || session.storeEventReceived) return;
      if (!session.restoreFallbackFromPurchase) {
        session.restoreFallbackFromPurchase = true;
        _store.restorePurchases();
        return;
      }
      _closeSession(
        const Failure<PlayPurchaseSuccess>(
          'Google Play no completó la compra. Si ya tienes la suscripción en '
          'esta cuenta, usa «Recuperar acceso».',
        ),
      );
    });
  }

  /// Schedules the pending-timeout (90s): the purchase is stuck in "pending".
  void _schedulePendingTimeout(_BillingSession session) {
    session.pendingTimer?.cancel();
    session.pendingTimer = Timer(_pendingTimeout, () {
      if (!session.isOpen) return;
      _closeSession(
        const Failure<PlayPurchaseSuccess>(
          'La compra quedó pendiente en Google Play. Revisa Pagos y '
          'suscripciones en Play Store o usa «Recuperar acceso».',
        ),
      );
    });
  }

  /// Finalises a successful purchase: verifies it, acknowledges it and closes
  /// the session with the verified result.
  Future<void> _finalizeSuccessfulPurchase(
    _BillingSession session,
    PurchaseDetails purchase,
  ) async {
    if (!session.isOpen) {
      await _safeCompletePurchase(purchase);
      return;
    }
    try {
      final useRestoreVerification =
          session.intent == _BillingIntent.restore ||
          session.restoreFallbackFromPurchase;
      final Result<PlayPurchaseSuccess> verification = useRestoreVerification
          ? PlayPurchaseVerifier.verifyPlayStoreRestore(
              product: session.product,
              purchase: purchase,
              expectedProductId: session.productId,
            )
          : PlayPurchaseVerifier.verifyPlayStorePurchase(
              product: session.product,
              purchase: purchase,
              expectedProductId: session.productId,
            );
      if (verification is Failure<PlayPurchaseSuccess>) {
        await _safeCompletePurchase(purchase);
        _closeSession(Failure<PlayPurchaseSuccess>(verification.message));
        return;
      }
      await _safeCompletePurchase(purchase);
      _closeSession(verification);
    } catch (e) {
      _closeSession(
        Failure<PlayPurchaseSuccess>('Error al verificar la compra: $e'),
      );
    }
  }

  /// Closes the current session with [result], cancelling its timers.
  void _closeSession(Result<PlayPurchaseSuccess> result) {
    final session = _session;
    if (session == null) return;
    session.pendingTimer?.cancel();
    session.storeSilenceTimer?.cancel();
    if (!session.completer.isCompleted) {
      session.completer.complete(result);
    }
    if (identical(_session, session)) {
      _session = null;
    }
  }

  /// Acknowledges a purchase only if the store requires it (subscriptions).
  Future<void> _safeCompletePurchase(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _store.completePurchase(purchase);
    }
  }
}

// ---------------------------------------------------------------------------
// Billing session
// ---------------------------------------------------------------------------

enum _BillingIntent { purchase, restore }

/// A single billing operation session with timeout management.
///
/// Ported from machote's `_BillingSession` which used `Completer<Either<…>>`.
class _BillingSession {
  _BillingSession({
    required this.intent,
    required this.productId,
    required this.product,
  });

  final _BillingIntent intent;
  final String productId;
  final ProductDetails product;

  final Completer<Result<PlayPurchaseSuccess>> completer =
      Completer<Result<PlayPurchaseSuccess>>();

  Timer? pendingTimer;
  Timer? storeSilenceTimer;

  /// Whether the store emitted an event for this session.
  bool storeEventReceived = false;

  /// Whether the session started as a purchase but fell back to a restore
  /// because the user already owns the subscription.
  bool restoreFallbackFromPurchase = false;

  /// Whether this session is still open (not yet completed).
  bool get isOpen => !completer.isCompleted;
}

const String _operationBusyMessage =
    'Ya hay una operación de Google Play en curso. Espera un momento e '
    'inténtalo de nuevo.';

/// Mensaje cuando la cuenta de Google actual no tiene una suscripción ACTIVA y
/// PAGADA (se compró con otra cuenta, venció y no se renovó, o se canceló).
///
/// Es público para que la capa de UI (PaymentProvider/PaymentScreen) lo detecte
/// y ofrezca un camino accionable en lugar del genérico "Error de conexión".
const String kNoSubscriptionMessage =
    'No se encontró una suscripción activa en esta cuenta de Google Play.';
