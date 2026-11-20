import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../peer/peer_server.dart';
import 'envelope.dart';
import 'message_service.dart';

/// Paired-peer routes for messages and receipts, plugged into [PeerServer].
Map<String, RouteHandler> relayRoutes(MessageService svc) => {
  // Keep-alive: the signed request itself marks the caller seen here, and
  // any answer tells the caller this Mac is up.
  '/relay/ping': (request, peer) async => _json(200, {'ok': true}),
  '/relay/deliver': (request, peer) async {
    final Envelope env;
    try {
      env = Envelope.fromJson(
        (jsonDecode(await request.readAsString()) as Map)
            .cast<String, dynamic>(),
      );
    } on Object {
      return _json(400, {'error': 'bad_envelope'});
    }
    try {
      final r = await svc.receive(env, from: peer);
      return _json(200, {'received': true, 'duplicate': r.duplicate});
    } on UntrustedSender {
      return _json(401, {'error': 'untrusted'});
    } on NotAMember {
      return _json(403, {'error': 'not_a_member'});
    }
  },
  '/relay/receipt': (request, peer) async {
    final Map<String, dynamic> body;
    try {
      body = (jsonDecode(await request.readAsString()) as Map)
          .cast<String, dynamic>();
    } on Object {
      return _json(400, {'error': 'bad_receipt'});
    }
    final ok = await svc.handleReceipt(body, from: peer);
    return ok
        ? _json(200, {'ok': true})
        : _json(404, {'error': 'unknown_message'});
  },
};

Response _json(int status, Map<String, Object?> body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
