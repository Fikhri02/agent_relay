import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/messaging/envelope.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Two parties wired by hand: each has the other as a paired peer and both
/// share one private channel. Delivery is simulated by reading the sender's
/// queued envelopes.
class Party {
  Party(this.name, this.keys, this.db, this.svc, this.wall);
  final String name;
  final IdentityKeys keys;
  final RelayDatabase db;
  final MessageService svc;
  final int Function() wall;
  String get id => deviceIdFor(keys.signPub, keys.boxPub);
  Future<Peer> peer(String deviceId) => (db.select(
    db.peers,
  )..where((p) => p.deviceId.equals(deviceId))).getSingle();
}

void main() {
  late Party alice, bob;
  late String ch;
  var aliceNow = 1700000000000, bobNow = 1700000000000;

  Future<Party> make(String name, int Function() wall) async {
    final keys = await IdentityKeys.generate();
    final db = memoryDb();
    final svc = MessageService(
      db: db,
      myDeviceId: deviceIdFor(keys.signPub, keys.boxPub),
      myBox: keys.box,
      clock: HlcClock(nowMs: wall),
      nowMs: wall,
    );
    return Party(name, keys, db, svc, wall);
  }

  Future<void> link(Party me, Party other) async {
    await insertPeer(me.db, other.keys, name: other.name);
    await me.db
        .into(me.db.channels)
        .insert(
          ChannelsCompanion.insert(id: ch, kind: 'private', createdAt: 1),
        );
    for (final id in [me.id, other.id]) {
      await me.db
          .into(me.db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: ch,
              deviceId: id,
              joinedHlc: '0000000000000-00000',
            ),
          );
    }
  }

  setUp(() async {
    aliceNow = 1700000000000;
    bobNow = 1700000000000;
    alice = await make('Alice', () => aliceNow);
    bob = await make('Bob', () => bobNow);
    ch = privateChannelId(alice.id, bob.id);
    await link(alice, bob);
    await link(bob, alice);
  });
  tearDown(() async {
    await alice.db.close();
    await bob.db.close();
  });

  /// Everything [from] has queued for [to], as (path, payload).
  Future<List<(String, Map<String, dynamic>)>> queued(
    Party from,
    Party to,
  ) async {
    final rows =
        await (from.db.select(from.db.deliveries)..where(
              (d) =>
                  d.recipientDeviceId.equals(to.id) & d.status.equals('queued'),
            ))
            .get();
    return [
      for (final r in rows)
        (
          (jsonDecode(r.envelopeJson) as Map)['path'] as String,
          ((jsonDecode(r.envelopeJson) as Map)['payload'] as Map)
              .cast<String, dynamic>(),
        ),
    ];
  }

  Future<Message> sendAndDeliver(Party from, Party to, String body) async {
    final d = await from.svc.draft(channelId: ch, body: body);
    await from.svc.approve(d.id);
    final env = (await queued(
      from,
      to,
    )).firstWhere((q) => q.$1 == '/relay/deliver');
    final r = await to.svc.receive(
      Envelope.fromJson(env.$2),
      from: await to.peer(from.id),
    );
    return r.message;
  }

  test(
    'body of exactly 32768 UTF-8 bytes is accepted; 32769 is rejected',
    () async {
      final atLimit = 'é' * 16384;
      expect(
        (await alice.svc.draft(channelId: ch, body: atLimit)).status,
        'awaiting_approval',
      );
      expect(
        () => alice.svc.draft(channelId: ch, body: '${atLimit}x'),
        throwsA(isA<BodyTooLarge>()),
      );
    },
  );

  test(
    'draft has no hlc/seq and is not in the timeline until approved',
    () async {
      final d = await alice.svc.draft(channelId: ch, body: 'hi');
      expect(d.hlc, isNull);
      expect(d.seq, isNull);
      expect(await alice.db.channelMessages(ch), isEmpty);
    },
  );

  test('draft on a closed or unknown channel is refused', () async {
    await (alice.db.update(alice.db.channels)..where((c) => c.id.equals(ch)))
        .write(const ChannelsCompanion(closedAt: Value(5)));
    expect(
      () => alice.svc.draft(channelId: ch, body: 'x'),
      throwsA(isA<ChannelClosed>()),
    );
    expect(
      () => alice.svc.draft(channelId: 'nope', body: 'x'),
      throwsA(isA<UnknownChannel>()),
    );
  });

  test(
    'approve assigns hlc + seq 1, 2 and queues one delivery per paired member',
    () async {
      final d1 = await alice.svc.draft(channelId: ch, body: 'one');
      final d2 = await alice.svc.draft(channelId: ch, body: 'two');
      final a1 = await alice.svc.approve(d1.id);
      final a2 = await alice.svc.approve(d2.id);
      expect(a1.status, 'queued');
      expect(a1.hlc, isNotNull);
      expect([a1.seq, a2.seq], [1, 2]);
      expect(
        Hlc.decode(a2.hlc!).compareTo(Hlc.decode(a1.hlc!)),
        greaterThan(0),
      );
      expect((await queued(alice, bob)).length, 2);
    },
  );

  test(
    'approve twice is a no-op; approve after discard does nothing',
    () async {
      final d = await alice.svc.draft(channelId: ch, body: 'x');
      await alice.svc.approve(d.id);
      await alice.svc.approve(d.id);
      expect((await queued(alice, bob)).length, 1);
      final d2 = await alice.svc.draft(channelId: ch, body: 'y');
      await alice.svc.discard(d2.id);
      expect((await alice.svc.approve(d2.id)).status, 'discarded');
      expect((await queued(alice, bob)).length, 1);
    },
  );

  test('receive decrypts and stores unread; the same envelope again is a duplicate', () async {
    final d = await alice.svc.draft(
      channelId: ch,
      body: 'staging is busy',
      context: {'repo': 'Middleware'},
    );
    await alice.svc.approve(d.id);
    final env = Envelope.fromJson((await queued(alice, bob)).single.$2);
    final r1 = await bob.svc.receive(env, from: await bob.peer(alice.id));
    expect(r1.duplicate, isFalse);
    expect(r1.message.body, 'staging is busy');
    expect(jsonDecode(r1.message.contextJson!), {'repo': 'Middleware'});
    expect(r1.message.status, 'unread');
    final r2 = await bob.svc.receive(env, from: await bob.peer(alice.id));
    expect(r2.duplicate, isTrue);
    expect((await bob.db.channelMessages(ch)).length, 1);
  });

  test(
    'tampered envelope (aad field changed) is stored as locked, not read',
    () async {
      final d = await alice.svc.draft(channelId: ch, body: 'secret');
      await alice.svc.approve(d.id);
      final json = (await queued(alice, bob)).single.$2;
      json['seq'] = 99;
      final r = await bob.svc.receive(
        Envelope.fromJson(json),
        from: await bob.peer(alice.id),
      );
      expect(r.message.status, 'locked');
      expect(r.message.body, isNull);
    },
  );

  test('sender not a member of the channel is refused', () async {
    final carol = await IdentityKeys.generate();
    await insertPeer(bob.db, carol, name: 'Carol');
    final carolPeer = await bob.peer(deviceIdFor(carol.signPub, carol.boxPub));
    final d = await alice.svc.draft(channelId: ch, body: 'x');
    await alice.svc.approve(d.id);
    final env = Envelope.fromJson((await queued(alice, bob)).single.$2);
    expect(
      () => bob.svc.receive(env, from: carolPeer),
      throwsA(isA<NotAMember>()),
    );
  });

  test('received at sentAt + 121 s is marked arrivedLate', () async {
    final d = await alice.svc.draft(channelId: ch, body: 'x');
    await alice.svc.approve(d.id);
    bobNow += 121000;
    final env = Envelope.fromJson((await queued(alice, bob)).single.$2);
    final r = await bob.svc.receive(env, from: await bob.peer(alice.id));
    expect(r.message.arrivedLate, isTrue);
  });

  test('a reply sent after reading sorts after the original even with a slower sender clock', () async {
    await sendAndDeliver(alice, bob, 'question');
    bobNow -= 60000; // Bob's clock is a minute behind
    await bob.svc.read(ch, by: Reader.agent);
    await sendAndDeliver(bob, alice, 'answer');
    final timeline = await alice.db.channelMessages(ch);
    expect(timeline.map((m) => m.body), ['question', 'answer']);
  });

  test('read marks returned unread messages read', () async {
    await sendAndDeliver(alice, bob, 'x');
    final first = await bob.svc.read(ch, unreadOnly: true, by: Reader.agent);
    expect(first.single.status, 'unread');
    expect(await bob.svc.read(ch, unreadOnly: true, by: Reader.agent), isEmpty);
    expect((await bob.db.channelMessages(ch)).single.status, 'read');
  });

  group('read receipts', () {
    test('agent read queues one agent_read receipt to the sender; the sender records it', () async {
      final m = await sendAndDeliver(alice, bob, 'x');
      bobNow += 5000;
      await bob.svc.read(ch, by: Reader.agent);
      await bob.svc.read(ch, by: Reader.agent);
      final receipts = (await queued(
        bob,
        alice,
      )).where((q) => q.$1 == '/relay/receipt').toList();
      expect(receipts.length, 1);
      expect(receipts.single.$2, {
        'messageId': m.id,
        'kind': 'agent_read',
        'at': bobNow,
      });
      await alice.svc.handleReceipt(
        receipts.single.$2,
        from: await alice.peer(bob.id),
      );
      final r = (await alice.svc.receiptsFor(m.id)).single;
      expect(r.agentReadAt, bobNow);
      expect(r.seenAt, isNull);
      expect(r.personName, 'Bob');
    });

    test('person seeing it in the app queues a seen receipt', () async {
      await sendAndDeliver(alice, bob, 'x');
      await bob.svc.read(ch, by: Reader.person);
      final kinds = (await queued(
        bob,
        alice,
      )).map((q) => q.$2['kind']).toList();
      expect(kinds, ['seen']);
    });

    test('a receipt for a message the peer never got is ignored', () async {
      final ok = await alice.svc.handleReceipt({
        'messageId': 'nope',
        'kind': 'seen',
        'at': 1,
      }, from: await alice.peer(bob.id));
      expect(ok, isFalse);
    });

    test('marking delivered records deliveredAt', () async {
      final d = await alice.svc.draft(channelId: ch, body: 'x');
      await alice.svc.approve(d.id);
      aliceNow += 700;
      await alice.svc.markDelivered(d.id, bob.id);
      final r = (await alice.svc.receiptsFor(d.id)).single;
      expect(r.deliveredAt, aliceNow);
      expect(
        (await (alice.db.select(
          alice.db.messages,
        )..where((m) => m.id.equals(d.id))).getSingle()).status,
        'sent',
      );
    });
  });

  test('an envelope stamped more than 60 s in the future is refused and does not jam the clock', () async {
    final d = await alice.svc.draft(channelId: ch, body: 'x');
    await alice.svc.approve(d.id);
    final json = (await queued(alice, bob)).single.$2;
    json['hlc'] = '9999999999999-99999';
    final from = await bob.peer(alice.id);
    await expectLater(
      bob.svc.receive(Envelope.fromJson(json), from: from),
      throwsA(isA<BadEnvelope>()),
    );
    final mine = await bob.svc.draft(channelId: ch, body: 'still works');
    expect((await bob.svc.approve(mine.id)).status, 'queued');
  });

  test('a malformed stamp is a BadEnvelope', () async {
    final d = await alice.svc.draft(channelId: ch, body: 'x');
    await alice.svc.approve(d.id);
    final json = (await queued(alice, bob)).single.$2;
    json['hlc'] = 'nonsense';
    final from = await bob.peer(alice.id);
    await expectLater(
      bob.svc.receive(Envelope.fromJson(json), from: from),
      throwsA(isA<BadEnvelope>()),
    );
  });

  test(
    'two approvals at once queue one delivery and keep sequence numbers whole',
    () async {
      final d = await alice.svc.draft(channelId: ch, body: 'once');
      await Future.wait([alice.svc.approve(d.id), alice.svc.approve(d.id)]);
      expect((await queued(alice, bob)).length, 1);
      final first = await (alice.db.select(
        alice.db.messages,
      )..where((m) => m.id.equals(d.id))).getSingle();
      expect(first.seq, 1);
      final d2 = await alice.svc.draft(channelId: ch, body: 'next');
      expect((await alice.svc.approve(d2.id)).seq, 2);
      final sent = (await queued(alice, bob)).map((q) => q.$2['seq']).toList()
        ..sort();
      expect(sent, [1, 2]);
    },
  );

  test(
    'approving a draft older than 1 hour expires it instead of sending',
    () async {
      final d = await alice.svc.draft(channelId: ch, body: 'old');
      aliceNow += 60 * 60 * 1000 + 1;
      expect((await alice.svc.approve(d.id)).status, 'expired');
      expect(await queued(alice, bob), isEmpty);
    },
  );
}
