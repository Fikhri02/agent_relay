import 'dart:convert';

import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/messaging/envelope.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/surat/surat_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/surat_side.dart';

void main() {
  late Side alice, bob, carol;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    now = 1700000000000;
    alice = await Side.make('Alice');
    bob = await Side.make('Bob');
    carol = await Side.make('Carol');
    await alice.pair(bob);
    await alice.pair(carol);
    await bob.pair(alice);
    await carol.pair(alice);
  });
  tearDown(() async {
    for (final s in [alice, bob, carol]) {
      await s.db.close();
    }
  });

  /// Hands everything [from] has queued for [to] over, the way the worker
  /// would, in queue order. Returns the delivery ids handed over.
  Future<List<String>> flush(Side from, Side to) async {
    final rows =
        await (from.db.select(from.db.deliveries)
              ..where(
                (d) =>
                    d.recipientDeviceId.equals(to.id) &
                    d.status.equals('queued'),
              )
              ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]))
            .get();
    final peer = await to.peerOf(from);
    for (final d in rows) {
      final json = jsonDecode(d.envelopeJson) as Map;
      final env = Envelope.fromJson(
        (json['payload'] as Map).cast<String, dynamic>(),
      );
      if (json['path'] == eventPath) {
        await to.surat.receiveEvent(env, from: peer);
      } else if (!d.messageId.startsWith('receipt:')) {
        await to.messages.receive(env, from: peer);
      }
      await from.messages.markDelivered(d.messageId, to.id);
    }
    return [for (final d in rows) d.messageId];
  }

  Future<String> send(Side s, String suratId, String body) async {
    now += 1000;
    final d = await s.messages.draft(channelId: suratId, body: body);
    await s.messages.approve(d.id);
    return d.id;
  }

  Future<List<Message>> inbox(Side s, String suratId) =>
      s.db.channelMessages(suratId);

  /// Alice's "Trip" with Bob a member on both Macs.
  Future<String> tripWithBob() async {
    final draft = await alice.surat.draftCreate('Trip', [bob.id]);
    await alice.messages.approve(draft);
    final suratId = (await alice.message(draft)).channelId;
    await flush(alice, bob);
    now += 1000;
    await bob.surat.decide('invite:$suratId:${bob.id}', approve: true);
    await flush(bob, alice);
    return suratId;
  }

  /// Alice invites Carol; Carol accepts; Bob has not decided yet.
  Future<String> carolInvited(String suratId) async {
    final invite = await alice.surat.draftInvite(suratId, carol.id);
    await alice.messages.approve(invite);
    await flush(alice, bob);
    await flush(alice, carol);
    now += 1000;
    await carol.surat.decide('invite:$suratId:${carol.id}', approve: true);
    await flush(carol, alice);
    await flush(carol, bob);
    return 'newcomer:$suratId:${carol.id}';
  }

  Future<List<Delivery>> historyFor(Side from, Side to) =>
      (from.db.select(from.db.deliveries)..where(
            (d) =>
                d.recipientDeviceId.equals(to.id) &
                d.messageId.like('history:%'),
          ))
          .get();

  test('on approval the newcomer gets the approver\'s own messages, never a third member\'s', () async {
    final suratId = await tripWithBob();
    final a1 = await send(alice, suratId, 'alice one');
    final b1 = await send(bob, suratId, 'bob one');
    await flush(alice, bob);
    await flush(bob, alice);
    final newcomer = await carolInvited(suratId);
    await flush(alice, carol);

    now += 1000;
    await bob.surat.decide(newcomer, approve: true);
    await flush(bob, alice);
    await flush(bob, carol);
    await flush(alice, carol);

    final seen = await inbox(carol, suratId);
    final byId = {for (final m in seen) m.id: m};
    expect(byId[a1]!.body, 'alice one');
    expect(byId[b1]!.body, 'bob one');
    // Each sender shared only its own: no copy of Bob's message came from
    // Alice, none of Alice's from Bob.
    for (final d in await historyFor(alice, carol)) {
      expect(d.messageId, isNot(contains(b1)));
    }
    for (final d in await historyFor(bob, carol)) {
      expect(d.messageId, isNot(contains(a1)));
    }
    expect((await historyFor(bob, carol)).map((d) => d.messageId), [
      'history:$b1:${carol.id}',
    ]);
    expect((await historyFor(alice, carol)).map((d) => d.messageId), [
      'history:$a1:${carol.id}',
    ]);
  });

  test('history keeps original stamps and fills gaps', () async {
    final suratId = await tripWithBob();
    final ids = [
      for (var i = 1; i <= 4; i++) await send(alice, suratId, 'm$i'),
    ];
    await flush(alice, bob);
    // Bob only ever got the first and the last of them.
    await (bob.db.delete(
      bob.db.messages,
    )..where((m) => m.id.isIn([ids[1], ids[2]]))).go();
    expect((await bob.db.gaps(suratId)).single.missing, 2);
    final before = await alice.db.channelMessages(suratId);

    final n = await alice.messages.reshareOwn(suratId, await alice.peerOf(bob));
    await flush(alice, bob);

    expect(n, 4);
    expect(await bob.db.gaps(suratId), isEmpty);
    final mine = [
      for (final m in await inbox(bob, suratId))
        if (m.kind == 'message') m,
    ];
    expect([for (final m in mine) m.id], ids);
    expect(
      [for (final m in mine) m.hlc],
      [
        for (final m in before)
          if (m.kind == 'message') m.hlc,
      ],
    );
    expect([for (final m in mine) m.seq], [1, 2, 3, 4]);
    expect([for (final m in mine) m.body], ['m1', 'm2', 'm3', 'm4']);
  });

  test('history raises no notification', () async {
    final suratId = await tripWithBob();
    await send(alice, suratId, 'hello');
    // Bob never got the live copy; only the history copy reaches him.
    await alice.db.delete(alice.db.deliveries).go();
    final heard = <Message>[];
    final sub = bob.messages.incoming.listen(heard.add);

    await alice.messages.reshareOwn(suratId, await alice.peerOf(bob));
    await flush(alice, bob);
    await settle();
    await sub.cancel();

    expect(heard, isEmpty);
    expect(
      (await inbox(bob, suratId)).where((m) => m.kind == 'message'),
      hasLength(1),
    );
  });

  test('a history copy refreshes open views (changes) and is never marked '
      'arrived late', () async {
    final suratId = await tripWithBob();
    final id = await send(alice, suratId, 'old news');
    // Bob never got the live copy; the history copy comes much later.
    await alice.db.delete(alice.db.deliveries).go();
    now += 60 * 60 * 1000;
    final changed = <Message>[];
    final sub = bob.messages.changes.listen(changed.add);

    await alice.messages.reshareOwn(suratId, await alice.peerOf(bob));
    await flush(alice, bob);
    await settle();
    await sub.cancel();

    expect(changed.map((m) => m.id), contains(id));
    final row = (await inbox(bob, suratId)).firstWhere((m) => m.id == id);
    expect((row.body, row.arrivedLate), ('old news', false));
  });

  test('decline then approve between existing members unlocks earlier placeholders on both sides', () async {
    final suratId = await tripWithBob();
    final newcomer = await carolInvited(suratId);
    await flush(alice, carol);
    // Bob declines Carol: Bob and Carol cannot read each other yet.
    now += 1000;
    await bob.surat.decide(newcomer, approve: false);
    await flush(bob, alice);
    await flush(bob, carol);
    final fromBob = await send(bob, suratId, 'bob to all');
    final fromCarol = await send(carol, suratId, 'carol to all');
    await flush(bob, carol);
    await flush(carol, bob);
    expect((await bob.message(fromCarol)).status, 'locked');
    expect((await carol.message(fromBob)).status, 'locked');
    expect((await carol.message(fromBob)).body, isNull);

    now += 1000;
    await bob.surat.decide(newcomer, approve: true);
    await flush(bob, alice);
    await flush(bob, carol);
    await flush(carol, bob);

    expect((await carol.message(fromBob)).body, 'bob to all');
    expect((await carol.message(fromBob)).status, isNot('locked'));
    expect((await bob.message(fromCarol)).body, 'carol to all');
    expect((await bob.message(fromCarol)).status, isNot('locked'));
  });

  test('a placeholder read while locked is unread once it unlocks, and '
      'reading it then sends the receipts', () async {
    final suratId = await tripWithBob();
    final newcomer = await carolInvited(suratId);
    await flush(alice, carol);
    now += 1000;
    await bob.surat.decide(newcomer, approve: false);
    await flush(bob, alice);
    await flush(bob, carol);
    final fromBob = await send(bob, suratId, 'bob to all');
    await flush(bob, carol);
    // Carol's agent and Carol herself open the surat while it is locked.
    for (final by in Reader.values) {
      await carol.messages.read(suratId, by: by);
    }

    now += 1000;
    await bob.surat.decide(newcomer, approve: true);
    await flush(bob, carol);

    for (final by in Reader.values) {
      expect(
        (await carol.messages.read(
          suratId,
          unreadOnly: true,
          by: by,
        )).map((m) => (m.id, m.body)),
        [(fromBob, 'bob to all')],
        reason: by.name,
      );
    }
    final receipts = await (carol.db.select(
      carol.db.deliveries,
    )..where((d) => d.messageId.like('receipt:$fromBob:%'))).get();
    expect(receipts.map((d) => d.messageId).toSet(), {
      'receipt:$fromBob:agent_read',
      'receipt:$fromBob:seen',
    });
  });

  test('re-sharing twice queues no duplicate', () async {
    final suratId = await tripWithBob();
    await send(alice, suratId, 'once');
    final bobPeer = await alice.peerOf(bob);

    final first = await alice.messages.reshareOwn(suratId, bobPeer);
    final second = await alice.messages.reshareOwn(suratId, bobPeer);

    expect((first, second), (1, 0));
    expect(await historyFor(alice, bob), hasLength(1));
  });

  test(
    'a delivered history copy leaves the original message untouched',
    () async {
      final suratId = await tripWithBob();
      final id = await send(alice, suratId, 'still queued');
      final bobPeer = await alice.peerOf(bob);
      await alice.messages.reshareOwn(suratId, bobPeer);
      final before = await alice.message(id);
      final receiptsBefore = await alice.messages.receiptsFor(id);

      await alice.messages.markDelivered('history:$id:${bob.id}', bob.id);

      final after = await alice.message(id);
      expect(
        (after.status, after.hlc, after.seq),
        (before.status, before.hlc, before.seq),
      );
      expect(before.status, 'queued');
      final receiptsAfter = await alice.messages.receiptsFor(id);
      expect(
        [for (final r in receiptsAfter) (r.deviceId, r.deliveredAt)],
        [for (final r in receiptsBefore) (r.deviceId, r.deliveredAt)],
      );
    },
  );

  test(
    'drafts, discarded, expired and incoming rows are never re-shared',
    () async {
      final suratId = await tripWithBob();
      final draft = await alice.messages.draft(
        channelId: suratId,
        body: 'draft',
      );
      final dropped = await alice.messages.draft(
        channelId: suratId,
        body: 'no',
      );
      await alice.messages.discard(dropped.id);
      final late = await alice.messages.draft(channelId: suratId, body: 'late');
      await (alice.db.update(alice.db.messages)
            ..where((m) => m.id.equals(late.id)))
          .write(const MessagesCompanion(status: Value('expired')));
      await send(bob, suratId, 'from bob');
      await flush(bob, alice);
      final bobPeer = await alice.peerOf(bob);

      expect(await alice.messages.reshareOwn(suratId, bobPeer), 0);
      expect(await historyFor(alice, bob), isEmpty);
      expect((await alice.message(draft.id)).status, 'awaiting_approval');

      final sent = await send(alice, suratId, 'real');
      expect(await alice.messages.reshareOwn(suratId, bobPeer), 1);
      expect(
        (await historyFor(alice, bob)).single.messageId,
        'history:$sent:${bob.id}',
      );
    },
  );

  test('a failing re-share leaves the committed decision and runs after the commit', () async {
    final suratId = await tripWithBob();
    final newcomer = await carolInvited(suratId);
    final spy = _Spy(bob);
    final service = SuratService(
      db: bob.db,
      messages: spy,
      keys: bob.keys,
      me: bob.surat.me,
      clock: bob.surat.clock,
      nowMs: () => now,
    );
    spy.publishEvent = service.publish;

    now += 1000;
    await service.decide(newcomer, approve: true);

    expect(spy.calls, 1);
    expect(spy.insideTransaction, isFalse);
    expect(
      (await bob.member(suratId, carol.id))!.myApproval,
      'approved',
      reason: 'the decision stays committed although the re-share threw',
    );
    expect((await bob.db.drafts()), isEmpty);
  });

  test(
    'a dropped history copy is queued again when the pair becomes mutual again',
    () async {
      final suratId = await tripWithBob();
      final id = await send(alice, suratId, 'again');
      final bobPeer = await alice.peerOf(bob);
      await alice.messages.reshareOwn(suratId, bobPeer);
      final key = 'history:$id:${bob.id}';
      await (alice.db.update(alice.db.deliveries)
            ..where((d) => d.messageId.equals(key)))
          .write(const DeliveriesCompanion(status: Value('dropped')));

      expect(await alice.messages.reshareOwn(suratId, bobPeer), 1);

      final row = (await historyFor(alice, bob)).single;
      expect((row.messageId, row.status, row.attempts), (key, 'queued', 0));
    },
  );
}

class _Spy extends MessageService {
  _Spy(Side s)
    : db_ = s.db,
      super(
        db: s.db,
        myDeviceId: s.id,
        myBox: s.keys.box,
        clock: s.surat.clock,
        nowMs: () => now,
      );
  final RelayDatabase db_;
  int calls = 0;
  bool? insideTransaction;

  @override
  Future<int> reshareOwn(String channelId, Peer to) async {
    calls++;
    // ignore: invalid_use_of_internal_member
    insideTransaction = db_.resolvedEngine != db_;
    throw StateError('boom');
  }
}
