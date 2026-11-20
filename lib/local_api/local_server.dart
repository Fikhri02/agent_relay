import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../data/relay_database.dart';
import '../messaging/message_service.dart';
import '../surat/surat_service.dart';
import 'surat_routes.dart';

/// The app version GET /status reports; keep it equal to pubspec's version
/// name (a test checks).
const appVersion = '1.1.0';
const reachableWithinMs = 120000;

typedef LocalMe = ({String deviceId, String personName, String deviceName});

/// The API the `inbox` skill calls. Loopback only; every request carries the
/// bearer token from `local-token` (mode 0600, rewritten on each start).
/// Reads through this API count as the agent reading.
class LocalServer {
  LocalServer({
    required this.config,
    required this.db,
    required this.messages,
    required this.surat,
    required this.me,
    this.deliverNow,
    this.deliverWait = const Duration(seconds: 5),
    int Function()? nowMs,
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _surat = SuratRoutes(db: db, surat: surat, meDeviceId: me.deviceId);

  /// Runs one delivery pass. Approve calls it so the reply says what
  /// happened ("sent" or still queued) instead of guessing from last contact.
  final Future<void> Function()? deliverNow;

  /// How long approve waits for that pass before answering.
  final Duration deliverWait;

  final AppConfig config;
  final RelayDatabase db;
  final MessageService messages;
  final SuratService surat;
  final LocalMe me;
  final SuratRoutes _surat;
  final int Function() _now;
  late String _token;
  HttpServer? _server;

  InternetAddress? get address => _server?.address;
  int get boundPort => _server?.port ?? 0;

  Future<void> start() async {
    await config.dataDir.create(recursive: true);
    final random = Random.secure();
    _token = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final file = File('${config.dataDir.path}/local-token');
    await file.writeAsString(_token);
    await Process.run('/bin/chmod', ['600', file.path]);
    _server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      config.localPort,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Handler get handler {
    final r = Router()
      ..get(
        '/status',
        (Request _) => _ok({
          'deviceId': me.deviceId,
          'personName': me.personName,
          'deviceName': me.deviceName,
          'version': appVersion,
        }),
      )
      ..get('/peers', _peers)
      ..get('/channels', _channels)
      ..get('/channels/<id>/messages', _messages)
      ..post('/channels/<id>/send', _send)
      ..get('/outbox', _outbox)
      ..post('/outbox/<id>/approve', _approve)
      ..post('/outbox/<id>/discard', _discard);
    _surat.mount(r);
    return (Request req) {
      final auth = req.headers['authorization'] ?? '';
      if (auth != 'Bearer $_token') {
        return _json(401, {'error': 'unauthorized'});
      }
      return r.call(req);
    };
  }

  bool _reachable(Peer p) =>
      p.lastSeenAt != null && _now() - p.lastSeenAt! <= reachableWithinMs;

  Future<Response> _peers(Request _) async {
    final peers = await (db.select(
      db.peers,
    )..where((p) => p.trust.equals('paired'))).get();
    return _ok([
      for (final p in peers)
        {
          'deviceId': p.deviceId,
          'personName': p.personName,
          'deviceName': p.deviceName,
          'trust': p.trust,
          'reachable': _reachable(p),
          'clockSkewMs': p.clockSkewMs,
        },
    ]);
  }

  Future<Map<String, Peer>> _peerMap() async => {
    for (final p in await db.select(db.peers).get()) p.deviceId: p,
  };

  Future<Response> _channels(Request _) async {
    final peers = await _peerMap();
    // The local API is the agent's view: unread means not read by the agent,
    // even if the person already opened it in the app.
    final unread = await db.unreadCounts(by: Reader.agent);
    final pending = await _surat.pendingCounts();
    final out = <Map<String, Object?>>[];
    for (final c in await db.select(db.channels).get()) {
      final members = await (db.select(
        db.channelMembers,
      )..where((m) => m.channelId.equals(c.id))).get();
      final other = c.kind == 'private'
          ? peers[members
                .map((m) => m.deviceId)
                .firstWhere((id) => id != me.deviceId, orElse: () => '')]
          : null;
      out.add({
        'id': c.id,
        'kind': c.kind,
        'name': c.name ?? other?.personName ?? 'Unknown',
        if (other != null)
          'peer': {
            'deviceId': other.deviceId,
            'personName': other.personName,
            'deviceName': other.deviceName,
          },
        'unread': unread[c.id] ?? 0,
        'closed': c.closedAt != null,
        if (c.kind == 'surat')
          ..._surat.channelFields(c, members, peers, pending[c.id] ?? 0),
      });
    }
    return _ok(out);
  }

  Future<Response> _messages(Request req, String id) async {
    final unreadOnly = req.url.queryParameters['status'] == 'unread';
    final peers = await _peerMap();
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    final inSurat = channel?.kind == 'surat';
    final members = inSurat
        ? await (db.select(
            db.channelMembers,
          )..where((m) => m.channelId.equals(id))).get()
        : const <ChannelMember>[];
    final memberNames = inSurat ? await _surat.memberNames(id) : const {};
    String nameOf(String deviceId) => deviceId == me.deviceId
        ? me.personName
        : peers[deviceId]?.personName ?? memberNames[deviceId] ?? 'Unknown';
    final list = await messages.read(
      id,
      unreadOnly: unreadOnly,
      by: Reader.agent,
    );
    final out = <Map<String, Object?>>[];
    for (final m in list) {
      out.add({
        'id': m.id,
        'channelId': m.channelId,
        'kind': m.kind,
        'direction': m.direction,
        'from': {
          'deviceId': m.fromDeviceId,
          'personName': nameOf(m.fromDeviceId),
        },
        'sentAt': m.sentAt,
        'hlc': m.hlc,
        'body': m.kind == 'event' ? await _surat.eventBody(m, peers) : m.body,
        'context': m.contextJson == null ? null : jsonDecode(m.contextJson!),
        'replyTo': m.replyTo,
        'status': m.status,
        if (inSurat && m.status == 'locked')
          'lockedReason': _surat.lockedReason(members, m.fromDeviceId),
        'arrivedLate': m.arrivedLate,
        if (m.direction == 'out')
          'receipts': [
            for (final r in await messages.receiptsFor(m.id))
              {
                'personName': r.personName,
                'deliveredAt': r.deliveredAt,
                'seenAt': r.seenAt,
                'agentReadAt': r.agentReadAt,
              },
          ],
      });
    }
    final gaps = [
      for (final g in await db.gaps(id))
        {'personName': nameOf(g.fromDeviceId), 'missing': g.missing},
    ];
    return _ok({'messages': out, 'gaps': gaps});
  }

  Future<Response> _send(Request req, String id) async {
    final Map<String, dynamic> body;
    try {
      body = (jsonDecode(await req.readAsString()) as Map)
          .cast<String, dynamic>();
    } on Object {
      return _json(400, {'error': 'bad_request'});
    }
    final text = body['body'];
    if (text is! String || text.trim().isEmpty) {
      return _json(400, {'error': 'empty_body'});
    }
    try {
      final m = await messages.draft(
        channelId: id,
        body: text,
        context: (body['context'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
        replyTo: body['replyTo'] as String?,
      );
      return _json(201, {'id': m.id, 'status': m.status});
    } on BodyTooLarge {
      return _json(413, {'error': 'body_too_large', 'limit': maxBodyBytes});
    } on UnknownChannel {
      return _json(404, {'error': 'unknown_channel'});
    } on ChannelClosed {
      return _json(409, {'error': 'channel_closed'});
    } on NotAMember {
      return _json(403, {'error': 'not_a_member'});
    }
  }

  Future<Response> _outbox(Request _) async {
    final peers = await _peerMap();
    return _ok([
      for (final m in await db.drafts())
        {
          'id': m.id,
          'channelId': m.channelId,
          'kind': m.kind,
          'body': m.kind == 'event' ? await _surat.eventBody(m, peers) : m.body,
          'context': m.contextJson == null ? null : jsonDecode(m.contextJson!),
          'replyTo': m.replyTo,
          'createdAt': m.createdAt,
        },
    ]);
  }

  Future<Message?> _find(String id) =>
      (db.select(db.messages)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<Response> _approve(Request _, String id) async {
    final draft = await _find(id);
    if (draft == null) return _json(404, {'error': 'unknown_draft'});
    if (draft.status != 'awaiting_approval') {
      return _json(409, {
        'error': 'not_awaiting_approval',
        'status': draft.status,
      });
    }
    Message m;
    try {
      m = await messages.approve(id);
    } on NotAMember {
      return _json(403, {'error': 'not_a_member', 'status': 'discarded'});
    } on ChannelClosed {
      return _json(409, {'error': 'channel_closed', 'status': 'discarded'});
    }
    final deliver = deliverNow;
    if (deliver != null && m.status == 'queued') {
      try {
        await deliver().timeout(deliverWait);
      } on Object {
        // Still queued; the worker keeps trying in the background.
      }
      m = await _find(id) ?? m;
    }
    // After a delivery pass: whoever still hasn't got it. Without one (no
    // worker attached): whoever hasn't been heard from lately.
    final peers = await _peerMap();
    final waiting = <String>[
      if (m.status == 'queued')
        for (final r in await messages.receiptsFor(m.id))
          if (deliver != null
              ? r.deliveredAt == null
              : !(peers[r.deviceId] == null || _reachable(peers[r.deviceId]!)))
            r.personName,
    ];
    return _ok({'status': m.status, 'queuedFor': waiting});
  }

  Future<Response> _discard(Request _, String id) async {
    final draft = await _find(id);
    if (draft == null) return _json(404, {'error': 'unknown_draft'});
    if (draft.status != 'awaiting_approval') {
      return _json(409, {
        'error': 'not_awaiting_approval',
        'status': draft.status,
      });
    }
    await messages.discard(id);
    return _ok({'status': 'discarded'});
  }
}

Response _ok(Object body) => _json(200, body);

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
