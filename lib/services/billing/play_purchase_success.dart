import 'package:in_app_purchase/in_app_purchase.dart';

/// Represents a successfully verified Play Store purchase.
class PlayPurchaseSuccess {
  const PlayPurchaseSuccess({
    required this.product,
    required this.verifiedProductId,
    this.purchaseToken,
    this.transactionId,
  });

  /// The original [ProductDetails] from the Play Store.
  final ProductDetails product;

  /// The verified product ID after cross-checking.
  final String verifiedProductId;

  /// The purchase token for server-side verification.
  final String? purchaseToken;

  /// The transaction ID (Google Order ID).
  final String? transactionId;

  @override
  String toString() =>
      'PlayPurchaseSuccess(productId: $verifiedProductId, token: $purchaseToken)';
}
