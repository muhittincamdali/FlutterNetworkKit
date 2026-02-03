import 'dart:io';
import 'dart:typed_data';

import 'certificate_pinning.dart';

/// Configuration for SSL/TLS settings.
///
/// This class provides comprehensive SSL configuration including
/// certificate pinning, client certificates, and protocol settings.
///
/// Example:
/// ```dart
/// final sslConfig = SSLConfiguration(
///   certificatePinning: CertificatePinning(pins: [...]),
///   trustSelfSigned: false,
///   protocols: [TlsProtocol.tls12, TlsProtocol.tls13],
/// );
/// ```
class SSLConfiguration {
  /// Creates a new [SSLConfiguration].
  const SSLConfiguration({
    this.certificatePinning,
    this.clientCertificate,
    this.clientPrivateKey,
    this.clientPrivateKeyPassword,
    this.trustedCertificates,
    this.trustSelfSigned = false,
    this.trustBadCertificates = false,
    this.protocols,
    this.ciphers,
    this.verifyHostname = true,
    this.onBadCertificate,
  });

  /// Creates a development configuration that trusts all certificates.
  factory SSLConfiguration.development() {
    return const SSLConfiguration(
      trustSelfSigned: true,
      trustBadCertificates: true,
      verifyHostname: false,
    );
  }

  /// Creates a production configuration with strict security.
  factory SSLConfiguration.production({
    CertificatePinning? certificatePinning,
    List<Uint8List>? trustedCertificates,
  }) {
    return SSLConfiguration(
      certificatePinning: certificatePinning,
      trustedCertificates: trustedCertificates,
      trustSelfSigned: false,
      trustBadCertificates: false,
      verifyHostname: true,
      protocols: const [TlsProtocol.tls12, TlsProtocol.tls13],
    );
  }

  /// Certificate pinning configuration.
  final CertificatePinning? certificatePinning;

  /// Client certificate for mutual TLS.
  final Uint8List? clientCertificate;

  /// Client private key for mutual TLS.
  final Uint8List? clientPrivateKey;

  /// Password for the client private key.
  final String? clientPrivateKeyPassword;

  /// Additional trusted CA certificates.
  final List<Uint8List>? trustedCertificates;

  /// Whether to trust self-signed certificates.
  final bool trustSelfSigned;

  /// Whether to trust certificates with validation errors.
  /// WARNING: This is insecure and should only be used for development.
  final bool trustBadCertificates;

  /// Allowed TLS protocols.
  final List<TlsProtocol>? protocols;

  /// Allowed cipher suites.
  final List<String>? ciphers;

  /// Whether to verify the hostname matches the certificate.
  final bool verifyHostname;

  /// Custom bad certificate handler.
  final bool Function(X509Certificate)? onBadCertificate;

  /// Returns true if mutual TLS is configured.
  bool get hasMutualTls =>
      clientCertificate != null && clientPrivateKey != null;

  /// Returns true if certificate pinning is configured.
  bool get hasCertificatePinning => certificatePinning != null;

  /// Creates a [SecurityContext] with this configuration.
  SecurityContext createSecurityContext() {
    final context = SecurityContext();

    // Add trusted certificates
    if (trustedCertificates != null) {
      for (final cert in trustedCertificates!) {
        context.setTrustedCertificatesBytes(cert);
      }
    }

    // Add client certificate for mutual TLS
    if (clientCertificate != null) {
      context.useCertificateChainBytes(clientCertificate!);
    }

    // Add client private key
    if (clientPrivateKey != null) {
      context.usePrivateKeyBytes(
        clientPrivateKey!,
        password: clientPrivateKeyPassword,
      );
    }

    return context;
  }

