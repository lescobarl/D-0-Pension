import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../../core/models/result.dart';
import 'play_purchase_success.dart';
import 'play_purchase_verifier.dart';

// ---------------------------------------------------------------------------
// Timeout constants (from machote)
// ---------------------------------------------------------------------------
/// How long we wait for the store to emit *any* purchase update before
/// concluding the store is silent (e.g. no UI shown).
const _storeSilenceTimeout = Duration(seconds: 10);

/// How long we wait for the user to complete a purchase in the Play overlay
/// before timing out the entire operation.
const _pendingTimeout = Duration(seconds: 90);


/// How long we wait for a restore to complete.
const _restoreTimeout = Duration(seconds: 15);

// ---------------------------------------------------------------------------
// Product IDs (adjust when you publish on Play Console)
// ---------------------------------------------------------------------------
const String kProductIdAnnual = 'subscription_annual_ley73';
const String kProductIdPerpetual = 'license_perpetual_ley73';

// ---------------------------------------------------------------------------
// PlayBillingService
// ---------------------------------------------------------------------------

/// High-level service that wraps `in_app_purchase` and provides a
/// session-based purchase / restore API.
///
/// Ported from machote's `PlayBillingService` (~440 lines).
/// Adaptations:
///   - `dartz` `Either<Failure, PlayPurchaseSuccess>` → `Result<PlayPurchaseSuccess>`
///   - `Failure` → `String message` inside `Failure`
///   - All BLoC / cubit references removed.
class PlayBillingService {
  late final InAppPurchase _store;

  /// Whether the billing API is available on this device.
  bool _available = false;

  /// Currently active billing session (only one at a time).
  _BillingSession? _session;

  /// Latest product details fetched from the store.
  List<ProductDetails> _products = [];

  /// Whether we have already fetched products.
  bool get hasProducts => _products.isNotEmpty;

  /// The list of fetched products.
  List<ProductDetails> get products => List.unmodifiable(_products);

  /// Whether billing is available.
  bool get isAvailable => _available;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /// Initialise the service: check availability and fetch products.
  Future<Result<bool>> initialize() async {
    try {
      // Initialize lazily inside try/catch so web (which has no
      // in_app_purchase implementation) doesn't crash at construction time.
      _store = InAppPurchase.instance;
      _available = await _store.isAvailable();
      if (!_available) {
        return const Failure('Google Play Store no está disponible en este '
            'dispositivo.');
      }

      // Listen for purchase updates (must be done once).
      _store.purchaseStream.listen(_onPurchaseUpdated);

      // Fetch product details.
      final productIds = <String>{kProductIdAnnual, kProductIdPerpetual};
      final productResponse = await _store.queryProductDetails(productIds);

      if (productResponse.error != null) {
        return Failure('Error al consultar productos: '
            '${productResponse.error!.message}');
      }

      _products = productResponse.productDetails;
      return const Success(true);
    } catch (e) {
      return Failure('Error al inicializar Play Billing: $e');
    }
  }

  /// Dispose the service, cancelling any active session.
  void dispose() {
    _session?.cancel();
    _session = null;
  }

  // -----------------------------------------------------------------------
  // Purchase
  // -----------------------------------------------------------------------

  /// Purchase the annual subscription license.
  Future<Result<PlayPurchaseSuccess>> purchaseAnnualLicense() {
    return _runExclusive(
      _BillingSession(
        productId: kProductIdAnnual,
        operation: _BillingOperation.purchase,
        store: _store,
        products: _products,
      ),
    );
  }

  /// Purchase the perpetual license.
  Future<Result<PlayPurchaseSuccess>> purchasePerpetualLicense() {
    return _runExclusive(
      _BillingSession(
        productId: kProductIdPerpetual,
        operation: _BillingOperation.purchase,
        store: _store,
        products: _products,
      ),
    );
  }

