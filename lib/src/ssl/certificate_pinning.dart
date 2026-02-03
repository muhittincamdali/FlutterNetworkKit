import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Configuration for SSL certificate pinning.
///
/// Certificate pinning prevents man-in-the-middle attacks by validating
/// that the server's certificate matches a known good certificate.
///
/// Example:
/// ```dart
/// final pinning = CertificatePinning(
///   pins: [
///     CertificatePin(
///       host: 'api.example.com',
///       sha256Hashes: [
///         'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
///       ],
///     ),
///   ],
/// );
/// ```
class CertificatePinning {
  /// Creates a new [CertificatePinning] configuration.
  CertificatePinning({
    required this.pins,
    this.includeSubdomains = false,
    this.reportUri,
    this.reportOnly = false,
    this.maxAge = const Duration(days: 30),
  });

  /// The list of certificate pins.
  final List<CertificatePin> pins;

  /// Whether to include subdomains in the pinning.
  final bool includeSubdomains;

  /// URI to report pin validation failures.
  final String? reportUri;

  /// If true, only report failures without blocking connections.
  final bool reportOnly;

  /// How long the pins are valid.
  final Duration maxAge;

  /// Validates a certificate chain against the configured pins.
  ///
  /// Returns a [PinValidationResult] indicating success or failure.
  PinValidationResult validate(
    X509Certificate certificate,
    String host,
  ) {
    // Find matching pin configuration
    final pin = _findPinForHost(host);
    if (pin == null) {
      return PinValidationResult.noPinConfigured(host);
    }

    // Calculate certificate hash
    final certHash = _calculateHash(certificate);

    // Check if hash matches any pin
    for (final expectedHash in pin.sha256Hashes) {
      if (certHash == expectedHash) {
        return PinValidationResult.success(host, certHash);
      }
    }

    // No match found
    final result = PinValidationResult.failure(
      host,
      certHash,
      pin.sha256Hashes,
    );

    // Report failure if configured
    if (reportUri != null) {
      _reportPinFailure(result);
    }

    // In report-only mode, return success anyway
    if (reportOnly) {
      return PinValidationResult.success(host, certHash);
    }

    return result;
  }

  /// Validates an entire certificate chain.
  PinValidationResult validateChain(
    List<X509Certificate> chain,
    String host,
  ) {
    for (final cert in chain) {
      final result = validate(cert, host);
      if (result.isValid) {
        return result;
      }
    }

    // If no certificate in the chain matched, return failure
    if (chain.isEmpty) {
      return PinValidationResult.failure(host, '', []);
    }

    return validate(chain.first, host);
  }

  CertificatePin? _findPinForHost(String host) {
    // Exact match
    for (final pin in pins) {
      if (pin.host == host) {
        return pin;
      }
    }

    // Subdomain match
    if (includeSubdomains) {
      for (final pin in pins) {
        if (host.endsWith('.${pin.host}')) {
          return pin;
        }
      }
    }

    // Wildcard match
    for (final pin in pins) {
      if (pin.host.startsWith('*.')) {
        final pattern = pin.host.substring(2);
        if (host.endsWith(pattern) || host == pattern) {
          return pin;
        }
      }
    }

    return null;
  }

  String _calculateHash(X509Certificate certificate) {
    final der = certificate.der;
    final digest = sha256.convert(der);
    return 'sha256/${base64.encode(digest.bytes)}';
  }

  void _reportPinFailure(PinValidationResult result) {
    // In a production implementation, this would send a report
    // to the configured reportUri
  }

  /// Creates a security context with certificate pinning.
  SecurityContext createSecurityContext() {
    final context = SecurityContext();

    // Add trusted certificates if provided
    for (final pin in pins) {
      if (pin.certificateData != null) {
        context.setTrustedCertificatesBytes(pin.certificateData!);
      }
    }

    return context;
  }

  /// Returns HTTP Public Key Pinning (HPKP) header value.
  String toHpkpHeader() {
    final parts = <String>[];

    for (final pin in pins) {
      for (final hash in pin.sha256Hashes) {
        parts.add('pin-$hash');
      }
    }

    parts.add('max-age=${maxAge.inSeconds}');

    if (includeSubdomains) {
      parts.add('includeSubDomains');
    }

    if (reportUri != null) {
      parts.add('report-uri="$reportUri"');
    }

    return parts.join('; ');
  }

  @override
  String toString() {
    return 'CertificatePinning('
        'pins: ${pins.length}, '
        'includeSubdomains: $includeSubdomains, '
        'reportOnly: $reportOnly'
        ')';
  }
}

