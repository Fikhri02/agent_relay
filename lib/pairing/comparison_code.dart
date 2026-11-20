import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The 6-digit code both people compare. Built from both certificate
/// fingerprints and both key sets, so a machine in the middle changes it.
String comparisonCode({
  required String fpA,
  required String fpB,
  required List<int> keysA,
  required List<int> keysB,
}) {
  final pairs = [(fpA, keysA), (fpB, keysB)]
    ..sort((x, y) => x.$1.compareTo(y.$1));
  final bytes = <int>[
    for (final p in pairs) ...[...utf8.encode(p.$1), ...p.$2],
  ];
  final d = sha256.convert(bytes).bytes;
  final n = ((d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3]) & 0xFFFFFFFF;
  return (n % 1000000).toString().padLeft(6, '0');
}

String privateChannelId(String deviceA, String deviceB) {
  final ids = [deviceA, deviceB]..sort();
  return sha256.convert(utf8.encode(ids.join(':'))).toString().substring(0, 32);
}