  /// Restore an existing license.
  Future<Result<PlayPurchaseSuccess>> restoreAnnualLicense() {
    return _runExclusive(
      _BillingSession(
        productId: kProductIdAnnual,
        operation: _BillingOperation.restore,
        store: _store,
        products: _products,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Internal – exclusive session runner
  // -----------------------------------------------------------------------

  /// Runs a billing session exclusively – only one session at a time.
  Future<Result<PlayPurchaseSuccess>> _runExclusive(
      _BillingSession session) async {
    // Cancel any previous session.
    _session?.cancel();
    _session = session;

    final result = await session.result;
    _session = null;
    return result;
  }

  // -----------------------------------------------------------------------
  // Purchase stream handler
  // -----------------------------------------------------------------------

  /// Called whenever the store emits a purchase update.
  void _onPurchaseUpdated(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _handlePurchaseEvent(purchase);
      } else if (purchase.status == PurchaseStatus.error) {
        _handlePurchaseError(purchase);
      } else if (purchase.status == PurchaseStatus.canceled) {
        _session?.completeWithError('Compra cancelada por el usuario.');
      } else if (purchase.status == PurchaseStatus.pending) {
        // Still waiting for the user to complete the payment.
      }
    }
  }

  /// Handle a successful purchase event from the store.
  void _handlePurchaseEvent(PurchaseDetails purchase) {
    final session = _session;
    if (session == null) return;

    // Find the matching product details.
    final product = _products.where((p) => p.id == purchase.productID).firstOrNull;
    if (product == null) {
      session.completeWithError(
          'Producto no encontrado: ${purchase.productID}');
      return;
    }

    // Verify the purchase.
    final verification = PlayPurchaseVerifier.verifyPlayStorePurchase(
      product: product,
      purchase: purchase,
      expectedProductId: session.productId,
    );

    if (verification is Success<PlayPurchaseSuccess>) {
      _finalizeSuccessfulPurchase(session, purchase, verification.value);
    } else if (verification is Failure<PlayPurchaseSuccess>) {
      session.completeWithError(verification.message);
    } else {
      session.completeWithError('Verificación fallida');
    }
  }

  /// Handle a purchase error from the store.
  void _handlePurchaseError(PurchaseDetails purchase) {
    final session = _session;
    if (session == null) return;

    final error = purchase.error;
    if (error != null) {
      session.completeWithError(_mapStoreError(error));
    } else {
      session.completeWithError('Error desconocido en la compra.');
    }
  }

  /// Finalise a successful purchase: acknowledge it and complete the session.
  void _finalizeSuccessfulPurchase(
    _BillingSession session,
    PurchaseDetails purchase,
    PlayPurchaseSuccess verified,
  ) {
    // Acknowledge the purchase (required for subscriptions).
    if (purchase is GooglePlayPurchaseDetails) {
      _store.completePurchase(purchase);
    }

    session.completeWithSuccess(verified);
  }

  // -----------------------------------------------------------------------
  // Error mapping
  // -----------------------------------------------------------------------

  /// Map a [IAPError] to a user-friendly message.
  String _mapStoreError(IAPError error) {
    switch (error.code) {
      case 'userCancelled':
        return 'Compra cancelada.';
      case 'itemAlreadyOwned':
        return 'Ya posees esta licencia. Puedes restaurarla.';
      case 'itemUnavailable':
        return 'Producto no disponible en este momento.';
      case 'billingUnavailable':
        return 'Google Play no está disponible.';
      case 'developerError':
        return 'Error de configuración. Contacta al soporte.';
      case 'networkError':
        return 'Error de red. Verifica tu conexión.';
      case 'serviceDisconnected':
        return 'Servicio de facturación desconectado.';
      case 'serviceTimeout':
        return 'Tiempo de espera agotado. Intenta de nuevo.';
      default:
        return 'Error: ${error.message}';
    }
  }
}

// ---------------------------------------------------------------------------
// Billing session
// ---------------------------------------------------------------------------

enum _BillingOperation { purchase, restore }

/// A single billing operation session with timeout management.
///
/// Ported from machote's `_BillingSession` which used `Completer<Either<…>>`.
class _BillingSession {
  final String productId;
  final _BillingOperation operation;
  final InAppPurchase store;
  final List<ProductDetails> products;

  late final Completer<Result<PlayPurchaseSuccess>> _completer;
  Timer? _pendingTimer;
  Timer? _storeSilenceTimer;

  _BillingSession({
    required this.productId,
    required this.operation,
    required this.store,
    required this.products,
  }) {
    _completer = Completer<Result<PlayPurchaseSuccess>>();
    _startTimers();
    _startOperation();
  }

  /// The future that completes when the session finishes.
  Future<Result<PlayPurchaseSuccess>> get result => _completer.future;

  /// Start the store silence watch and pending timeout.
  void _startTimers() {
    // If the store doesn't emit anything within the silence timeout,
    // we assume the purchase UI wasn't shown.
    _storeSilenceTimer = Timer(_storeSilenceTimeout, () {
      if (!_completer.isCompleted) {
        _completer.complete(
          const Failure(
            'La tienda no respondió. Verifica que Google Play esté configurado '
            'correctamente.',
          ),
        );
      }
    });

    // Overall pending timeout.
    final timeout = operation == _BillingOperation.restore
        ? _restoreTimeout
        : _pendingTimeout;
    _pendingTimer = Timer(timeout, () {
      if (!_completer.isCompleted) {
        _completer.complete(
          const Failure('La operación tardó demasiado. Intenta de nuevo.'),
        );
      }
    });
  }

  /// Start the actual store operation.
  void _startOperation() {
    switch (operation) {
      case _BillingOperation.purchase:
        _startPurchase();
      case _BillingOperation.restore:
        _startRestore();
    }
  }

  void _startPurchase() {
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      _completer.complete(
        Failure('Producto no encontrado: $productId'),
      );
      return;
    }

    // Cancel silence timer – the store responded.
    _storeSilenceTimer?.cancel();

    final purchaseParam = PurchaseParam(productDetails: product);
    store.buyNonConsumable(purchaseParam: purchaseParam);
  }

  void _startRestore() {
    // Cancel silence timer – we're initiating the restore.
    _storeSilenceTimer?.cancel();
    store.restorePurchases();
  }

  /// Complete the session with a successful result.
  void completeWithSuccess(PlayPurchaseSuccess success) {
    _cancelTimers();
    if (!_completer.isCompleted) {
      _completer.complete(Success(success));
    }
  }

  /// Complete the session with an error message.
  void completeWithError(String message) {
    _cancelTimers();
    if (!_completer.isCompleted) {
      _completer.complete(Failure(message));
    }
  }

  /// Cancel the session entirely.
  void cancel() {
    _cancelTimers();
    if (!_completer.isCompleted) {
      _completer.complete(
        const Failure('Operación cancelada.'),
      );
    }
  }

  void _cancelTimers() {
    _storeSilenceTimer?.cancel();
    _pendingTimer?.cancel();
  }
}
