import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../../core/models/result.dart';
import 'play_purchase_success.dart';

/// Verifies Play Store purchase and restore responses.
///
/// Cross-checks product IDs, purchase status, tokens, and source.
/// Adapted from machote's verifier, replacing `dartz` with [Result].
class PlayPurchaseVerifier {
  PlayPurchaseVerifier._();

  /// Verify a fresh purchase made through the billing flow.
  static Result<PlayPurchaseSuccess> verifyPlayStorePurchase({
    required ProductDetails product,
    required PurchaseDetails purchase,
    required String expectedProductId,
  }) {
    return _verifyCommon(
      product: product,
      purchase: purchase,
      expectedProductId: expectedProductId,
    );
  }

  /// Verify a restored purchase (from existing purchases list).
  static Result<PlayPurchaseSuccess> verifyPlayStoreRestore({
    required ProductDetails product,
    required PurchaseDetails purchase,
    required String expectedProductId,
  }) {
    return _verifyCommon(
      product: product,
      purchase: purchase,
      expectedProductId: expectedProductId,
    );
  }

  /// Common verification logic for both purchase and restore.
  static Result<PlayPurchaseSuccess> _verifyCommon({
    required ProductDetails product,
    required PurchaseDetails purchase,
    required String expectedProductId,
  }) {
    // 1. Verify product ID matches
    if (purchase.productID != expectedProductId) {
      return Failure<PlayPurchaseSuccess>(
        'Product ID mismatch: expected $expectedProductId, got ${purchase.productID}',
      );
    }

    // 2. Verify purchase status
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return Failure<PlayPurchaseSuccess>(
        'Purchase not completed: status=${purchase.status}',
      );
    }

    // 3. Verify purchase token is not empty
    final token = _extractPurchaseToken(purchase);
    if (token == null || token.isEmpty) {
      return Failure<PlayPurchaseSuccess>(
        'Purchase token is empty or missing',
      );
    }

    // 4. Verify source is Google Play
    if (purchase.verificationData.source != 'google_play') {
      return Failure<PlayPurchaseSuccess>(
        'Invalid source: ${purchase.verificationData.source}',
      );
    }

    // 5. For Android, verify PurchaseState is purchased
    if (purchase is GooglePlayPurchaseDetails) {
      final gpPurchase = purchase; // type is already narrowed
      if (gpPurchase.billingClientPurchase.purchaseState !=
          PurchaseStateWrapper.purchased) {
        return Failure<PlayPurchaseSuccess>(
          'Android purchase state is not purchased: '
          '${gpPurchase.billingClientPurchase.purchaseState}',
        );
      }
    }

    return Success(
      PlayPurchaseSuccess(
        product: product,
        verifiedProductId: expectedProductId,
        purchaseToken: token,
        transactionId: _extractTransactionId(purchase),
      ),
    );
  }

  /// Extract the purchase token from a [PurchaseDetails].
  static String? _extractPurchaseToken(PurchaseDetails purchase) {
    if (purchase is GooglePlayPurchaseDetails) {
      return purchase.billingClientPurchase.purchaseToken;
    }
    // For iOS/other platforms, use the verification data
    return purchase.verificationData.localVerificationData;
  }

  /// Extract the transaction/order ID.
  static String? _extractTransactionId(PurchaseDetails purchase) {
    if (purchase is GooglePlayPurchaseDetails) {
      return purchase.billingClientPurchase.orderId;
    }
    return null;
  }
}
