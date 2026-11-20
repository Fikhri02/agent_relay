import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../peer/peer_server.dart';
import '../surat/surat_service.dart';
import 'envelope.dart';
import 'message_service.dart';

/// Peer routes for messages, receipts and (with [surat]) membership events,
/// plugged into [PeerServer].
Map<String, RouteHandler> relayRoutes(
  MessageService svc, {
  SuratService? surat,
}) => {
  // Keep-alive: the signed request itself marks the caller seen here, and
  // any answer tells the caller this Mac is up.
  '/relay/ping': (request, peer) async => _json(200, {'ok': true}),
  '/relay/deliver': (request, peer) async {
    final env = await _envelope(request);
    if (env == null) return _json(400, {'error': 'bad_envelope'});
    try {
      final r = await svc.receive(env, from: peer);
      return _json(200, {'received': true, 'duplicate': r.duplicate});
    } on BadEnvelope {
      return _json(400, {'error': 'bad_envelope'});
    } on UntrustedSender {
      return _json(401, {'error': 'untrusted'});
    } on ChannelClosed {
      // Not "untrusted": the sender must not read this as an unpair.
      return _json(409, {'error': 'channel_closed'});
    } on NotAMember {
      return _json(403, {'error': 'not_a_member'});
    }
  },
  if (surat != null)
    eventPath: (request, peer) async {
      final env = await _envelope(request);
      if (env == null) return _json(400, {'error': 'bad_envelope'});
      try {
        final r = await surat.receiveEvent(env, from: peer);
        return _json(200, {'received': true, 'duplicate': r.duplicate});
      } on BadEnvelope {
        return _json(400, {'error': 'bad_envelope'});
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

Future<Envelope?> _envelope(Request request) async {
  try {
    return Envelope.fromJson(
      (jsonDecode(await request.readAsString()) as Map).cast<String, dynamic>(),
    );
  } on Object {
    return null;
  }
}

Response _json(int status, Map<String, Object?> body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
