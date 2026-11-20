import 'dart:convert';
import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/identity/local_identity.dart';
import 'package:agent_relay/local_api/local_server.dart';
import 'package:agent_relay/messaging/envelope.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/surat/surat_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../support/fixtures.dart';

void main() {
  late Directory dir;
  late RelayDatabase db;
  late MessageService svc;
  late SuratService surat;
  late LocalServer server;
  late String token;
  late String xavierId;
  late IdentityKeys xavier;
  late String myId;
  var now = 1700000000000;
  const ch = 'ch1';

  setUp(() async {
    now = 1700000000000;
    dir = await tempDir('local');
    db = memoryDb();
    final me = await IdentityKeys.generate();
    myId = deviceIdFor(me.signPub, me.boxPub);
    xavier = await IdentityKeys.generate();
    xavierId = deviceIdFor(xavier.signPub, xavier.boxPub);
    await insertPeer(db, xavier);
    await (db.update(db.peers)).write(
      PeersCompanion(
        lastAddress: const Value('10.0.0.5'),
        lastPort: const Value(8790),
        lastSeenAt: Value(now),
      ),
    );
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(id: ch, kind: 'private', createdAt: 1),
        );
    for (final id in [myId, xavierId]) {
      await db
          .into(db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: ch,
              deviceId: id,
              joinedHlc: '0000000000000-00000',
            ),
          );
    }
    svc = MessageService(
      db: db,
      myDeviceId: myId,
      myBox: me.box,
      clock: HlcClock(nowMs: () => now),
      nowMs: () => now,
    );
    final identity = LocalIdentity(
      deviceId: myId,
      personName: 'Irfan',
      deviceName: 'MacBook Pro',
      keys: me,
      certPath: '',
      keyPath: '',
      certFingerprint: 'fp-me',
    );
    surat = SuratService(
      db: db,
      messages: svc,
      keys: me,
      me: identity,
      clock: HlcClock(nowMs: () => now),
      nowMs: () => now,
    );
    svc
      ..publishEvent = surat.publish
      ..dropEvent = surat.dropDraft;
    server = LocalServer(
      config: AppConfig(
        dataDir: dir,
        peerPort: 0,
        localPort: 0,
        keychainPrefix: 't',
      ),
      db: db,
      messages: svc,
      surat: surat,
      me: (deviceId: myId, personName: 'Irfan', deviceName: 'MacBook Pro'),
      nowMs: () => now,
    );
    await server.start();
    token = await File('${dir.path}/local-token').readAsString();
  });
  tearDown(() async {
    await server.stop();
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<(int, dynamic)> call(
    String method,
    String path, {
    Object? body,
    String? auth,
  }) async {
    final res = await server.handler(
      Request(
        method,
        Uri.parse('http://127.0.0.1$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {'authorization': auth ?? 'Bearer $token'},
      ),
    );
    final text = await res.readAsString();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  test('token file is written with mode 0600', () async {
    expect((await File('${dir.path}/local-token').stat()).mode & 0x1FF, 0x180);
    expect(token.length, greaterThanOrEqualTo(40));
  });

  test('server is bound to loopback only', () {
    expect(server.address!.isLoopback, isTrue);
  });

  test('requests without the bearer token get 401', () async {
    expect((await call('GET', '/status', auth: '')).$1, 401);
    expect((await call('GET', '/status', auth: 'Bearer nope')).$1, 401);
  });

  test('appVersion is the pubspec version name', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version: '));
    expect(appVersion, line.substring('version: '.length).split('+').first);
  });

  test('status and peers', () async {
    expect((await call('GET', '/status')).$2, {
      'deviceId': myId,
      'personName': 'Irfan',
      'deviceName': 'MacBook Pro',
      'version': '1.1.0',
    });
    final peers = (await call('GET', '/peers')).$2 as List;
    expect(peers.single['personName'], 'Xavier');
    expect(peers.single['reachable'], isTrue);
    now += 121000;
    expect(
      ((await call('GET', '/peers')).$2 as List).single['reachable'],
      isFalse,
    );
  });

  test(
    'channels: private channel named after the peer, with unread count',
    () async {
      final list = (await call('GET', '/channels')).$2 as List;
      expect(list.single['name'], 'Xavier');
      expect(list.single['kind'], 'private');
      expect(list.single['unread'], 0);
      expect(list.single['peer']['deviceId'], xavierId);
      expect(list.single['closed'], isFalse);
    },
  );

  test('send returns 201 awaiting_approval; approve returns queued with empty queuedFor when online', () async {
    final (s1, b1) = await call(
      'POST',
      '/channels/$ch/send',
      body: {
        'body': 'hi',
        'context': {'repo': 'Middleware'},
      },
    );
    expect(s1, 201);
    expect(b1['status'], 'awaiting_approval');
    final outbox = (await call('GET', '/outbox')).$2 as List;
    expect(outbox.single['id'], b1['id']);
    expect(outbox.single['channelId'], ch);
    expect(outbox.single['context'], {'repo': 'Middleware'});
    final (s2, b2) = await call('POST', '/outbox/${b1['id']}/approve');
    expect(s2, 200);
    expect(b2, {'status': 'queued', 'queuedFor': []});
  });

  test('approve lists only offline recipients in queuedFor', () async {
    now += 121000;
    final (_, b1) = await call(
      'POST',
      '/channels/$ch/send',
      body: {'body': 'hi'},
    );
    final (_, b2) = await call('POST', '/outbox/${b1['id']}/approve');
    expect(b2['queuedFor'], ['Xavier']);
  });

  test('discard', () async {
    final (_, b1) = await call(
      'POST',
      '/channels/$ch/send',
      body: {'body': 'hi'},
    );
    expect((await call('POST', '/outbox/${b1['id']}/discard')).$2, {
      'status': 'discarded',
    });
    expect((await call('GET', '/outbox')).$2, isEmpty);
  });

  test(
    'send over 32768 bytes returns 413 body_too_large; unknown channel 404',
    () async {
      final (s, b) = await call(
        'POST',
        '/channels/$ch/send',
        body: {'body': 'x' * 32769},
      );
      expect(s, 413);
      expect(b, {'error': 'body_too_large', 'limit': 32768});
      expect(
        (await call('POST', '/channels/nope/send', body: {'body': 'x'})).$1,
        404,
      );
    },
  );

  test('closed channel send is 409', () async {
    await (db.update(db.channels))
        .write(const ChannelsCompanion(closedAt: Value(1)));
    expect((await call('POST', '/channels/$ch/send', body: {'body': 'x'})).$2, {
      'error': 'channel_closed',
    });
  });

  test('messages endpoint returns ordered messages with receipts, gaps, and marks unread read', () async {
    final (_, b1) = await call(
      'POST',
      '/channels/$ch/send',
      body: {'body': 'mine'},
    );
    await call('POST', '/outbox/${b1['id']}/approve');
    // Incoming from Xavier: seq 2 and 4 (seq 3 missing → gap).
    final sealedFor =
        await IdentityKeys.generate(); // not our key: stored locked
    Envelope locked(String id, int seq, int hlcMs) => Envelope.fromJson({
      'id': id,
      'channelId': ch,
      'kind': 'message',
      'from': xavierId,
      'sentAt': now,
      'hlc': '${now + hlcMs}-00000',
      'seq': seq,
      'sealed': {
        'eph': base64.encode(sealedFor.boxPub),
        'nonce': base64.encode(List.filled(12, 0)),
        'ct': '',
        'mac': base64.encode(List.filled(16, 0)),
      },
    });
    final xavier = await db.select(db.peers).getSingle();
    await svc.receive(locked('in1', 2, 30000), from: xavier);
    // seq 3 never arrives: gaps count from the first stored seq.
    await svc.receive(locked('in2', 4, 40000), from: xavier);

    final (s, body) = await call('GET', '/channels/$ch/messages?status=all');
    expect(s, 200);
    final msgs = body['messages'] as List;
    expect(msgs.map((m) => m['id']), [b1['id'], 'in1', 'in2']);
    expect(msgs.first['direction'], 'out');
    expect(msgs.first['from'], {'deviceId': myId, 'personName': 'Irfan'});
    expect(msgs.first['receipts'].single, {
      'personName': 'Xavier',
      'deliveredAt': null,
      'seenAt': null,
      'agentReadAt': null,
    });
    expect(msgs.last['status'], 'locked');
    expect(body['gaps'], [
      {'personName': 'Xavier', 'missing': 1},
    ]);
  });

  test('unread filter returns only unread and then marks them read', () async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'u1',
            channelId: ch,
            kind: 'message',
            fromDeviceId: xavierId,
            sentAt: now,
            hlc: const Value('0000000000005-00000'),
            seq: const Value(1),
            body: const Value('hello'),
            direction: 'in',
            status: 'unread',
            createdAt: now,
          ),
        );
    final first =
        (await call(
              'GET',
              '/channels/$ch/messages?status=unread',
            )).$2['messages']
            as List;
    expect(first.single['body'], 'hello');
    expect(
      (await call(
        'GET',
        '/channels/$ch/messages?status=unread',
      )).$2['messages'],
      isEmpty,
    );
    expect(((await call('GET', '/channels')).$2 as List).single['unread'], 0);
  });

  test(
    'a message the person already saw in the app is still unread for the agent',
    () async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 's1',
              channelId: ch,
              kind: 'message',
              fromDeviceId: xavierId,
              sentAt: now,
              hlc: const Value('0000000000005-00000'),
              seq: const Value(1),
              body: const Value('seen in the app'),
              direction: 'in',
              status: 'read',
              createdAt: now,
              seenAt: Value(now),
            ),
          );
      expect(((await call('GET', '/channels')).$2 as List).single['unread'], 1);
      final first =
          (await call(
                'GET',
                '/channels/$ch/messages?status=unread',
              )).$2['messages']
              as List;
      expect(first.single['body'], 'seen in the app');
      expect(
        (await call(
          'GET',
          '/channels/$ch/messages?status=unread',
        )).$2['messages'],
        isEmpty,
      );
      expect(((await call('GET', '/channels')).$2 as List).single['unread'], 0);
    },
  );

  group('approve with a delivery pass', () {
    Future<void> useServer(Future<void> Function() deliverNow) async {
      await server.stop();
      server = LocalServer(
        config: AppConfig(
          dataDir: dir,
          peerPort: 0,
          localPort: 0,
          keychainPrefix: 't',
        ),
        db: db,
        messages: svc,
        surat: surat,
        me: (deviceId: myId, personName: 'Irfan', deviceName: 'MacBook Pro'),
        deliverNow: deliverNow,
        deliverWait: const Duration(milliseconds: 200),
        nowMs: () => now,
      );
      await server.start();
      token = await File('${dir.path}/local-token').readAsString();
    }

    Future<Map> approveOne() async {
      final (_, b1) = await call(
        'POST',
        '/channels/$ch/send',
        body: {'body': 'hi'},
      );
      return (await call('POST', '/outbox/${b1['id']}/approve')).$2 as Map;
    }

    test('delivered during the pass: sent, nobody queued — even with no recent contact', () async {
      now += 121000; // last contact is stale, the old check said offline
      await useServer(() async {
        for (final d in await db.dueDeliveries(now)) {
          await svc.markDelivered(d.messageId, d.recipientDeviceId);
        }
      });
      expect(await approveOne(), {'status': 'sent', 'queuedFor': []});
    });

    test('not delivered by the pass: queued for that person', () async {
      await useServer(() async {});
      expect(await approveOne(), {
        'status': 'queued',
        'queuedFor': ['Xavier'],
      });
    });

    test('a pass slower than the wait still answers, as queued', () async {
      await useServer(() => Future.delayed(const Duration(seconds: 5)));
      expect((await approveOne())['status'], 'queued');
    });
  });

  group('surat', () {
    Matcher res(int status, Object body) => isA<(int, dynamic)>()
        .having((r) => r.$1, 'status', status)
        .having((r) => r.$2, 'body', body);

    Future<(String, IdentityKeys)> pairedPeer(String name) async {
      final k = await IdentityKeys.generate();
      await insertPeer(db, k, name: name, fingerprint: 'fp-$name');
      return (deviceIdFor(k.signPub, k.boxPub), k);
    }

    Future<String> suratRow({
      required String id,
      String creator = '',
      String? name = 'Release',
      int? closedAt,
      required Map<String, ChannelMembersCompanion Function(String id)> rows,
    }) async {
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              id: id,
              kind: 'surat',
              name: Value(name),
              createdAt: 1,
              closedAt: Value(closedAt),
              creatorDeviceId: Value(creator.isEmpty ? myId : creator),
            ),
          );
      for (final e in rows.entries) {
        await db.into(db.channelMembers).insert(e.value(e.key));
      }
      return id;
    }

    ChannelMembersCompanion Function(String) row(
      String surat,
      String joined, {
      String state = 'member',
      String? inviter,
      String? mine,
      String? theirs,
      String? person,
      String? device,
    }) =>
        (id) => ChannelMembersCompanion.insert(
          channelId: surat,
          deviceId: id,
          joinedHlc: joined,
          state: Value(state),
          inviterDeviceId: Value(inviter),
          myApproval: Value(mine),
          theirApproval: Value(theirs),
          personName: Value(person),
          deviceName: Value(device),
        );

    /// Creates a surat through the API and approves it, so it is published.
    Future<String> publishedSurat(List<String> invite) async {
      final (_, c) = await call(
        'POST',
        '/surat',
        body: {'name': 'Release', 'invite': invite},
      );
      expect((await call('POST', '/outbox/${c['id']}/approve')).$1, 200);
      return c['suratId'] as String;
    }

    test('POST /surat drafts the creation', () async {
      final (s, b) = await call(
        'POST',
        '/surat',
        body: {
          'name': ' Release ',
          'invite': [xavierId],
        },
      );
      expect(s, 201);
      expect(b['status'], 'awaiting_approval');
      final draft = await (db.select(
        db.messages,
      )..where((m) => m.id.equals(b['id']))).getSingle();
      expect(draft.channelId, b['suratId']);
      expect(draft.kind, 'event');
      final channel = await (db.select(
        db.channels,
      )..where((c) => c.id.equals(b['suratId']))).getSingle();
      expect((channel.kind, channel.name), ('surat', 'Release'));
    });

    test('POST /surat errors', () async {
      expect(
        await call(
          'POST',
          '/surat',
          body: {
            'name': '  ',
            'invite': [xavierId],
          },
        ),
        res(400, {'error': 'empty_name'}),
      );
      expect(
        await call(
          'POST',
          '/surat',
          body: {
            'name': 'x',
            'invite': ['nope'],
          },
        ),
        res(404, {'error': 'unknown_peer'}),
      );
      expect(
        await call('POST', '/surat', body: {'name': 'x', 'invite': []}),
        res(400, {'error': 'no_invitees'}),
      );
      expect((await call('POST', '/surat', body: {'name': 'x'})).$1, 400);
      final five = [
        xavierId,
        for (var i = 0; i < 4; i++) (await pairedPeer('P$i')).$1,
      ];
      expect(
        await call('POST', '/surat', body: {'name': 'x', 'invite': five}),
        res(409, {'error': 'too_many_members'}),
      );
    });

    test(
      'invite, leave and rename draft events once the surat is published',
      () async {
        final (yara, _) = await pairedPeer('Yara');
        final id = await publishedSurat([xavierId]);
        final (s, b) = await call(
          'POST',
          '/surat/$id/invite',
          body: {'deviceId': yara},
        );
        expect((s, b['status']), (201, 'awaiting_approval'));
        expect(
          (await call(
            'POST',
            '/surat/$id/rename',
            body: {'name': 'Launch'},
          )).$1,
          201,
        );
        final (sl, bl) = await call('POST', '/surat/$id/leave');
        expect((sl, bl['status']), (201, 'awaiting_approval'));
        final outbox = (await call('GET', '/outbox')).$2 as List;
        expect(outbox.map((d) => d['kind']), ['event', 'event', 'event']);
        expect(outbox.map((d) => d['body']), [
          'You invited Yara',
          'You renamed the surat to Launch',
          'You left',
        ]);
      },
    );

    test('invite errors', () async {
      final id = await publishedSurat([xavierId]);
      expect(
        await call('POST', '/surat/$id/invite', body: {'deviceId': xavierId}),
        res(403, {'error': 'not_allowed'}),
      );
      expect(
        await call('POST', '/surat/$id/invite', body: {'deviceId': 'nope'}),
        res(404, {'error': 'unknown_peer'}),
      );
      expect((await call('POST', '/surat/$id/invite', body: {})).$1, 400);
      // Me + Xavier + three more invitees fill all five seats.
      final (extra, _) = await pairedPeer('Extra');
      for (final n in ['E1', 'E2', 'E3']) {
        final (p, _) = await pairedPeer(n);
        await db
            .into(db.channelMembers)
            .insert(
              ChannelMembersCompanion.insert(
                channelId: id,
                deviceId: p,
                joinedHlc: '0000000000001-00000',
                state: const Value('invited'),
              ),
            );
      }
      expect(
        await call('POST', '/surat/$id/invite', body: {'deviceId': extra}),
        res(409, {'error': 'too_many_members'}),
      );
    });

    test('draft routes: unknown, closed, not a member, unpublished', () async {
      expect(
        await call('POST', '/surat/nope/leave'),
        res(404, {'error': 'unknown_channel'}),
      );
      expect(
        await call('POST', '/surat/$ch/leave'),
        res(404, {'error': 'unknown_channel'}),
      );
      await suratRow(
        id: 'ended',
        closedAt: 5,
        rows: {myId: row('ended', '0000000000001-00000')},
      );
      expect(
        await call('POST', '/surat/ended/leave'),
        res(409, {'error': 'channel_closed'}),
      );
      await suratRow(
        id: 'gone',
        rows: {
          myId: row('gone', '0000000000001-00000', state: 'left'),
          xavierId: row('gone', '0000000000002-00000'),
        },
      );
      expect(
        await call('POST', '/surat/gone/leave'),
        res(403, {'error': 'not_a_member'}),
      );
      // Before its create is published (R11) nothing may be drafted.
      final (_, c) = await call(
        'POST',
        '/surat',
        body: {
          'name': 'Draft',
          'invite': [xavierId],
        },
      );
      expect(
        await call('POST', '/surat/${c['suratId']}/leave'),
        res(403, {'error': 'not_allowed'}),
      );
      expect(
        await call(
          'POST',
          '/surat/${c['suratId']}/rename',
          body: {'name': 'z'},
        ),
        res(403, {'error': 'not_allowed'}),
      );
    });

    test('rename errors: empty name, and not the renamer', () async {
      final id = await publishedSurat([xavierId]);
      expect(
        await call('POST', '/surat/$id/rename', body: {'name': ' '}),
        res(400, {'error': 'empty_name'}),
      );
      await suratRow(
        id: 'theirs',
        creator: xavierId,
        rows: {
          myId: row('theirs', '0000000000002-00000'),
          xavierId: row('theirs', '0000000000001-00000'),
        },
      );
      expect(
        await call('POST', '/surat/theirs/rename', body: {'name': 'Mine'}),
        res(403, {'error': 'not_allowed'}),
      );
    });

    test('GET /pending lists invites and newcomers', () async {
      final (yara, _) = await pairedPeer('Yara');
      await suratRow(
        id: 's1',
        name: 'Alpha',
        creator: xavierId,
        rows: {
          myId: row(
            's1',
            '0000000000002-00000',
            state: 'invited',
            inviter: xavierId,
          ),
          xavierId: row(
            's1',
            '0000000000001-00000',
            person: 'Xavier',
            device: 'Mac',
          ),
        },
      );
      await suratRow(
        id: 's2',
        name: 'Beta',
        rows: {
          myId: row('s2', '0000000000001-00000'),
          xavierId: row(
            's2',
            '0000000000002-00000',
            mine: 'approved',
            person: 'Xavier',
            device: 'Mac',
          ),
          yara: row(
            's2',
            '0000000000003-00000',
            state: 'invited',
            inviter: xavierId,
            person: 'Yara',
            device: 'Air',
          ),
        },
      );
      final (s, list) = await call('GET', '/pending');
      expect(s, 200);
      expect(list, [
        {
          'id': 'invite:s1:$myId',
          'kind': 'invite',
          'suratId': 's1',
          'suratName': 'Alpha',
          'deviceId': myId,
          'personName': 'Irfan',
          'deviceName': 'MacBook Pro',
          'inviterName': 'Xavier',
          'declined': false,
        },
        {
          'id': 'newcomer:s2:$yara',
          'kind': 'newcomer',
          'suratId': 's2',
          'suratName': 'Beta',
          'deviceId': yara,
          'personName': 'Yara',
          'deviceName': 'Air',
          'inviterName': 'Xavier',
          'declined': false,
        },
      ]);
    });

    test('approve and decline a pending id, URL-encoded or not', () async {
      final (yara, _) = await pairedPeer('Yara');
      await suratRow(
        id: 's2',
        rows: {
          myId: row('s2', '0000000000001-00000'),
          xavierId: row(
            's2',
            '0000000000002-00000',
            mine: 'approved',
            person: 'Xavier',
            device: 'Mac',
          ),
          yara: row(
            's2',
            '0000000000003-00000',
            state: 'invited',
            inviter: xavierId,
            person: 'Yara',
            device: 'Air',
          ),
        },
      );
      final encoded = Uri.encodeComponent('newcomer:s2:$yara');
      expect(encoded, contains('%3A'));
      expect(
        await call('POST', '/pending/$encoded/approve'),
        res(200, {'ok': true}),
      );
      expect(
        await call('POST', '/pending/newcomer:s2:$yara/approve'),
        res(200, {'ok': true}),
      );
      final events = await (db.select(
        db.messages,
      )..where((m) => m.channelId.equals('s2') & m.kind.equals('event'))).get();
      // The fixture has no event log, so nothing marks Yara approved and the
      // second call publishes again; each carries my approval.
      expect(events, isNotEmpty);
      expect(
        events.every((e) => e.body == '{"type":"approve","deviceId":"$yara"}'),
        isTrue,
      );
    });

    test('decline a newcomer; accept an invite', () async {
      final (yara, _) = await pairedPeer('Yara');
      await suratRow(
        id: 's2',
        rows: {
          myId: row('s2', '0000000000001-00000'),
          xavierId: row('s2', '0000000000002-00000'),
          yara: row(
            's2',
            '0000000000003-00000',
            state: 'invited',
            inviter: xavierId,
          ),
        },
      );
      expect(
        await call(
          'POST',
          '/pending/${Uri.encodeComponent('newcomer:s2:$yara')}/decline',
        ),
        res(200, {'ok': true}),
      );
      await suratRow(
        id: 's3',
        creator: xavierId,
        rows: {
          myId: row(
            's3',
            '0000000000002-00000',
            state: 'invited',
            inviter: xavierId,
          ),
          xavierId: row('s3', '0000000000001-00000'),
        },
      );
      expect(
        await call(
          'POST',
          '/pending/${Uri.encodeComponent('invite:s3:$myId')}/approve',
        ),
        res(200, {'ok': true}),
      );
    });

    test('send into a surat I am only invited to, or left, is 403 '
        'not_a_member', () async {
      await suratRow(
        id: 'inv',
        rows: {
          myId: row('inv', '0000000000001-00000', state: 'invited'),
          xavierId: row('inv', '0000000000002-00000'),
        },
      );
      await suratRow(
        id: 'gone',
        rows: {
          myId: row('gone', '0000000000001-00000', state: 'left'),
          xavierId: row('gone', '0000000000002-00000'),
        },
      );
      for (final s in ['inv', 'gone']) {
        expect(
          await call('POST', '/channels/$s/send', body: {'body': 'x'}),
          res(403, {'error': 'not_a_member'}),
        );
      }
    });

    Future<Message> draftRow(String id) =>
        (db.select(db.messages)..where((m) => m.id.equals(id))).getSingle();

    test('approving a draft made before I left is 403 not_a_member and '
        'discards it', () async {
      await suratRow(
        id: 's3',
        rows: {
          myId: row('s3', '0000000000001-00000'),
          xavierId: row('s3', '0000000000002-00000'),
        },
      );
      final (_, d) = await call(
        'POST',
        '/channels/s3/send',
        body: {'body': 'late'},
      );
      await (db.update(db.channelMembers)
            ..where((m) => m.channelId.equals('s3') & m.deviceId.equals(myId)))
          .write(
            const ChannelMembersCompanion(
              state: Value('left'),
              leftHlc: Value('0000000000009-00000'),
            ),
          );
      expect(
        await call('POST', '/outbox/${d['id']}/approve'),
        res(403, {'error': 'not_a_member', 'status': 'discarded'}),
      );
      expect((await draftRow(d['id'] as String)).status, 'discarded');
      expect((await call('GET', '/outbox')).$2, isEmpty);
    });

    test('approving an event draft in a surat that has since ended is 409 '
        'channel_closed and discards it', () async {
      await suratRow(
        id: 's4',
        rows: {
          myId: row('s4', '0000000000001-00000'),
          xavierId: row('s4', '0000000000002-00000'),
        },
      );
      final (_, d) = await call('POST', '/surat/s4/leave');
      await (db.update(db.channels)..where((c) => c.id.equals('s4'))).write(
        const ChannelsCompanion(closedAt: Value(5)),
      );
      expect(
        await call('POST', '/outbox/${d['id']}/approve'),
        res(409, {'error': 'channel_closed', 'status': 'discarded'}),
      );
      expect((await draftRow(d['id'] as String)).status, 'discarded');
      expect((await call('GET', '/outbox')).$2, isEmpty);
    });

    test('a surat that ends while a decision is being published is 409 '
        'channel_closed', () async {
      await suratRow(
        id: 's5',
        rows: {
          myId: row('s5', '0000000000001-00000', state: 'invited'),
          xavierId: row('s5', '0000000000002-00000'),
        },
      );
      // The route reads the surat open, then it ends before the accept is
      // published.
      final answer = call(
        'POST',
        '/pending/${Uri.encodeComponent('invite:s5:$myId')}/approve',
      );
      await (db.update(db.channels)..where((c) => c.id.equals('s5'))).write(
        const ChannelsCompanion(closedAt: Value(5)),
      );
      expect(await answer, res(409, {'error': 'channel_closed'}));
    });

    test('pending errors', () async {
      final (yara, _) = await pairedPeer('Yara');
      await suratRow(
        id: 's2',
        rows: {
          myId: row('s2', '0000000000001-00000'),
          xavierId: row('s2', '0000000000002-00000'),
          yara: row(
            's2',
            '0000000000003-00000',
            state: 'invited',
            inviter: xavierId,
            mine: 'approved',
          ),
        },
      );
      expect(
        await call(
          'POST',
          '/pending/${Uri.encodeComponent('newcomer:s2:$yara')}/decline',
        ),
        res(409, {'error': 'already_approved'}),
      );
      expect(
        await call(
          'POST',
          '/pending/${Uri.encodeComponent('newcomer:s2:nobody')}/approve',
        ),
        res(404, {'error': 'unknown_pending'}),
      );
      expect(
        await call('POST', '/pending/garbage/decline'),
        res(404, {'error': 'unknown_pending'}),
      );
    });

    test('surat routes need the bearer token', () async {
      for (final (m, p) in [
        ('POST', '/surat'),
        ('POST', '/surat/x/invite'),
        ('POST', '/surat/x/leave'),
        ('POST', '/surat/x/rename'),
        ('GET', '/pending'),
        ('POST', '/pending/x/approve'),
        ('POST', '/pending/x/decline'),
      ]) {
        expect((await call(m, p, auth: 'Bearer nope')).$1, 401, reason: p);
      }
    });

    test(
      'GET /channels shows members, renamer and pending for a surat',
      () async {
        final (yara, _) = await pairedPeer('Yara');
        await suratRow(
          id: 's2',
          creator: xavierId,
          rows: {
            myId: row(
              's2',
              '0000000000002-00000',
              mine: 'approved',
              theirs: 'approved',
            ),
            xavierId: row(
              's2',
              '0000000000001-00000',
              mine: 'approved',
              theirs: 'declined',
              person: 'Xavier',
              device: 'Mac',
            ),
            yara: row(
              's2',
              '0000000000003-00000',
              state: 'invited',
              inviter: xavierId,
              person: 'Yara',
              device: 'Air',
            ),
          },
        );
        final list = (await call('GET', '/channels')).$2 as List;
        final s = list.firstWhere((c) => c['id'] == 's2');
        expect(s['kind'], 'surat');
        expect(s['name'], 'Release');
        expect(s['renamer'], xavierId);
        expect(s['pending'], 1);
        expect(s['closed'], isFalse);
        final members = s['members'] as List;
        expect(members.firstWhere((m) => m['deviceId'] == xavierId), {
          'deviceId': xavierId,
          'personName': 'Xavier',
          'deviceName': 'Mac',
          'state': 'member',
          'mine': {'approval': 'approved'},
          'theirs': {'approval': 'declined'},
        });
        expect(members.firstWhere((m) => m['deviceId'] == yara)['mine'], {
          'approval': null,
        });
        // Private channels keep their shape.
        final priv = list.firstWhere((c) => c['id'] == ch);
        expect(priv.containsKey('members'), isFalse);
        expect(priv.containsKey('renamer'), isFalse);
      },
    );

    test(
      'an ended surat is closed in /channels; unread counts messages only',
      () async {
        await suratRow(
          id: 'end',
          closedAt: 9,
          rows: {myId: row('end', '0000000000001-00000')},
        );
        await db
            .into(db.messages)
            .insert(
              MessagesCompanion.insert(
                id: 'evt',
                channelId: 'end',
                kind: 'event',
                fromDeviceId: xavierId,
                sentAt: 1,
                hlc: const Value('0000000000005-00000'),
                seq: const Value(0),
                body: const Value('{"type":"leave"}'),
                direction: 'in',
                status: 'unread',
                createdAt: 1,
              ),
            );
        final s = ((await call('GET', '/channels')).$2 as List).firstWhere(
          (c) => c['id'] == 'end',
        );
        expect((s['closed'], s['unread']), (true, 0));
      },
    );

    test('messages: kind, readable event lines, locked reasons', () async {
      await suratRow(
        id: 's2',
        creator: xavierId,
        rows: {
          myId: row('s2', '0000000000002-00000', mine: 'approved'),
          xavierId: row(
            's2',
            '0000000000001-00000',
            theirs: 'approved',
            person: 'Xavier',
            device: 'Mac',
          ),
        },
      );
      final (yara, _) = await pairedPeer('Yara');
      await db
          .into(db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: 's2',
              deviceId: yara,
              joinedHlc: '0000000000003-00000',
              myApproval: const Value(null),
              theirApproval: const Value('declined'),
            ),
          );
      Future<void> put(
        String id,
        String kind,
        String from,
        String hlc,
        String body,
        String status,
      ) => db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: id,
              channelId: 's2',
              kind: kind,
              fromDeviceId: from,
              sentAt: 1,
              hlc: Value(hlc),
              seq: Value(kind == 'event' ? 0 : 1),
              body: Value(body),
              direction: 'in',
              status: status,
              createdAt: 1,
            ),
          );
      await put(
        'e1',
        'event',
        xavierId,
        '0000000000010-00000',
        '{"type":"rename","name":"Launch"}',
        'unread',
      );
      await put(
        'm1',
        'message',
        xavierId,
        '0000000000011-00000',
        'hi',
        'locked',
      );
      await put('m2', 'message', yara, '0000000000012-00000', 'yo', 'locked');
      final (_, body) = await call('GET', '/channels/s2/messages');
      final msgs = body['messages'] as List;
      expect(msgs.map((m) => m['kind']), ['event', 'message', 'message']);
      expect(msgs[0]['body'], 'Xavier renamed the surat to Launch');
      expect(msgs[0].containsKey('lockedReason'), isFalse);
      // Xavier approved me, so what is missing is my approval of him.
      expect(msgs[1]['lockedReason'], 'you_have_not_approved_them');
      expect(msgs[2]['lockedReason'], 'they_have_not_approved_you');
    });

    test(
      'outbox: message drafts say kind message, event drafts a readable line',
      () async {
        await call('POST', '/channels/$ch/send', body: {'body': 'hi'});
        await call(
          'POST',
          '/surat',
          body: {
            'name': 'Release',
            'invite': [xavierId],
          },
        );
        final outbox = (await call('GET', '/outbox')).$2 as List;
        expect(outbox.map((d) => d['kind']), ['message', 'event']);
        expect(outbox[0]['body'], 'hi');
        expect(outbox[1]['body'], 'You created Release');
        final (s, b) = await call('POST', '/outbox/${outbox[1]['id']}/discard');
        expect((s, b['status']), (200, 'discarded'));
        expect(
          await (db.select(
            db.channels,
          )..where((c) => c.kind.equals('surat'))).get(),
          isEmpty,
        );
      },
    );
  });
}
