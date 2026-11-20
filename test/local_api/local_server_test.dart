import 'dart:convert';
import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/local_api/local_server.dart';
import 'package:agent_relay/messaging/envelope.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../support/fixtures.dart';

void main() {
  late Directory dir;
  late RelayDatabase db;
  late MessageService svc;
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
    server = LocalServer(
      config: AppConfig(
        dataDir: dir,
        peerPort: 0,
        localPort: 0,
        keychainPrefix: 't',
      ),
      db: db,
      messages: svc,
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

  test('status and peers', () async {
    expect((await call('GET', '/status')).$2, {
      'deviceId': myId,
      'personName': 'Irfan',
      'deviceName': 'MacBook Pro',
      'version': '1.0.0',
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
}
