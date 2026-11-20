import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../data/relay_database.dart';
import '../messaging/message_service.dart';
import '../surat/event_line.dart';
import '../surat/surat_event.dart';
import '../surat/surat_service.dart';

/// The surat and pending routes of the local API, plus the surat-aware
/// pieces of `/channels`, `/channels/<id>/messages` and `/outbox`.
/// [LocalServer] mounts the routes behind its bearer-token check.
class SuratRoutes {
  SuratRoutes({
    required this.db,
    required this.surat,
    required this.meDeviceId,
  });

  final RelayDatabase db;
  final SuratService surat;
  final String meDeviceId;

  void mount(Router r) {
    r
      ..post('/surat', _create)
      ..post('/surat/<id>/invite', _invite)
      ..post('/surat/<id>/leave', _leave)
      ..post('/surat/<id>/rename', _rename)
      ..get('/pending', _pending)
      ..post(
        '/pending/<id>/approve',
        (Request q, String id) => _decide(id, true),
      )
      ..post(
        '/pending/<id>/decline',
        (Request q, String id) => _decide(id, false),
      );
  }

  // ---- routes ----

  Future<Response> _create(Request req) async {
    final body = await _body(req);
    if (body == null) return _error(400, 'bad_request');
    final name = body['name'];
    final invite = body['invite'];
    if (name is! String || invite is! List || invite.any((i) => i is! String)) {
      return _error(400, 'bad_request');
    }
    return _drafting(() async {
      final id = await surat.draftCreate(name, invite.cast<String>());
      return _drafted(id);
    });
  }

  Future<Response> _invite(Request req, String id) async {
    final body = await _body(req);
    final deviceId = body?['deviceId'];
    if (deviceId is! String) return _error(400, 'bad_request');
    return _drafting(
      () async => _drafted(await surat.draftInvite(id, deviceId)),
    );
  }

  Future<Response> _leave(Request req, String id) =>
      _drafting(() async => _drafted(await surat.draftLeave(id)));

  Future<Response> _rename(Request req, String id) async {
    final name = (await _body(req))?['name'];
    if (name is! String) return _error(400, 'bad_request');
    return _drafting(() async => _drafted(await surat.draftRename(id, name)));
  }

  Future<Response> _pending(Request _) async => _json(200, [
    for (final p in await surat.pending())
      {
        'id': p.id,
        'kind': p.kind,
        'suratId': p.suratId,
        'suratName': p.suratName,
        'deviceId': p.deviceId,
        'personName': p.personName,
        'deviceName': p.deviceName,
        'inviterName': p.inviterName,
        'declined': p.declined,
      },
  ]);

  Future<Response> _decide(String rawId, bool approve) async {
    try {
      // Pending ids contain ':' and arrive URL-encoded.
      await surat.decide(Uri.decodeComponent(rawId), approve: approve);
      return _json(200, {'ok': true});
    } on AlreadyApproved {
      return _error(409, 'already_approved');
    } on UnknownPending {
      return _error(404, 'unknown_pending');
    } on NotAllowed {
      return _error(403, 'not_allowed');
    }
  }

  Future<Response> _drafting(Future<Response> Function() run) async {
    try {
      return await run();
    } on ArgumentError catch (e) {
      return _error(400, e.name == 'name' ? 'empty_name' : 'no_invitees');
    } on TooManyMembers {
      return _error(409, 'too_many_members');
    } on UnknownPeer {
      return _error(404, 'unknown_peer');
    } on NotAllowed {
      return _error(403, 'not_allowed');
    } on UnknownChannel {
      return _error(404, 'unknown_channel');
    } on ChannelClosed {
      return _error(409, 'channel_closed');
    } on NotAMember {
      return _error(403, 'not_a_member');
    }
  }

  Future<Response> _drafted(String draftId) async {
    final m = await (db.select(
      db.messages,
    )..where((m) => m.id.equals(draftId))).getSingle();
    return _json(201, {
      'id': draftId,
      'suratId': m.channelId,
      'status': m.status,
    });
  }

  // ---- pieces of the other routes ----

