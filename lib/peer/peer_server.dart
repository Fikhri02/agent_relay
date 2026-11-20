import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../data/relay_database.dart';
import '../pairing/pairing_service.dart';
import 'peer_auth_middleware.dart';

typedef RouteHandler = Future<Response> Function(Request request, Peer peer);

/// The LAN API other Macs call. Routes beyond pairing are added by later
/// layers through [paired].
class PeerServer {
  PeerServer({
    required this.db,
    required this.pairing,
    this.paired = const {},
    this.nowMs,
    this.onPeerSeen,
  });

  final RelayDatabase db;
  final PairingService pairing;

  /// Extra POST routes for paired peers, keyed by path (e.g. `/relay/deliver`).
  final Map<String, RouteHandler> paired;
  final int Function()? nowMs;
  final void Function(String deviceId)? onPeerSeen;

  Handler get handler {
    final router = Router()
      ..get('/health', (Request _) => _json(200, {'ok': true}))
      ..post('/pair/hello', _hello)
      ..post('/pair/confirm', _confirm)
      ..post('/pair/unpair', _unpair);
    for (final entry in paired.entries) {
      router.post(entry.key, (Request r) {
        final peer = r.context[peerContextKey] as Peer?;
        if (peer == null) return _json(401, {'error': 'untrusted'});
        return entry.value(r, peer);
      });
    }
    return const Pipeline()
        .addMiddleware(
          peerAuthMiddleware(
            db: db,
            allowUnpaired: (p) => p == '/pair/hello' || p == '/pair/confirm',
            nowMs: nowMs,
            onPeerSeen: onPeerSeen,
          ),
        )
        .addHandler(router.call);
  }

  Future<Response> _hello(Request r) async {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final conn = r.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final reply = await pairing.handleHello(
      body,
      conn?.remoteAddress.address ?? '127.0.0.1',
    );
    if (reply == null) return _json(403, {'error': 'pairing_closed'});
    return _json(200, reply);
  }

  Future<Response> _confirm(Request r) async {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final signPub =
        (r.context[unpairedSignPubKey] as List<int>?) ??
        (r.context[peerContextKey] as Peer?)?.signPub;
    if (signPub == null) return _json(401, {'error': 'untrusted'});
    final ok = await pairing.handleConfirm(body['deviceId'] as String, signPub);
    return ok ? _json(200, {'ok': true}) : _json(403, {'error': 'no_pairing'});
  }

  Future<Response> _unpair(Request r) async {
    final peer = r.context[peerContextKey] as Peer?;
    if (peer == null) return _json(401, {'error': 'untrusted'});
    await pairing.markUnpaired(peer.deviceId);
    return _json(200, {'ok': true});
  }
}

Response _json(int status, Map<String, Object?> body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
