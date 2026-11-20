// Adapted from gallery_bridge apps/macos/lib/core/identity/mac_identity_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class KeychainException implements Exception {
  const KeychainException(this.cause);
  final Object cause;
  @override
  String toString() => "couldn't use the Keychain: $cause";
}

/// macOS Keychain. The data-protection keychain needs an entitlement an
/// unsigned build lacks, so the login keychain is used.
class KeychainSecretStore implements SecretStore {
  const KeychainSecretStore();

  static const options = MacOsOptions(useDataProtectionKeyChain: false);
  static const _storage = FlutterSecureStorage(mOptions: options);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class InMemorySecretStore implements SecretStore {
  final _values = <String, String>{};

  Iterable<String> get keys => _values.keys;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
