import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/sealed_box.dart';
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

  test(
    'the person seeing a message does not mark it read for the agent',
    () async {
      await sendAndDeliver(alice, bob, 'x');
      await bob.svc.read(ch, by: Reader.person);
      expect(
        await bob.svc.read(ch, unreadOnly: true, by: Reader.person),
        isEmpty,
      );
      final forAgent = await bob.svc.read(
        ch,
        unreadOnly: true,
        by: Reader.agent,
      );
      expect(forAgent.single.body, 'x');
      expect(
        await bob.svc.read(ch, unreadOnly: true, by: Reader.agent),
        isEmpty,
      );
    },
  );

  test(
    'the agent reading a message does not clear it for the person',
    () async {
      await sendAndDeliver(alice, bob, 'x');
      await bob.svc.read(ch, by: Reader.agent);
      expect(await bob.db.unreadCounts(by: Reader.person), {ch: 1});
      expect(await bob.db.unreadCounts(by: Reader.agent), isEmpty);
      await bob.svc.read(ch, by: Reader.person);
      expect(await bob.db.unreadCounts(by: Reader.person), isEmpty);
    },
  );

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

  group('surat', () {
    late Party carol;

    setUp(() async {
      carol = await make('Carol', () => 1700000000000);
    });
    tearDown(() => carol.db.close());

    /// Alice's side: bob mutual, carol not.
    Future<void> aliceSurat({
      String carolState = 'member',
      String? carolLeft,
      int? closedAt,
    }) async {
      await insertPeer(alice.db, carol.keys, name: 'Carol');
      await alice.db
          .into(alice.db.channels)
          .insert(
            ChannelsCompanion.insert(
              id: 'surat-1',
              kind: 'surat',
              createdAt: 1,
              name: const Value('Trip'),
              closedAt: Value(closedAt),
            ),
          );
      Future<void> row(
        String id, {
        String state = 'member',
        String? mine,
        String? theirs,
        String? left,
      }) => alice.db
          .into(alice.db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: 'surat-1',
              deviceId: id,
              joinedHlc: '0000000000000-00000',
              state: Value(state),
              myApproval: Value(mine),
              theirApproval: Value(theirs),
              leftHlc: Value(left),
            ),
          );
      await row(alice.id);
      await row(bob.id, mine: 'approved', theirs: 'approved');
      await row(
        carol.id,
        state: carolState,
        mine: 'approved',
        theirs: null,
        left: carolLeft,
      );
    }

    /// The receiving side: sender and I are members.
    Future<void> receiverSurat(Party me) async {
      if (me != bob) await insertPeer(me.db, alice.keys, name: 'Alice');
      await me.db
          .into(me.db.channels)
          .insert(
            ChannelsCompanion.insert(
              id: 'surat-1',
              kind: 'surat',
              createdAt: 1,
              name: const Value('Trip'),
            ),
          );
      for (final id in [alice.id, me.id]) {
        await me.db
            .into(me.db.channelMembers)
            .insert(
              ChannelMembersCompanion.insert(
                channelId: 'surat-1',
                deviceId: id,
                joinedHlc: '0000000000000-00000',
              ),
            );
      }
    }

    Future<Map<String, dynamic>> deliver(Party to) async {
      final d = await alice.svc.draft(channelId: 'surat-1', body: 'secret');
      await alice.svc.approve(d.id);
      return (await queued(
        alice,
        to,
      )).firstWhere((q) => q.$1 == '/relay/deliver').$2;
    }

    test('mutual pair reads; the other member gets a locked placeholder with the same id, hlc and seq', () async {
      await aliceSurat();
      await receiverSurat(bob);
      await receiverSurat(carol);
      final toBob = await deliver(bob);
      final toCarol = await deliver(carol);
      final b = await bob.svc.receive(
        Envelope.fromJson(toBob),
        from: await bob.peer(alice.id),
      );
      final c = await carol.svc.receive(
        Envelope.fromJson(toCarol),
        from: await carol.peer(alice.id),
      );
      expect(b.message.body, 'secret');
      expect(b.message.status, 'unread');
      expect(c.message.status, 'locked');
      expect(c.message.body, isNull);
      expect(c.message.id, b.message.id);
      expect(c.message.hlc, b.message.hlc);
      expect(c.message.seq, b.message.seq);
    });

    test('a placeholder carries no ciphertext', () async {
      await aliceSurat();
      final toCarol = await deliver(carol);
      expect(toCarol['sealed'], isNull);
      expect(jsonEncode(toCarol), isNot(contains('secret')));
    });

    test('a half-approved pair also gets a placeholder', () async {
      await aliceSurat();
      await alice.db.customStatement(
        "UPDATE channel_members SET their_approval='approved', my_approval=NULL WHERE device_id='${carol.id}'",
      );
      expect((await deliver(carol))['sealed'], isNull);
    });

    test(
      "history envelope unlocks C's placeholder without an incoming event",
      () async {
        await aliceSurat();
        await receiverSurat(carol);
        final ph = await deliver(carol);
        await carol.svc.receive(
          Envelope.fromJson(ph),
          from: await carol.peer(alice.id),
        );
        final seen = <Message>[];
        final sub = carol.svc.incoming.listen(seen.add);
        final e = Envelope.fromJson(ph);
        final plain = utf8.encode(jsonEncode({'body': 'secret'}));
        final hist = Envelope(
          id: e.id,
          channelId: e.channelId,
          kind: e.kind,
          from: e.from,
          sentAt: e.sentAt,
          hlc: e.hlc,
          seq: e.seq,
          history: true,
          sealed: await seal(
            plain,
            recipientBoxPub: carol.keys.boxPub,
            aad: e.aad,
          ),
        );
        final r = await carol.svc.receive(
          hist,
          from: await carol.peer(alice.id),
        );
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(r.message.status, 'unread');
        expect(r.message.body, 'secret');
        expect(seen, isEmpty);
      },
    );

    test('a left member gets no copy', () async {
      await aliceSurat(carolState: 'left', carolLeft: '0000000000001-00000');
      final d = await alice.svc.draft(channelId: 'surat-1', body: 'x');
      await alice.svc.approve(d.id);
      expect(await queued(alice, carol), isEmpty);
      expect((await queued(alice, bob)).length, 1);
    });

    test('drafting in an ended surat throws ChannelClosed', () async {
      await aliceSurat(closedAt: 5);
      expect(
        () => alice.svc.draft(channelId: 'surat-1', body: 'x'),
        throwsA(isA<ChannelClosed>()),
      );
    });

    test('drafting when I am not a current member throws NotAMember', () async {
      await aliceSurat();
      await alice.db.customStatement(
        "UPDATE channel_members SET state='left', left_hlc='0000000000001-00000' WHERE device_id='${alice.id}'",
      );
      expect(
        () => alice.svc.draft(channelId: 'surat-1', body: 'x'),
        throwsA(isA<NotAMember>()),
      );
    });

    test('receiving when I am only invited is refused', () async {
      await receiverSurat(bob);
      await bob.db.customStatement(
        "UPDATE channel_members SET state='invited' WHERE device_id='${bob.id}'",
      );
      await aliceSurat();
      final env = await deliver(bob);
      final from = await bob.peer(alice.id);
      expect(
        () => bob.svc.receive(Envelope.fromJson(env), from: from),
        throwsA(isA<NotAMember>()),
      );
    });

    Future<Envelope> historyFor(Envelope e, Party to, {String? from}) async =>
        Envelope(
          id: e.id,
          channelId: e.channelId,
          kind: e.kind,
          from: from ?? e.from,
          sentAt: e.sentAt,
          hlc: e.hlc,
          seq: e.seq,
          history: true,
          sealed: await seal(
            utf8.encode(jsonEncode({'body': 'forged'})),
            recipientBoxPub: to.keys.boxPub,
            aad: Envelope(
              id: e.id,
              channelId: e.channelId,
              kind: e.kind,
              from: from ?? e.from,
              sentAt: e.sentAt,
              hlc: e.hlc,
              seq: e.seq,
              sealed: null,
            ).aad,
          ),
        );

    test("a history envelope from another member cannot unlock someone else's "
        'placeholder', () async {
      await aliceSurat();
      await receiverSurat(carol);
      await carol.db
          .into(carol.db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: 'surat-1',
              deviceId: bob.id,
              joinedHlc: '0000000000000-00000',
            ),
          );
      await insertPeer(carol.db, bob.keys, name: 'Bob');
      final ph = Envelope.fromJson(await deliver(carol));
      // the placeholder is attributed to Alice; Bob tries to fill it
      await carol.svc.receive(ph, from: await carol.peer(alice.id));
      final forged = await historyFor(ph, carol, from: bob.id);
      await carol.svc.receive(forged, from: await carol.peer(bob.id));
      final row = await (carol.db.select(
        carol.db.messages,
      )..where((m) => m.id.equals(ph.id))).getSingle();
      expect(row.status, 'locked');
      expect(row.body, isNull);
      expect(row.fromDeviceId, alice.id);
    });

    test(
      'a history envelope for another channel cannot unlock the row',
      () async {
        await aliceSurat();
        await receiverSurat(carol);
        await carol.db
            .into(carol.db.channels)
            .insert(
              ChannelsCompanion.insert(
                id: 'surat-2',
                kind: 'surat',
                createdAt: 1,
              ),
            );
        for (final id in [alice.id, carol.id]) {
          await carol.db
              .into(carol.db.channelMembers)
              .insert(
                ChannelMembersCompanion.insert(
                  channelId: 'surat-2',
                  deviceId: id,
                  joinedHlc: '0000000000000-00000',
                ),
              );
        }
        final ph = Envelope.fromJson(await deliver(carol));
        await carol.svc.receive(ph, from: await carol.peer(alice.id));
        final other = Envelope(
          id: ph.id,
          channelId: 'surat-2',
          kind: ph.kind,
          from: ph.from,
          sentAt: ph.sentAt,
          hlc: ph.hlc,
          seq: ph.seq,
          history: true,
          sealed: await seal(
            utf8.encode(jsonEncode({'body': 'forged'})),
            recipientBoxPub: carol.keys.boxPub,
            aad: Envelope(
              id: ph.id,
              channelId: 'surat-2',
              kind: ph.kind,
              from: ph.from,
              sentAt: ph.sentAt,
              hlc: ph.hlc,
              seq: ph.seq,
              sealed: null,
            ).aad,
          ),
        );
        await carol.svc.receive(other, from: await carol.peer(alice.id));
        final row = await (carol.db.select(
          carol.db.messages,
        )..where((m) => m.id.equals(ph.id))).getSingle();
        expect(row.status, 'locked');
        expect(row.channelId, 'surat-1');
        expect(row.body, isNull);
      },
    );

    test('approving a draft after I left throws NotAMember and sends nothing', () async {
      await aliceSurat();
      final d = await alice.svc.draft(channelId: 'surat-1', body: 'x');
      await alice.db.customStatement(
        "UPDATE channel_members SET state='left', left_hlc='0000000000001-00000' WHERE device_id='${alice.id}'",
      );
      await expectLater(alice.svc.approve(d.id), throwsA(isA<NotAMember>()));
      expect(await queued(alice, bob), isEmpty);
      final row = await (alice.db.select(
        alice.db.messages,
      )..where((m) => m.id.equals(d.id))).getSingle();
      expect(row.status, 'awaiting_approval');
    });
  });
}