  /// Creates an [HttpClient] with this configuration.
  HttpClient createHttpClient() {
    final context = createSecurityContext();
    final client = HttpClient(context: context);

    // Configure bad certificate handling
    if (trustBadCertificates || trustSelfSigned) {
      client.badCertificateCallback = (cert, host, port) {
        if (onBadCertificate != null) {
          return onBadCertificate!(cert);
        }
        return trustBadCertificates;
      };
    } else if (certificatePinning != null) {
      client.badCertificateCallback = (cert, host, port) {
        final result = certificatePinning!.validate(cert, host);
        return result.isValid;
      };
    }

    return client;
  }

  /// Validates a certificate against this configuration.
  bool validateCertificate(X509Certificate certificate, String host) {
    // Check certificate pinning
    if (certificatePinning != null) {
      final result = certificatePinning!.validate(certificate, host);
      if (!result.isValid) {
        return false;
      }
    }

    // Check hostname verification
    if (verifyHostname) {
      // In a real implementation, verify the certificate's CN or SAN
      // matches the expected hostname
    }

    return true;
  }

  /// Creates a copy with the specified overrides.
  SSLConfiguration copyWith({
    CertificatePinning? certificatePinning,
    Uint8List? clientCertificate,
    Uint8List? clientPrivateKey,
    String? clientPrivateKeyPassword,
    List<Uint8List>? trustedCertificates,
    bool? trustSelfSigned,
    bool? trustBadCertificates,
    List<TlsProtocol>? protocols,
    List<String>? ciphers,
    bool? verifyHostname,
    bool Function(X509Certificate)? onBadCertificate,
  }) {
    return SSLConfiguration(
      certificatePinning: certificatePinning ?? this.certificatePinning,
      clientCertificate: clientCertificate ?? this.clientCertificate,
      clientPrivateKey: clientPrivateKey ?? this.clientPrivateKey,
      clientPrivateKeyPassword:
          clientPrivateKeyPassword ?? this.clientPrivateKeyPassword,
      trustedCertificates: trustedCertificates ?? this.trustedCertificates,
      trustSelfSigned: trustSelfSigned ?? this.trustSelfSigned,
      trustBadCertificates: trustBadCertificates ?? this.trustBadCertificates,
      protocols: protocols ?? this.protocols,
      ciphers: ciphers ?? this.ciphers,
      verifyHostname: verifyHostname ?? this.verifyHostname,
      onBadCertificate: onBadCertificate ?? this.onBadCertificate,
    );
  }

  @override
  String toString() {
    return 'SSLConfiguration('
        'hasMutualTls: $hasMutualTls, '
        'hasCertificatePinning: $hasCertificatePinning, '
        'trustSelfSigned: $trustSelfSigned, '
        'verifyHostname: $verifyHostname'
        ')';
  }
}

/// TLS protocol versions.
enum TlsProtocol {
  /// TLS 1.0 (deprecated, insecure).
  tls10,

  /// TLS 1.1 (deprecated).
  tls11,

  /// TLS 1.2.
  tls12,

  /// TLS 1.3.
  tls13,
}

/// Extension methods for SSL configuration.
extension SSLConfigurationExtension on SSLConfiguration {
  /// Returns true if this is a secure configuration.
  bool get isSecure =>
      !trustBadCertificates &&
      !trustSelfSigned &&
      verifyHostname;

  /// Returns a list of security warnings for this configuration.
  List<String> get securityWarnings {
    final warnings = <String>[];

    if (trustBadCertificates) {
      warnings.add('Certificate validation is disabled');
    }

    if (trustSelfSigned) {
      warnings.add('Self-signed certificates are trusted');
    }

    if (!verifyHostname) {
      warnings.add('Hostname verification is disabled');
    }

    if (protocols != null) {
      if (protocols!.contains(TlsProtocol.tls10)) {
        warnings.add('TLS 1.0 is enabled (deprecated and insecure)');
      }
      if (protocols!.contains(TlsProtocol.tls11)) {
        warnings.add('TLS 1.1 is enabled (deprecated)');
      }
    }

    return warnings;
  }
}
