import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

final _ed25519 = Ed25519();

/// Same layout as GalleryBridge's HmacSigner: method, path, time, body hash.
String signingString({
  required String method,
  required String path,
  required int timestampMs,
  required List<int> body,
}) => '$method\n$path\n$timestampMs\n${hash.sha256.convert(body)}';

Future<String> signRequest(SimpleKeyPair signing, String signingString) async {
  final sig = await _ed25519.sign(utf8.encode(signingString), keyPair: signing);
  return base64.encode(sig.bytes);
}

Future<bool> verifyRequest(
  List<int> signPub,
  String signingString,
  String signatureB64,
) async {
  try {
    return await _ed25519.verify(
      utf8.encode(signingString),
      signature: Signature(
        base64.decode(signatureB64),
        publicKey: SimplePublicKey(signPub, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}
