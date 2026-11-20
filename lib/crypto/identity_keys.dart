import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

final _ed25519 = Ed25519();
final _x25519 = X25519();

/// A device's long-term keys: Ed25519 to sign, X25519 to receive sealed
/// messages. Both are rebuilt from 32-byte seeds kept in the Keychain.
class IdentityKeys {
  IdentityKeys._(this.signing, this.box, this.signPub, this.boxPub);

  final SimpleKeyPair signing;
  final SimpleKeyPair box;
  final List<int> signPub;
  final List<int> boxPub;

  static Future<IdentityKeys> generate() async {
    final signing = await _ed25519.newKeyPair();
    final box = await _x25519.newKeyPair();
    return _from(signing, box);
  }

  static Future<IdentityKeys> fromSeeds({
    required List<int> signSeed,
    required List<int> boxSeed,
  }) async {
    final signing = await _ed25519.newKeyPairFromSeed(signSeed);
    final box = await _x25519.newKeyPairFromSeed(boxSeed);
    return _from(signing, box);
  }

  static Future<IdentityKeys> _from(
    SimpleKeyPair signing,
    SimpleKeyPair box,
  ) async {
    final signPub = (await signing.extractPublicKey()).bytes;
    final boxPub = (await box.extractPublicKey()).bytes;
    return IdentityKeys._(signing, box, signPub, boxPub);
  }

  Future<({List<int> signSeed, List<int> boxSeed})> seeds() async => (
    signSeed: await signing.extractPrivateKeyBytes(),
    boxSeed: await box.extractPrivateKeyBytes(),
  );
}

/// Lowercase hex of sha256(signPub ‖ boxPub), first 32 chars.
String deviceIdFor(List<int> signPub, List<int> boxPub) =>
    hash.sha256.convert([...signPub, ...boxPub]).toString().substring(0, 32);
