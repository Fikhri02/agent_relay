import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../crypto/request_signer.dart';
import '../data/relay_database.dart';

const _publicPaths = {'/health'};
const signatureWindowMs = 30000;

/// Context key holding the verified [Peer] for a paired request.
const peerContextKey = 'peer';

/// Context key holding the signing key from the body of an unpaired
/// (pairing) request, already verified.
const unpairedSignPubKey = 'unpairedSignPub';

/// Every peer request carries `x-device-id`, `x-timestamp`, `x-signature`
/// (Ed25519 over [signingString]) and `x-relay-port`. Paired peers are checked
/// against their stored key; pairing paths against `signPub` in the body.
Middleware peerAuthMiddleware({
  required RelayDatabase db,
  required bool Function(String path) allowUnpaired,
  int Function()? nowMs,
  void Function(String deviceId)? onPeerSeen,
}) {
  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  return (inner) => (request) async {
    final path = '/${request.url.path}';
    if (_publicPaths.contains(path)) return inner(request);

    final deviceId = request.headers['x-device-id'];
    final ts = int.tryParse(request.headers['x-timestamp'] ?? '');
    final signature = request.headers['x-signature'];
    if (deviceId == null || ts == null || signature == null) {
      return _deny('missing_headers');
    }
    final now = clock();
    if ((now - ts).abs() > signatureWindowMs) {
      return _deny('clock_skew', {'serverTimeMs': now});
    }

    final body = await request.read().expand((c) => c).toList();
    final signed = signingString(
      method: request.method,
      path: path,
      timestampMs: ts,
      body: body,
    );
    final peer = await (db.select(
      db.peers,
    )..where((p) => p.deviceId.equals(deviceId))).getSingleOrNull();

    if (peer != null && peer.trust == 'paired') {
      if (!await verifyRequest(peer.signPub, signed, signature)) {
        return _deny('bad_signature');
      }
      final conn =
          request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final port = int.tryParse(request.headers['x-relay-port'] ?? '');
      await (db.update(
        db.peers,
      )..where((p) => p.deviceId.equals(deviceId))).write(
        PeersCompanion(
          lastSeenAt: Value(now),
          lastAddress: conn == null
              ? const Value.absent()
              : Value(conn.remoteAddress.address),
          lastPort: port == null ? const Value.absent() : Value(port),
        ),
      );
      onPeerSeen?.call(deviceId);
      final fresh = await (db.select(
        db.peers,
      )..where((p) => p.deviceId.equals(deviceId))).getSingle();
      return inner(
        request.change(
          body: Stream.value(body),
          context: {peerContextKey: fresh},
        ),
      );
    }

    if (!allowUnpaired(path)) return _deny('untrusted');
    final List<int> signPub;
    try {
      final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      signPub = base64.decode(json['signPub'] as String);
    } on Object {
      return _deny('untrusted');
    }
    if (!await verifyRequest(signPub, signed, signature)) {
      return _deny('bad_signature');
    }
    return inner(
      request.change(
        body: Stream.value(body),
        context: {unpairedSignPubKey: signPub},
      ),
    );
  };
}

Response _deny(String error, [Map<String, Object> extra = const {}]) =>
    Response(
      401,
      body: jsonEncode({'error': error, ...extra}),
      headers: {'content-type': 'application/json'},
    );
