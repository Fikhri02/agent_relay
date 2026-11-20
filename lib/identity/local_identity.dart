import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import '../crypto/identity_keys.dart';
import 'secret_store.dart';
import 'tls_cert_manager.dart';

/// This Mac: who runs it, its keys, and its TLS certificate.
class LocalIdentity {
  const LocalIdentity({
    required this.deviceId,
    required this.personName,
    required this.deviceName,
    required this.keys,
    required this.certPath,
    required this.keyPath,
    required this.certFingerprint,
  });

  final String deviceId;
  final String personName;
  final String deviceName;
  final IdentityKeys keys;
  final String certPath;
  final String keyPath;
  final String certFingerprint;

  static String _signKey(AppConfig c) => '${c.keychainPrefix}.signSeed';
  static String _boxKey(AppConfig c) => '${c.keychainPrefix}.boxSeed';
  static File _namesFile(AppConfig c) =>
      File('${c.dataDir.path}/identity.json');
  static Directory _tlsDir(AppConfig c) => Directory('${c.dataDir.path}/tls');

  /// Null until [create] has run for this config.
  static Future<LocalIdentity?> load(
    AppConfig config,
    SecretStore secrets,
  ) async {
    final String? signSeed;
    final String? boxSeed;
    try {
      signSeed = await secrets.read(_signKey(config));
      boxSeed = await secrets.read(_boxKey(config));
    } on Object catch (e) {
      throw KeychainException(e);
    }
    final names = _namesFile(config);
    final tls = _tlsDir(config);
    final certPath = '${tls.path}/cert.pem';
    final keyPath = '${tls.path}/key.pem';
    if (signSeed == null ||
        boxSeed == null ||
        !names.existsSync() ||
        !File(certPath).existsSync() ||
        !File(keyPath).existsSync()) {
      return null;
    }
    final keys = await IdentityKeys.fromSeeds(
      signSeed: base64.decode(signSeed),
      boxSeed: base64.decode(boxSeed),
    );
    final json = jsonDecode(await names.readAsString()) as Map<String, dynamic>;
    return LocalIdentity(
      deviceId: deviceIdFor(keys.signPub, keys.boxPub),
      personName: json['personName'] as String,
      deviceName: json['deviceName'] as String,
      keys: keys,
      certPath: certPath,
      keyPath: keyPath,
      certFingerprint: await TlsCertManager.computeFingerprint(certPath),
    );
  }

  static Future<LocalIdentity> create(
    AppConfig config,
    SecretStore secrets, {
    required String personName,
    required String deviceName,
    CertGenerator gen = TlsCertManager.generateCert,
  }) async {
    final keys = await IdentityKeys.generate();
    final seeds = await keys.seeds();
    try {
      await secrets.write(_signKey(config), base64.encode(seeds.signSeed));
      await secrets.write(_boxKey(config), base64.encode(seeds.boxSeed));
    } on Object catch (e) {
      throw KeychainException(e);
    }
    final tls = _tlsDir(config);
    await tls.create(recursive: true);
    final cert = await gen(tls.path);
    await _namesFile(config).writeAsString(
      jsonEncode({'personName': personName, 'deviceName': deviceName}),
    );
    return LocalIdentity(
      deviceId: deviceIdFor(keys.signPub, keys.boxPub),
      personName: personName,
      deviceName: deviceName,
      keys: keys,
      certPath: cert.certPath,
      keyPath: cert.keyPath,
      certFingerprint: cert.fingerprint,
    );
  }
}
