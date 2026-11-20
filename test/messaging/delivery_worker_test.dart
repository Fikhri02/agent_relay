import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/identity/local_identity.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/messaging/delivery_worker.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/node/notifier.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/peer/peer_client.dart';
import 'package:agent_relay/peer/server_bootstrap.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../support/fixtures.dart';

/// Records calls; answers with [next] (a status code or an exception).
class FakeTransport implements PeerTransport {
  final calls = <(PeerTarget, String)>[];
  Object next = 200;
  Completer<void>? gate;

  @override
  Future<PeerResponse> post(
    PeerTarget t,
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add((t, path));
    if (gate != null) await gate!.future;
    final n = next;
    if (n is Exception) throw n;
    return (
      status: n as int,
      json: <String, dynamic>{'error': n == 401 ? 'untrusted' : 'x'},
      presentedFingerprint: null,
    );
  }
}

void main() {
  late RelayDatabase db;
  late MessageService svc;
  late FakeTransport net;
  late RecordingNotifier notes;
  late DeliveryWorker worker;
  late String peerId;
  final unpaired = <String>[];
  var now = 1700000000000;
  const ch = 'ch1';

  setUp(() async {
    now = 1700000000000;
    unpaired.clear();
    db = memoryDb();
    final me = await IdentityKeys.generate();
    final xavier = await IdentityKeys.generate();
    peerId = deviceIdFor(xavier.signPub, xavier.boxPub);
    await insertPeer(db, xavier, fingerprint: 'fpX');
    await (db.update(db.peers)).write(
      const PeersCompanion(
        lastAddress: Value('10.0.0.5'),
        lastPort: Value(8790),
      ),
    );
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(id: ch, kind: 'private', createdAt: 1),
        );
    final myId = deviceIdFor(me.signPub, me.boxPub);
    for (final id in [myId, peerId]) {
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
    net = FakeTransport();
    notes = RecordingNotifier();
    worker = DeliveryWorker(
      db: db,
      transport: net,
      messages: svc,
      notifier: notes,
      nowMs: () => now,
      onUnpaired: (id) async => unpaired.add(id),
    );
  });
  tearDown(() => db.close());

  Future<String> queuedMessage([String body = 'hi']) async {
    final d = await svc.draft(channelId: ch, body: body);
    await svc.approve(d.id);
    return d.id;
  }

  Future<Delivery> delivery(String id) => (db.select(
    db.deliveries,
  )..where((d) => d.messageId.equals(id))).getSingle();
  Future<Message> message(String id) =>
      (db.select(db.messages)..where((m) => m.id.equals(id))).getSingle();

  const suratCh = 'sur1';
  Future<void> addSurat() async {
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(id: suratCh, kind: 'surat', createdAt: 1),
        );
    for (final id in [svc.myDeviceId, peerId]) {
      await db
          .into(db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: suratCh,
              deviceId: id,
              joinedHlc: '0000000000000-00000',
            ),
          );
    }
  }

  Future<String> queuedSuratMessage() async {
    final d = await svc.draft(channelId: suratCh, body: 'surat hi');
    await svc.approve(d.id);
    return d.id;
  }

  Future<void> makeContact() =>
      (db.update(db.peers))
          .write(const PeersCompanion(trust: Value('surat_contact')));

  test('worker delivers a surat message to a surat contact', () async {
    await addSurat();
    final id = await queuedSuratMessage();
    await makeContact();
    await worker.runOnce();
    expect(net.calls, hasLength(1));
    expect((await message(id)).status, 'sent');
  });

  test('a 401 from a peer already a surat contact backs off without calling onUnpaired', () async {
    await addSurat();
    final sur = await queuedSuratMessage();
    await makeContact();
    net.next = 401;
    await worker.runOnce();
    expect(unpaired, isEmpty);
    expect(notes.shown, isEmpty);
    expect((await delivery(sur)).status, 'queued');
    expect((await delivery(sur)).attempts, 1);
    final posts = net.calls.length;
    await worker.runOnce();
    expect(net.calls.length, posts);
  });

  test('worker never sends a private message to a contact', () async {
    final id = await queuedMessage();
    await makeContact();
    await worker.runOnce();
    expect(net.calls, isEmpty);
    expect((await delivery(id)).status, 'dropped');
  });

  test('A unpairs while B is offline: a 401 drops private deliveries only and keeps surat ones queued', () async {
    await addSurat();
    final priv = await queuedMessage();
    final sur = await queuedSuratMessage();
    net.next = 401;
    await worker.runOnce();
    expect(unpaired, [peerId]);
    expect((await delivery(priv)).status, 'dropped');
    expect((await delivery(sur)).status, 'queued');
    expect((await delivery(sur)).lastError, 'untrusted');
    expect(notes.shown, hasLength(1));
    final posts = net.calls.length;
    await worker.runOnce(); // same `now`: backing off
    expect(net.calls.length, posts);
    expect(unpaired, [peerId]);
    expect(notes.shown, hasLength(1));
  });

  test('posts to the peer address pinned to its fingerprint; 200 marks the message sent', () async {
    final id = await queuedMessage();
    await worker.runOnce();
    expect(net.calls.single.$1, (
      host: '10.0.0.5',
      port: 8790,
      pinnedFingerprint: 'fpX',
    ));
    expect(net.calls.single.$2, '/relay/deliver');
    expect((await delivery(id)).status, 'delivered');
    expect((await message(id)).status, 'sent');
  });

  test('unreachable peer backs off 5 s, 30 s, 2 min, 5 min', () async {
    final id = await queuedMessage();
    net.next = const PeerUnreachable('down');
    final waits = <int>[];
    for (var i = 0; i < 5; i++) {
      await worker.runOnce();
      final d = await delivery(id);
      waits.add(d.nextAttemptAt - now);
      now = d.nextAttemptAt;
    }
    expect(waits, [5000, 30000, 120000, 300000, 300000]);
  });

  test('not due yet is not attempted', () async {
    await queuedMessage();
    net.next = const PeerUnreachable('down');
    await worker.runOnce();
    await worker.runOnce();
    expect(net.calls.length, 1);
  });

  test(
    'delivery resumes immediately after peerSeen with a new address',
    () async {
      final id = await queuedMessage();
      net.next = const PeerUnreachable('down');
      await worker.runOnce();
      await (db.update(db.peers))
          .write(const PeersCompanion(lastAddress: Value('10.0.0.9')));
      net.next = 200;
      await worker.peerSeen(peerId);
      await worker.runOnce();
      expect(net.calls.last.$1.host, '10.0.0.9');
      expect((await delivery(id)).status, 'delivered');
    },
  );

  test(
    'delivery queued 7 days + 1 ms is dropped and the sender is notified',
    () async {
      final id = await queuedMessage();
      now += 7 * 24 * 3600 * 1000 + 1;
      await worker.runOnce();
      expect((await delivery(id)).status, 'dropped');
      expect(net.calls, isEmpty);
      expect(notes.shown.single.title, "Couldn't deliver to Xavier");
      expect(notes.shown.single.body, contains('7 days'));
    },
  );

  test('draft awaiting approval for 1 h + 1 ms expires; one approved at 59 min is sent', () async {
    final stale = await svc.draft(channelId: ch, body: 'old');
    final fresh = await svc.draft(channelId: ch, body: 'new');
    now += 59 * 60 * 1000;
    await svc.approve(fresh.id);
    now += 60 * 1000 + 1;
    await worker.runOnce();
    expect((await message(stale.id)).status, 'expired');
    expect((await message(fresh.id)).status, 'sent');
  });

  test('expired drafts are reported to onDraftsExpired once', () async {
    final expired = <List<String>>[];
    final w = DeliveryWorker(
      db: db,
      transport: net,
      messages: svc,
      notifier: notes,
      nowMs: () => now,
      onUnpaired: (_) async {},
      onDraftsExpired: (list) async =>
          expired.add([for (final m in list) '${m.id}:${m.status}']),
    );
    final stale = await svc.draft(channelId: ch, body: 'old');
    now += 60 * 60 * 1000 + 1;
    final fresh = await svc.draft(channelId: ch, body: 'new');
    await w.runOnce();
    await w.runOnce();
    expect(expired, [
      ['${stale.id}:expired'],
    ]);
    expect((await message(fresh.id)).status, 'awaiting_approval');
  });

  test(
    'state survives a restart: a new worker on the same db sends queued items',
    () async {
      final id = await queuedMessage();
      final again = DeliveryWorker(
        db: db,
        transport: net,
        messages: svc,
        notifier: notes,
        nowMs: () => now,
        onUnpaired: (_) async {},
      );
      await again.runOnce();
      expect((await delivery(id)).status, 'delivered');
    },
  );

  test(
    'clock skew keeps the item queued, records the skew and notifies once',
    () async {
      final id = await queuedMessage();
      net.next = const PeerClockSkew(45000);
      await worker.runOnce();
      now += 10 * 60 * 1000;
      await worker.runOnce();
      expect((await delivery(id)).status, 'queued');
      expect((await db.select(db.peers).getSingle()).clockSkewMs, 45000);
      expect(
        notes.shown
            .where((n) => n.body.contains('Clocks differ by 45 s'))
            .length,
        1,
      );
    },
  );

  test('a certificate mismatch at an address clears the address and keeps the pairing', () async {
    final id = await queuedMessage();
    net.next = const PeerIdentityMismatch('other');
    await worker.runOnce();
    final p = await db.select(db.peers).getSingle();
    expect(p.trust, 'paired');
    expect(p.lastAddress, isNull);
    expect((await delivery(id)).status, 'queued');
  });

  test(
    'after a mismatch, the peer seen at a new address gets the message',
    () async {
      final id = await queuedMessage();
      net.next = const PeerIdentityMismatch('other');
      await worker.runOnce();
      await (db.update(db.peers))
          .write(const PeersCompanion(lastAddress: Value('10.0.0.9')));
      net.next = 200;
      await worker.peerSeen(peerId);
      await worker.runOnce();
      expect((await delivery(id)).status, 'delivered');
    },
  );

  test(
    'a delivery to a peer that is not paired is still dropped after 7 days',
    () async {
      final id = await queuedMessage();
      await (db.update(db.peers))
          .write(const PeersCompanion(trust: Value('unpaired')));
      now += 7 * 24 * 3600 * 1000 + 1;
      await worker.runOnce();
      expect((await delivery(id)).status, 'dropped');
    },
  );

  test(
    'an unreachable peer is tried once per pass; its other items wait',
    () async {
      final ids = [
        await queuedMessage('1'),
        await queuedMessage('2'),
        await queuedMessage('3'),
      ];
      net.next = const PeerUnreachable('down');
      await worker.runOnce();
      expect(net.calls.length, 1);
      for (final id in ids) {
        final d = await delivery(id);
        expect(d.status, 'queued');
        expect(d.nextAttemptAt, greaterThan(now));
      }
    },
  );

  group('event deliveries', () {
    Future<void> queueEvent(String id) => db
        .into(db.deliveries)
        .insert(
          DeliveriesCompanion.insert(
            messageId: id,
            recipientDeviceId: peerId,
            envelopeJson: jsonEncode({
              'path': '/relay/event',
              'payload': {'id': id},
            }),
            status: 'queued',
            nextAttemptAt: now,
            createdAt: now,
          ),
        );

    test('old peer: 404 on /relay/event keeps it queued for an hour and '
        'notifies once', () async {
      await queueEvent('e1');
      await queueEvent('e2');
      net.next = 404;
      await worker.runOnce();
      for (final id in ['e1', 'e2']) {
        final d = await delivery(id);
        expect(
          (d.status, d.nextAttemptAt, d.lastError),
          ('queued', now + tooOldRetryMs, 'too old for surat'),
        );
      }
      expect(notes.shown.map((n) => n.toString()), [
        "Xavier's Agent Relay is too old for surat — ask them to update",
      ]);

      await queueEvent('e3');
      await worker.runOnce();
      expect((await delivery('e3')).status, 'queued');
      expect(notes.shown, hasLength(1));

      // They update: the held events land.
      now += tooOldRetryMs;
      net.next = 200;
      await worker.runOnce();
      for (final id in ['e1', 'e2', 'e3']) {
        expect((await delivery(id)).status, 'delivered');
      }
    });

    test('an event dropped after 7 days says it was a surat update', () async {
      await queueEvent('e1');
      now += queueLifetimeMs + 1;
      await worker.runOnce();
      expect((await delivery('e1')).status, 'dropped');
      expect(notes.shown.map((n) => n.toString()), [
        "Couldn't reach Xavier for a surat update — "
            'The surat update waited 7 days for their Mac and was dropped.',
      ]);
    });

    group('against a 1.0.x Mac through the real PeerClient', () {
      late Directory dir;
      late ServerBootstrap old;
      late String oldFp;
      late LocalIdentity me;

      setUpAll(() async {
        dir = await tempDir('oldmac');
        me = await LocalIdentity.create(
          AppConfig(
            dataDir: Directory('${dir.path}/me'),
            peerPort: 1,
            localPort: 2,
            keychainPrefix: 'oldmac',
          ),
          InMemorySecretStore(),
          personName: 'Irfan',
          deviceName: 'A',
        );
        final cert = await realCert(Directory('${dir.path}/srv'));
        oldFp = cert.fingerprint;
        old = ServerBootstrap(
          certPath: cert.certPath,
          keyPath: cert.keyPath,
          port: 0,
          address: InternetAddress.loopbackIPv4,
        );
        // shelf_router's own 404 for a route 1.0.x never had: plain text.
        await old.start(
          handler: (req) => req.url.path == 'relay/event'
              ? Response.notFound('Route not found')
              : Response.ok(
                  '{"received":true}',
                  headers: {'content-type': 'application/json'},
                ),
        );
      });
      tearDownAll(() async {
        await old.stop();
        await dir.delete(recursive: true);
      });

      test(
        'a plain-text 404 on /relay/event is "too old", not unreachable',
        () async {
          await (db.update(db.peers)).write(
            PeersCompanion(
              lastAddress: const Value('127.0.0.1'),
              lastPort: Value(old.boundPort),
              certFingerprint: Value(oldFp),
            ),
          );
          final real = DeliveryWorker(
            db: db,
            transport: PeerClient(me, relayPort: 1, nowMs: () => now),
            messages: svc,
            notifier: notes,
            nowMs: () => now,
            onUnpaired: (id) async => unpaired.add(id),
          );
          await queueEvent('e1');
          final m = await queuedMessage();
          await real.runOnce();
          final e = await delivery('e1');
          expect(
            (e.status, e.nextAttemptAt, e.lastError),
            ('queued', now + tooOldRetryMs, 'too old for surat'),
          );
          expect((await delivery(m)).status, 'delivered');
          expect(notes.shown.map((n) => n.title), [
            "Xavier's Agent Relay is too old for surat",
          ]);
        },
      );
    });

    test('a 404 on /relay/deliver drops without the surat notice', () async {
      final id = await queuedMessage();
      net.next = 404;
      await worker.runOnce();
      expect((await delivery(id)).status, 'dropped');
      expect(notes.shown, isEmpty);
    });

    test(
      'a 403 on /relay/event backs off and retries: the event may be early',
      () async {
        await queueEvent('e1');
        net.next = 403;
        await worker.runOnce();
        final d = await delivery('e1');
        expect(
          (d.status, d.attempts, d.nextAttemptAt),
          ('queued', 1, now + 5000),
        );
        now += 5000;
        net.next = 200;
        await worker.runOnce();
        expect((await delivery('e1')).status, 'delivered');
      },
    );

    test('a 403 on /relay/deliver still drops', () async {
      final id = await queuedMessage();
      net.next = 403;
      await worker.runOnce();
      expect((await delivery(id)).status, 'dropped');
    });

    test('a 403 on a surat message backs off and retries: the sender\'s '
        'seating event may still be on its way', () async {
      await addSurat();
      final id = await queuedSuratMessage();
      net.next = 403;
      await worker.runOnce();
      final d = await delivery(id);
      expect(
        (d.status, d.attempts, d.nextAttemptAt, d.lastError),
        ('queued', 1, now + 5000, 'not_a_member'),
      );
      now += 5000;
      net.next = 200;
      await worker.runOnce();
      expect((await delivery(id)).status, 'delivered');
    });

    test(
      'a 403 on a surat message drops once the recipient has left here',
      () async {
        await addSurat();
        final id = await queuedSuratMessage();
        await (db.update(
          db.channelMembers,
        )..where((m) => m.deviceId.equals(peerId))).write(
          const ChannelMembersCompanion(
            state: Value('left'),
            leftHlc: Value('0000000000009-00000'),
          ),
        );
        net.next = 403;
        await worker.runOnce();
        expect((await delivery(id)).status, 'dropped');
      },
    );
  });

  test('401 untrusted unpairs the peer and drops its queue', () async {
    final id = await queuedMessage();
    net.next = 401;
    await worker.runOnce();
    expect(unpaired, [peerId]);
    expect((await delivery(id)).status, 'dropped');
    expect(notes.shown.single.title, 'Xavier unpaired');
  });

  test('a history copy dropped after 7 days shows no notice and leaves the message', () async {
    final id = await queuedMessage();
    await db
        .into(db.deliveries)
        .insert(
          DeliveriesCompanion.insert(
            messageId: 'history:$id:$peerId',
            recipientDeviceId: peerId,
            envelopeJson: jsonEncode({'path': '/relay/deliver', 'payload': {}}),
            status: 'queued',
            nextAttemptAt: now,
            createdAt: now,
          ),
        );
    now += 7 * 24 * 3600 * 1000 + 1;
    await worker.runOnce();
    expect((await delivery('history:$id:$peerId')).status, 'dropped');
    // Only the live copy's notice; the history copy adds none.
    expect(notes.shown, hasLength(1));
    expect((await message(id)).status, 'queued');
  });

  test(
    'receipts are sent to /relay/receipt and do not touch message status',
    () async {
      await db
          .into(db.deliveries)
          .insert(
            DeliveriesCompanion.insert(
              messageId: 'receipt:m9:seen',
              recipientDeviceId: peerId,
              envelopeJson: jsonEncode({
                'path': '/relay/receipt',
                'payload': {'messageId': 'm9', 'kind': 'seen', 'at': 1},
              }),
              status: 'queued',
              nextAttemptAt: now,
              createdAt: now,
            ),
          );
      await worker.runOnce();
      expect(net.calls.single.$2, '/relay/receipt');
    },
  );

  test('runOnce called during a pass waits for it and runs again', () async {
    await queuedMessage('first');
    final gate = Completer<void>();
    net.gate = gate;
    final firstPass = worker.runOnce(); // blocks inside the first post
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final second = await queuedMessage(
      'second',
    ); // queued after that pass looked
    net.gate = null;
    final secondCall = worker.runOnce();
    gate.complete();
    await firstPass;
    await secondCall;
    expect((await delivery(second)).status, 'delivered');
  });

  group('online status', () {
    Future<int?> lastSeen() async =>
        (await db.select(db.peers).getSingle()).lastSeenAt;
    Future<void> setLastSeen(int? at) =>
        db.update(db.peers).write(PeersCompanion(lastSeenAt: Value(at)));

    test('a delivery the peer answers marks it seen', () async {
      await setLastSeen(null);
      await queuedMessage();
      await worker.runOnce();
      expect(await lastSeen(), now);
    });

    test('an unreachable peer is not marked seen', () async {
      await setLastSeen(null);
      net.next = const PeerUnreachable('down');
      await queuedMessage();
      await worker.runOnce();
      expect(await lastSeen(), isNull);
    });

    DeliveryWorker withKeepAlive() => DeliveryWorker(
      db: db,
      transport: net,
      messages: svc,
      notifier: notes,
      nowMs: () => now,
      onUnpaired: (id) async => unpaired.add(id),
      keepAlive: const Duration(seconds: 60),
    );

    test(
      'keep-alive pings an idle peer once a minute and marks it seen',
      () async {
        final w = withKeepAlive();
        await setLastSeen(now - 61000);
        await w.runOnce();
        await pumpEventQueue();
        expect(net.calls.map((c) => c.$2), ['/relay/ping']);
        expect(await lastSeen(), now);

        await setLastSeen(now - 61000);
        await w.runOnce(); // pinged under a minute ago: not again
        await pumpEventQueue();
        expect(net.calls.length, 1);
      },
    );

    test('keep-alive pings an idle surat contact', () async {
      await (db.update(db.peers))
          .write(const PeersCompanion(trust: Value('surat_contact')));
      await setLastSeen(now - 61000);
      await withKeepAlive().runOnce();
      await pumpEventQueue();
      expect(net.calls.map((c) => c.$2), ['/relay/ping']);
    });

    test('keep-alive skips a peer heard from recently', () async {
      final w = withKeepAlive();
      await setLastSeen(now - 10000);
      await w.runOnce();
      await pumpEventQueue();
      expect(net.calls, isEmpty);
    });

    test('a 404 from an older build still counts as seen', () async {
      final w = withKeepAlive();
      await setLastSeen(now - 61000);
      net.next = 404;
      await w.runOnce();
      await pumpEventQueue();
      expect(await lastSeen(), now);
    });

    test('keep-alive is off by default', () async {
      await setLastSeen(now - 61000);
      await worker.runOnce();
      await pumpEventQueue();
      expect(net.calls, isEmpty);
    });
  });
}