/// A single certificate pin configuration.
class CertificatePin {
  /// Creates a new [CertificatePin].
  const CertificatePin({
    required this.host,
    required this.sha256Hashes,
    this.certificateData,
    this.expiresAt,
  });

  /// Creates a [CertificatePin] from a PEM-encoded certificate.
  factory CertificatePin.fromPem(String host, String pem) {
    final hash = _hashFromPem(pem);
    return CertificatePin(
      host: host,
      sha256Hashes: [hash],
      certificateData: utf8.encode(pem),
    );
  }

  /// The hostname this pin applies to.
  final String host;

  /// SHA-256 hashes of the certificate's Subject Public Key Info.
  final List<String> sha256Hashes;

  /// Raw certificate data for verification.
  final Uint8List? certificateData;

  /// When this pin expires.
  final DateTime? expiresAt;

  /// Returns true if this pin has expired.
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  static String _hashFromPem(String pem) {
    // Extract DER from PEM
    final lines = pem.split('\n')
        .where((line) => !line.startsWith('-----'))
        .join();
    final der = base64.decode(lines);
    final digest = sha256.convert(der);
    return 'sha256/${base64.encode(digest.bytes)}';
  }

  @override
  String toString() => 'CertificatePin(host: $host, hashes: ${sha256Hashes.length})';
}

/// Result of certificate pin validation.
class PinValidationResult {
  const PinValidationResult._({
    required this.host,
    required this.isValid,
    this.actualHash,
    this.expectedHashes,
    this.message,
  });

  /// Creates a successful validation result.
  factory PinValidationResult.success(String host, String hash) {
    return PinValidationResult._(
      host: host,
      isValid: true,
      actualHash: hash,
      message: 'Certificate pin validation successful',
    );
  }

  /// Creates a failed validation result.
  factory PinValidationResult.failure(
    String host,
    String actualHash,
    List<String> expectedHashes,
  ) {
    return PinValidationResult._(
      host: host,
      isValid: false,
      actualHash: actualHash,
      expectedHashes: expectedHashes,
      message: 'Certificate hash does not match any pinned certificates',
    );
  }

  /// Creates a result when no pin is configured for the host.
  factory PinValidationResult.noPinConfigured(String host) {
    return PinValidationResult._(
      host: host,
      isValid: true,
      message: 'No certificate pin configured for host',
    );
  }

  /// The hostname that was validated.
  final String host;

  /// Whether the validation was successful.
  final bool isValid;

  /// The actual hash of the certificate.
  final String? actualHash;

  /// The expected hashes from the pin configuration.
  final List<String>? expectedHashes;

  /// A human-readable message describing the result.
  final String? message;

  @override
  String toString() {
    return 'PinValidationResult('
        'host: $host, '
        'isValid: $isValid, '
        'message: $message'
        ')';
  }
}

/// Builder for creating certificate pinning configurations.
class CertificatePinningBuilder {
  final List<CertificatePin> _pins = [];
  bool _includeSubdomains = false;
  String? _reportUri;
  bool _reportOnly = false;
  Duration _maxAge = const Duration(days: 30);

  /// Adds a pin for a host with SHA-256 hashes.
  CertificatePinningBuilder addPin(String host, List<String> sha256Hashes) {
    _pins.add(CertificatePin(host: host, sha256Hashes: sha256Hashes));
    return this;
  }

  /// Adds a pin from a PEM certificate.
  CertificatePinningBuilder addPemPin(String host, String pem) {
    _pins.add(CertificatePin.fromPem(host, pem));
    return this;
  }

  /// Includes subdomains in the pinning.
  CertificatePinningBuilder includeSubdomains([bool include = true]) {
    _includeSubdomains = include;
    return this;
  }

  /// Sets the report URI for pin failures.
  CertificatePinningBuilder reportTo(String uri) {
    _reportUri = uri;
    return this;
  }

  /// Enables report-only mode.
  CertificatePinningBuilder reportOnlyMode([bool reportOnly = true]) {
    _reportOnly = reportOnly;
    return this;
  }

  /// Sets the maximum age for the pins.
  CertificatePinningBuilder maxAge(Duration duration) {
    _maxAge = duration;
    return this;
  }

  /// Builds the certificate pinning configuration.
  CertificatePinning build() {
    return CertificatePinning(
      pins: _pins,
      includeSubdomains: _includeSubdomains,
      reportUri: _reportUri,
      reportOnly: _reportOnly,
      maxAge: _maxAge,
    );
  }
}
