// Adapted from gallery_bridge apps/macos/lib/core/server/tls_cert_manager.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

typedef CertResult = ({String certPath, String keyPath, String fingerprint});
typedef CertGenerator = Future<CertResult> Function(String outputDir);

class TlsCertManager {
  static Future<CertResult> generateCert(String outputDir) async {
    final certPath = '$outputDir/cert.pem';
    final keyPath = '$outputDir/key.pem';

    final result = await Process.run('/usr/bin/openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-keyout', keyPath, '-out',
      certPath, '-days', '3650', '-nodes', '-subj', '/CN=AgentRelay',
    ]);
    if (result.exitCode != 0) {
      throw Exception('openssl failed: ${result.stderr}');
    }
    return (
      certPath: certPath,
      keyPath: keyPath,
      fingerprint: await computeFingerprint(certPath),
    );
  }

  /// sha256 hex of the certificate's DER bytes.
  static Future<String> computeFingerprint(String certPath) async {
    final pem = await File(certPath).readAsString();
    final base64Body = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll('\n', '')
        .trim();
    return fingerprintOfDer(base64.decode(base64Body));
  }

  static String fingerprintOfDer(List<int> der) => sha256.convert(der).toString();
}
