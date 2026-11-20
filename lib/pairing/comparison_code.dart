import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The 6-digit code both people compare. Built from both certificate
/// fingerprints, both key sets and both random nonces. The initiator commits
/// to its nonce before seeing the responder's, so a machine in the middle
/// cannot search for keys that make two different codes match.
String comparisonCode({
  required String fpA,
  required String fpB,
  required List<int> keysA,
  required List<int> keysB,
  required List<int> nonceA,
  required List<int> nonceB,
}) {
  final sides = [(fpA, keysA, nonceA), (fpB, keysB, nonceB)]
    ..sort((x, y) => x.$1.compareTo(y.$1));
  final bytes = <int>[
    for (final s in sides) ...[...utf8.encode(s.$1), ...s.$2, ...s.$3],
  ];
  final d = sha256.convert(bytes).bytes;
  final n = ((d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3]) & 0xFFFFFFFF;
  return (n % 1000000).toString().padLeft(6, '0');
}

/// What the initiator sends in hello instead of its nonce.
String commitmentOf(List<int> nonce) =>
    base64.encode(sha256.convert(nonce).bytes);

List<int> newNonce() {
  final r = Random.secure();
  return List<int>.generate(16, (_) => r.nextInt(256));
}

String privateChannelId(String deviceA, String deviceB) {
  final ids = [deviceA, deviceB]..sort();
  return sha256.convert(utf8.encode(ids.join(':'))).toString().substring(0, 32);
}
