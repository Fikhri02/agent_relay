import 'dart:async';
import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/messaging/delivery_worker.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/node/notifier.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/peer/peer_client.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

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

  test('401 untrusted unpairs the peer and drops its queue', () async {
    final id = await queuedMessage();
    net.next = 401;
    await worker.runOnce();
    expect(unpaired, [peerId]);
    expect((await delivery(id)).status, 'dropped');
    expect(notes.shown.single.title, 'Xavier unpaired');
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