  /// The surat-only fields of a `/channels` row.
  Map<String, Object?> channelFields(
    Channel c,
    List<ChannelMember> members,
    Map<String, Peer> peers,
    int pending,
  ) => {
    'members': [
      for (final m in members)
        {
          'deviceId': m.deviceId,
          'personName': m.personName ?? peers[m.deviceId]?.personName,
          'deviceName': m.deviceName ?? peers[m.deviceId]?.deviceName,
          'state': m.state,
          'mine': {'approval': m.myApproval},
          'theirs': {'approval': m.theirApproval},
        },
    ],
    'renamer': renamerOf(c, members),
    'pending': pending,
  };

  /// The member with rename rights: lowest `joinedHlc` among current members
  /// (ties: lowest device id), else the creator while none has joined.
  String? renamerOf(Channel c, List<ChannelMember> members) {
    final current = members.where((m) => m.state == 'member').toList();
    if (current.isEmpty) return null;
    final joined = current.where((m) => m.joinedHlc != unpublishedHlc).toList()
      ..sort((a, b) {
        final byHlc = a.joinedHlc.compareTo(b.joinedHlc);
        return byHlc != 0 ? byHlc : a.deviceId.compareTo(b.deviceId);
      });
    return joined.isEmpty ? c.creatorDeviceId : joined.first.deviceId;
  }

  /// Why a locked message is locked, judged from its sender's member row:
  /// their approval of me is missing, or mine of them.
  String lockedReason(List<ChannelMember> members, String sender) {
    final row = members.where((m) => m.deviceId == sender).firstOrNull;
    return row?.theirApproval == 'approved'
        ? 'you_have_not_approved_them'
        : 'they_have_not_approved_you';
  }

  /// Device id to display name inside one surat: "You" for me, the person
  /// name, plus " ({device})" where two members share a person name.
  Future<String Function(String)> namer(
    String channelId,
    Map<String, Peer> peers,
  ) async {
    final rows = await (db.select(
      db.channelMembers,
    )..where((m) => m.channelId.equals(channelId))).get();
    final person = <String, String>{};
    final device = <String, String>{};
    for (final m in rows) {
      final p = peers[m.deviceId];
      person[m.deviceId] = m.personName ?? p?.personName ?? 'Unknown';
      device[m.deviceId] = m.deviceName ?? p?.deviceName ?? '';
    }
    final counts = <String, int>{};
    for (final n in person.values) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
    return (id) {
      if (id == meDeviceId) return 'You';
      final n = person[id] ?? peers[id]?.personName ?? 'Unknown';
      return (counts[n] ?? 0) > 1 && (device[id] ?? '').isNotEmpty
          ? '$n (${device[id]})'
          : n;
    };
  }

  /// A person name for [deviceId] in [channelId]: peers first, then the
  /// surat's member rows (members who are not peers yet).
  Future<Map<String, String>> memberNames(String channelId) async => {
    for (final m in await (db.select(
      db.channelMembers,
    )..where((m) => m.channelId.equals(channelId))).get())
      if (m.personName != null) m.deviceId: m.personName!,
  };

  /// The readable line of a stored event row, or the raw body when it does
  /// not parse.
  Future<String?> eventBody(
    Message m,
    Map<String, Peer> peers, {
    String? suratName,
  }) async {
    final SuratEvent event;
    try {
      event = SuratEvent.fromJson(jsonDecode(m.body ?? '') as Map);
    } on Object {
      return m.body;
    }
    final nameOf = await namer(m.channelId, peers);
    return eventLine(
      event,
      from: m.fromDeviceId,
      nameOf: nameOf,
      suratName: suratName,
    );
  }

  /// How many decisions wait for me, per surat id.
  Future<Map<String, int>> pendingCounts() async {
    final out = <String, int>{};
    for (final p in await surat.pending()) {
      out[p.suratId] = (out[p.suratId] ?? 0) + 1;
    }
    return out;
  }
}

Future<Map<String, dynamic>?> _body(Request req) async {
  try {
    final text = await req.readAsString();
    if (text.trim().isEmpty) return <String, dynamic>{};
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  } on Object {
    return null;
  }
}

Response _error(int status, String code) => _json(status, {'error': code});

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
