import 'package:clock/clock.dart';

/// Service to check license expiry status.
///
/// Adapted from machote's LicenseService, simplified to work with
/// DateTime? directly instead of a UserProfile object.
class LicenseService {
  LicenseService._();

  /// Returns true if the license has expired.
  ///
  /// - If [licenseExpiry] is null, the license is considered perpetual (never expires).
  /// - If [licenseExpiry] is in the past, the license has expired.
  /// - If [licenseExpiry] is in the future, the license is still valid.
  static bool isLicenseExpired(DateTime? licenseExpiry) {
    if (licenseExpiry == null) return false; // perpetual license
    return clock.now().isAfter(licenseExpiry);
  }

  /// Returns the number of days remaining until expiry.
  /// Returns null if perpetual (no expiry).
  static int? daysRemaining(DateTime? licenseExpiry) {
    if (licenseExpiry == null) return null; // perpetual
    final diff = licenseExpiry.difference(clock.now());
    return diff.inDays > 0 ? diff.inDays : 0;
  }

  /// Returns a human-readable status string.
  static String licenseStatus(DateTime? licenseExpiry) {
    if (licenseExpiry == null) return 'Perpetua';
    if (isLicenseExpired(licenseExpiry)) return 'Expirada';
    final days = daysRemaining(licenseExpiry);
    if (days == null || days <= 0) return 'Expirada';
    if (days <= 7) return 'Por expirar ($days días)';
    return 'Vigente ($days días restantes)';
  }
}
