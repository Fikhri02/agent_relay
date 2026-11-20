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
      ..post('/pair/reveal', _reveal)
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
            allowUnpaired: (p) =>
                p == '/pair/hello' ||
                p == '/pair/reveal' ||
                p == '/pair/confirm',
            nowMs: nowMs,
            onPeerSeen: onPeerSeen,
          ),
        )
        .addHandler(router.call);
  }

  Future<Map<String, dynamic>?> _body(Request r) async {
    try {
      return (jsonDecode(await r.readAsString()) as Map)
          .cast<String, dynamic>();
    } on Object {
      return null;
    }
  }

  Future<Response> _hello(Request r) async {
    final body = await _body(r);
    if (body == null) return _json(400, {'error': 'bad_hello'});
    final conn = r.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final (status, reply) = await pairing.handleHello(
      body,
      conn?.remoteAddress.address ?? '127.0.0.1',
    );
    return _json(status, reply);
  }

  Future<Response> _reveal(Request r) async {
    final body = await _body(r);
    final signPub = r.context[unpairedSignPubKey] as List<int>?;
    if (body == null ||
        signPub == null ||
        body['nonce'] is! String ||
        body['deviceId'] is! String) {
      return _json(400, {'error': 'bad_reveal'});
    }
    final ok = await pairing.handleReveal(
      body['deviceId'] as String,
      signPub,
      base64.decode(body['nonce'] as String),
    );
    return ok ? _json(200, {'ok': true}) : _json(403, {'error': 'no_pairing'});
  }

  Future<Response> _confirm(Request r) async {
    final body = await _body(r);
    if (body == null || body['deviceId'] is! String) {
      return _json(400, {'error': 'bad_confirm'});
    }
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
