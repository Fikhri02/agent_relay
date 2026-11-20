import 'dart:convert';

import 'package:cryptography/cryptography.dart';

final _x25519 = X25519();
final _aead = Chacha20.poly1305Aead();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final _info = utf8.encode('agent-relay-v1 seal');

class SealOpenException implements Exception {
  const SealOpenException(this.cause);
  final Object cause;
  @override
  String toString() => "couldn't open sealed message: $cause";
}

/// One message encrypted for one recipient. All fields base64.
class SealedEnvelope {
  const SealedEnvelope({
    required this.eph,
    required this.nonce,
    required this.ct,
    required this.mac,
  });

  final String eph;
  final String nonce;
  final String ct;
  final String mac;

  Map<String, dynamic> toJson() => {
    'eph': eph,
    'nonce': nonce,
    'ct': ct,
    'mac': mac,
  };

  factory SealedEnvelope.fromJson(Map<String, dynamic> json) => SealedEnvelope(
    eph: json['eph'] as String,
    nonce: json['nonce'] as String,
    ct: json['ct'] as String,
    mac: json['mac'] as String,
  );
}

Future<SecretKey> _key(
  SecretKey shared,
  List<int> ephPub,
  List<int> recipPub,
) => _hkdf.deriveKey(
  secretKey: shared,
  nonce: [...ephPub, ...recipPub],
  info: _info,
);

/// Ephemeral X25519 + HKDF-SHA256 + ChaCha20-Poly1305, sealed-box style.
Future<SealedEnvelope> seal(
  List<int> plaintext, {
  required List<int> recipientBoxPub,
  required List<int> aad,
}) async {
  final eph = await _x25519.newKeyPair();
  final ephPub = (await eph.extractPublicKey()).bytes;
  final shared = await _x25519.sharedSecretKey(
    keyPair: eph,
    remotePublicKey: SimplePublicKey(recipientBoxPub, type: KeyPairType.x25519),
  );
  final key = await _key(shared, ephPub, recipientBoxPub);
  final box = await _aead.encrypt(
    plaintext,
    secretKey: key,
    nonce: _aead.newNonce(),
    aad: aad,
  );
  return SealedEnvelope(
    eph: base64.encode(ephPub),
    nonce: base64.encode(box.nonce),
    ct: base64.encode(box.cipherText),
    mac: base64.encode(box.mac.bytes),
  );
}

Future<List<int>> open(
  SealedEnvelope e, {
  required SimpleKeyPair recipientBox,
  required List<int> aad,
}) async {
  try {
    final ephPub = base64.decode(e.eph);
    final recipPub = (await recipientBox.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(
      keyPair: recipientBox,
      remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519),
    );
    final key = await _key(shared, ephPub, recipPub);
    return await _aead.decrypt(
      SecretBox(
        base64.decode(e.ct),
        nonce: base64.decode(e.nonce),
        mac: Mac(base64.decode(e.mac)),
      ),
      secretKey: key,
      aad: aad,
    );
  } catch (err) {
    throw SealOpenException(err);
  }
}
