import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:agent_relay/surat/surat_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/surat_side.dart';

void main() {
  late Side alice, bob, carol;

  // Each side has its own in-memory database on purpose.
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
    await alice.db.close();
    await bob.db.close();
    await carol.db.close();
  });

  /// Alice creates "Trip" with [invitees] and approves it.
  Future<String> created(List<Side> invitees) async {
    final draftId = await alice.surat.draftCreate('Trip', [
      for (final s in invitees) s.id,
    ]);
    await alice.messages.approve(draftId);
    return (await alice.message(draftId)).channelId;
  }

  /// Bob accepts on his Mac; Alice stores his accept.
  Future<void> bobAccepts(String suratId) async {
    now += 1000;
    await alice.storeIncoming(
      suratId,
      from: bob,
      hlc: Hlc(now, 0).encode(),
      event: const AcceptEvent(),
    );
    await alice.surat.rebuild(suratId);
    now += 1000;
  }

  test(
    'draftCreate makes a surat with me as member and one awaiting draft',
    () async {
      final draftId = await alice.surat.draftCreate('Trip', [bob.id, carol.id]);
      final draft = await alice.message(draftId);
      expect(draft.kind, 'event');
      expect(draft.status, 'awaiting_approval');
      expect(draft.direction, 'out');
      expect(draft.hlc, isNull);
      final event = SuratEvent.fromJson(jsonDecode(draft.body!) as Map);
      expect(event, isA<CreateEvent>());
      final create = event as CreateEvent;
      expect(create.name, 'Trip');
      expect(create.invitees.map((c) => c.deviceId), [bob.id, carol.id]);
      for (final c in create.invitees) {
        expect(
          await checkVouch(
            alice.keys.signPub,
            draft.channelId,
            c,
            create.vouches[c.deviceId]!,
          ),
          isTrue,
        );
      }

      final channel = (await alice.channel(draft.channelId))!;
      expect(channel.kind, 'surat');
      expect(channel.name, 'Trip');
      expect(channel.creatorDeviceId, alice.id);
      final members = await alice.members(draft.channelId);
      expect(members.map((m) => (m.deviceId, m.state)), [(alice.id, 'member')]);
      expect(await alice.db.drafts(), hasLength(1));
    },
  );

  test('an empty name or no invitee is refused', () async {
    expect(
      () => alice.surat.draftCreate('  ', [bob.id]),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => alice.surat.draftCreate('Trip', []),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('discarding the create draft removes the surat', () async {
    final draftId = await alice.surat.draftCreate('Trip', [bob.id]);
    final suratId = (await alice.message(draftId)).channelId;
    await alice.messages.discard(draftId);
    expect(await alice.channel(suratId), isNull);
    expect(await alice.members(suratId), isEmpty);
    expect((await alice.message(draftId)).status, 'discarded');
  });

  test('an expired create draft removes the surat', () async {
    final draftId = await alice.surat.draftCreate('Trip', [bob.id]);
    final suratId = (await alice.message(draftId)).channelId;
    now += draftLifetimeMs + 1;
    expect((await alice.messages.approve(draftId)).status, 'expired');
    expect(await alice.channel(suratId), isNull);
    expect(await alice.members(suratId), isEmpty);
  });

  test(
    'approving it queues a create event to each invitee on /relay/event',
    () async {
      final draftId = await alice.surat.draftCreate('Trip', [bob.id, carol.id]);
      final sent = await alice.messages.approve(draftId);
      expect(sent.status, 'queued');
      expect(sent.hlc, isNotNull);
      expect(sent.seq, 0);
      for (final to in [bob, carol]) {
        final q = await alice.queuedFor(to, draftId);
        expect(q.path, '/relay/event');
        expect(q.env.kind, 'event');
        expect(q.env.seq, 0);
        expect(q.env.hlc, sent.hlc);
        expect(q.env.from, alice.id);
        expect(q.env.channelId, sent.channelId);
        expect((q.event as CreateEvent).name, 'Trip');
      }

      final members = await alice.members(sent.channelId);
      expect(
        {for (final m in members) m.deviceId: m.state},
        {alice.id: 'member', bob.id: 'invited', carol.id: 'invited'},
      );
      final mine = await alice.member(sent.channelId, alice.id);
      expect(mine!.joinedHlc, sent.hlc);
      final bobRow = (await alice.member(sent.channelId, bob.id))!;
      expect(bobRow.inviterDeviceId, alice.id);
      expect(bobRow.joinedHlc, sent.hlc);
      expect(bobRow.myApproval, 'approved');
      expect(bobRow.theirApproval, isNull);
      expect(bobRow.personName, 'Bob');
    },
  );

  test('a surat message draft is not an event and still sends', () async {
    final suratId = await created([bob]);
    await bobAccepts(suratId);
    final d = await alice.messages.draft(channelId: suratId, body: 'hi');
    expect((await alice.messages.approve(d.id)).status, 'queued');
    expect((await alice.message(d.id)).seq, 1);
  });

  test('inviting a non-paired device throws', () async {
    final suratId = await created([bob]);
    final stranger = await IdentityKeys.generate();
    final strangerId = deviceIdFor(stranger.signPub, stranger.boxPub);
    expect(
      () => alice.surat.draftInvite(suratId, strangerId),
      throwsA(isA<UnknownPeer>()),
    );
    await insertPeer(alice.db, stranger, trust: 'surat_contact');
    expect(
      () => alice.surat.draftInvite(suratId, strangerId),
      throwsA(isA<UnknownPeer>()),
    );
    expect(
      () => alice.surat.draftCreate('Other', [strangerId]),
      throwsA(isA<UnknownPeer>()),
    );
  });

  test('a sixth seat throws TooManyMembers', () async {
    final extra = <Side>[];
    for (final n in ['Dan', 'Eve', 'Fay']) {
      final s = await Side.make(n);
      await alice.pair(s);
      extra.add(s);
    }
    expect(
      () => alice.surat.draftCreate('Big', [
        bob.id,
        carol.id,
        for (final s in extra) s.id,
      ]),
      throwsA(isA<TooManyMembers>()),
    );
    final suratId = await created([bob, carol, extra[0], extra[1]]);
    expect(
      () => alice.surat.draftInvite(suratId, extra[2].id),
      throwsA(isA<TooManyMembers>()),
    );
    for (final s in extra) {
      await s.db.close();
    }
  });

  test('rename by a non-renamer throws NotAllowed', () async {
    // Bob's surat, which Alice joined: Bob renames, Alice may not.
    const suratId = 'bob-surat';
    await alice.db
        .into(alice.db.channels)
        .insert(
          ChannelsCompanion.insert(
            id: suratId,
            kind: 'surat',
            createdAt: now,
            name: const Value('Lunch'),
            creatorDeviceId: Value(bob.id),
          ),
        );
    await alice.storeIncoming(
      suratId,
      from: bob,
      hlc: Hlc(now, 0).encode(),
      event: CreateEvent(
        name: 'Lunch',
        invitees: [alice.card],
        vouches: {alice.id: await vouch(bob.keys.signing, suratId, alice.card)},
      ),
    );
    await alice.storeIncoming(
      suratId,
      from: alice,
      hlc: Hlc(now + 1, 0).encode(),
      event: const AcceptEvent(),
    );
    await alice.surat.rebuild(suratId);
    expect((await alice.member(suratId, alice.id))!.state, 'member');
    expect(
      () => alice.surat.draftRename(suratId, 'Dinner'),
      throwsA(isA<NotAllowed>()),
    );

    // On her own surat she is the renamer.
    now += 1000;
    final mine = await created([bob]);
    final draftId = await alice.surat.draftRename(mine, 'Road trip');
    await alice.messages.approve(draftId);
    expect((await alice.channel(mine))!.name, 'Road trip');
    expect(alice.changes.whereType<Renamed>().map((r) => (r.suratId, r.name)), [
      (mine, 'Road trip'),
    ]);
  });

  test('leave from the last-but-one member ends the surat locally', () async {
    final suratId = await created([bob]);
    await bobAccepts(suratId);
    expect((await alice.member(suratId, bob.id))!.state, 'member');

    final draftId = await alice.surat.draftLeave(suratId);
    await alice.messages.approve(draftId);
    await settle();

    expect((await alice.member(suratId, alice.id))!.state, 'left');
    expect((await alice.member(suratId, alice.id))!.leftHlc, isNotNull);
    expect((await alice.channel(suratId))!.closedAt, isNotNull);
    expect(alice.changes.whereType<Ended>().map((e) => e.suratId), [suratId]);
    expect((await alice.queuedFor(bob, draftId)).event, isA<LeaveEvent>());
    expect(
      () => alice.messages.draft(channelId: suratId, body: 'x'),
      throwsA(isA<ChannelClosed>()),
    );
  });

  test('a draft approved after the surat ended is not sent', () async {
    final suratId = await created([bob]);
    await bobAccepts(suratId);
    final rename = await alice.surat.draftRename(suratId, 'Later');
    await alice.storeIncoming(
      suratId,
      from: bob,
      hlc: Hlc(now, 0).encode(),
      event: const LeaveEvent(),
    );
    await alice.surat.rebuild(suratId);
    expect((await alice.channel(suratId))!.closedAt, isNotNull);
    await expectLater(
      alice.messages.approve(rename),
      throwsA(isA<ChannelClosed>()),
    );
    final row = await alice.message(rename);
    expect((row.status, row.hlc), ('awaiting_approval', null));
    expect(await alice.db.select(alice.db.deliveries).get(), hasLength(1));
  });

  test(
    'the newcomer copy of an invite carries the snapshot; other copies do not',
    () async {
      final suratId = await created([bob]);
      await bobAccepts(suratId);
      final draftId = await alice.surat.draftInvite(suratId, carol.id);
      final sent = await alice.messages.approve(draftId);

      final stored = SuratEvent.fromJson(jsonDecode(sent.body!) as Map);
      expect((stored as InviteEvent).snapshot, isNull);
      final toBob = (await alice.queuedFor(bob, draftId)).event as InviteEvent;
      expect(toBob.snapshot, isNull);
      expect(toBob.newcomer.deviceId, carol.id);

      final toCarol =
          (await alice.queuedFor(carol, draftId)).event as InviteEvent;
      expect(
        await checkVouch(
          alice.keys.signPub,
          suratId,
          toCarol.newcomer,
          toCarol.vouch,
        ),
        isTrue,
      );
      final snap = toCarol.snapshot!;
      expect(snap.name, 'Trip');
      expect(snap.creatorDeviceId, alice.id);
      expect(snap.members.map((c) => c.deviceId).toSet(), {alice.id, bob.id});
      expect(snap.invited, isEmpty);
      final aliceCard = snap.members.firstWhere((c) => c.deviceId == alice.id);
      expect(aliceCard.port, 9000);
      expect(aliceCard.address, isNull);
      expect(aliceCard.boxPub, alice.keys.boxPub);
      expect(aliceCard.joinedHlc, isNotNull);
      expect(snap.approvals[alice.id]?[bob.id], 'approved');
      expect(snap.approvals[bob.id]?[alice.id], 'approved');

      final carolRow = (await alice.member(suratId, carol.id))!;
      expect(carolRow.state, 'invited');
      expect(carolRow.joinedHlc, sent.hlc);
    },
  );

  test('the newcomer rebuilds from the snapshot it was sent', () async {
    final suratId = await created([bob]);
    await bobAccepts(suratId);
    final draftId = await alice.surat.draftInvite(suratId, carol.id);
    final sent = await alice.messages.approve(draftId);
    final invite = (await alice.queuedFor(carol, draftId)).event;

    // Carol's Mac as Task 7 will leave it: the channel and the event.
    await carol.db
        .into(carol.db.channels)
        .insert(
          ChannelsCompanion.insert(
            id: suratId,
            kind: 'surat',
            createdAt: now,
            name: const Value('Trip'),
            creatorDeviceId: Value(alice.id),
          ),
        );
    await carol.storeIncoming(
      suratId,
      from: alice,
      hlc: sent.hlc!,
      event: invite,
    );
    final state = await carol.surat.rebuild(suratId);
    await settle();

    expect(state.members.keys.toSet(), {alice.id, bob.id, carol.id});
    final rows = {for (final m in await carol.members(suratId)) m.deviceId: m};
    expect(rows[carol.id]!.state, 'invited');
    expect(rows[carol.id]!.inviterDeviceId, alice.id);
    expect(rows[carol.id]!.theirApproval, isNull);
    expect(rows[alice.id]!.state, 'member');
    expect(rows[alice.id]!.myApproval, isNull);
    expect(rows[alice.id]!.theirApproval, 'approved');
    // Bob is no peer of Carol's: his names come from the card.
    expect(rows[bob.id]!.personName, 'Bob');
    expect(rows[bob.id]!.deviceName, "Bob's Mac");
    expect(
      carol.changes.whereType<Invited>().map((i) => (i.suratId, i.inviter)),
      [(suratId, alice.id)],
    );
  });

  test(
    'members are told of a newcomer to approve and of mutual pairs',
    () async {
      // Bob's Mac: in Alice's surat, then Alice invites Carol.
      const suratId = 's1';
      await bob.db
          .into(bob.db.channels)
          .insert(
            ChannelsCompanion.insert(
              id: suratId,
              kind: 'surat',
              createdAt: now,
              name: const Value('Trip'),
              creatorDeviceId: Value(alice.id),
            ),
          );
      await bob.storeIncoming(
        suratId,
        from: alice,
        hlc: Hlc(now, 0).encode(),
        event: CreateEvent(
          name: 'Trip',
          invitees: [bob.card],
          vouches: {bob.id: await vouch(alice.keys.signing, suratId, bob.card)},
        ),
      );
      await bob.surat.rebuild(suratId);
      await bob.storeIncoming(
        suratId,
        from: bob,
        hlc: Hlc(now + 1, 0).encode(),
        event: const AcceptEvent(),
      );
      await bob.surat.rebuild(suratId);
      await bob.storeIncoming(
        suratId,
        from: alice,
        hlc: Hlc(now + 2, 0).encode(),
        event: InviteEvent(
          newcomer: carol.card,
          vouch: await vouch(alice.keys.signing, suratId, carol.card),
          snapshot: null,
        ),
      );
      await bob.surat.rebuild(suratId);
      await settle();

      expect(bob.changes.whereType<Invited>().single.inviter, alice.id);
      expect(bob.changes.whereType<BecameMutual>().map((c) => c.deviceId), [
        alice.id,
      ]);
      final n = bob.changes.whereType<NewcomerToApprove>().single;
      expect((n.suratId, n.newcomer, n.inviter), (suratId, carol.id, alice.id));
    },
  );

  test(
    'nothing else is drafted in a surat before its create is published',
    () async {
      final draftId = await alice.surat.draftCreate('Trip', [bob.id]);
      final suratId = (await alice.message(draftId)).channelId;
      for (final attempt in [
        () => alice.surat.draftInvite(suratId, carol.id),
        () => alice.surat.draftLeave(suratId),
        () => alice.surat.draftRename(suratId, 'Later'),
      ]) {
        await expectLater(attempt(), throwsA(isA<NotAllowed>()));
      }
      await expectLater(
        alice.messages.draft(channelId: suratId, body: 'early'),
        throwsA(isA<NotAMember>()),
      );
      // A message row that somehow predates the create is not sent either.
      await alice.db
          .into(alice.db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'early',
              channelId: suratId,
              kind: 'message',
              fromDeviceId: alice.id,
              sentAt: now,
              body: const Value('early'),
              direction: 'out',
              status: 'awaiting_approval',
              createdAt: now,
            ),
          );
      await expectLater(
        alice.messages.approve('early'),
        throwsA(isA<NotAMember>()),
      );
      expect((await alice.message('early')).hlc, isNull);

      // Once the create is out, the same drafts work.
      await alice.messages.approve(draftId);
      expect(await alice.surat.draftLeave(suratId), isNotEmpty);
      expect(
        (await alice.messages.draft(channelId: suratId, body: 'now')).status,
        'awaiting_approval',
      );
    },
  );

  test('a re-invited member replays only from its new snapshot', () async {
    // Alice's surat with Dan: Carol joins, Bob joins, Carol and Bob approve
    // each other, Carol leaves, then Bob leaves (Carol never hears of it),
    // and Alice invites Carol again.
    final dan = await Side.make('Dan');
    addTearDown(dan.db.close);
    await alice.pair(dan);
    final suratId = await created([carol, dan]);
    Future<void> fromOther(Side who, SuratEvent event) async {
      now += 1000;
      await alice.storeIncoming(
        suratId,
        from: who,
        hlc: Hlc(now, 0).encode(),
        event: event,
      );
      await alice.surat.rebuild(suratId);
      now += 1000;
    }

    await fromOther(carol, const AcceptEvent());
    await fromOther(dan, const AcceptEvent());
    await alice.messages.approve(
      await alice.surat.draftInvite(suratId, bob.id),
    );
    await fromOther(bob, const AcceptEvent());
    await fromOther(carol, ApproveEvent(bob.id));
    await fromOther(carol, const LeaveEvent());
    // What Carol's Mac holds from her first stay: every event up to her leave.
    final firstStay = await (alice.db.select(
      alice.db.messages,
    )..where((m) => m.kind.equals('event') & m.hlc.isNotNull())).get();
    await fromOther(bob, const LeaveEvent());
    final reinvite = await alice.surat.draftInvite(suratId, carol.id);
    final sent = await alice.messages.approve(reinvite);
    final copy = (await alice.queuedFor(carol, reinvite)).event as InviteEvent;
    expect(copy.snapshot!.members.map((c) => c.deviceId).toSet(), {
      alice.id,
      dan.id,
    });

    await carol.db
        .into(carol.db.channels)
        .insert(
          ChannelsCompanion.insert(
            id: suratId,
            kind: 'surat',
            createdAt: now,
            name: const Value('Trip'),
            creatorDeviceId: Value(alice.id),
          ),
        );
    for (final m in firstStay) {
      await carol.db
          .into(carol.db.messages)
          .insert(
            m.copyWith(direction: 'in', status: 'read').toCompanion(false),
          );
    }
    await carol.storeIncoming(
      suratId,
      from: alice,
      hlc: sent.hlc!,
      event: copy,
    );
    await carol.surat.rebuild(suratId);

    Future<Map<String, String>> seated(Side side) async => {
      for (final m in await side.members(suratId))
        if (m.state == 'member' || m.state == 'invited') m.deviceId: m.state,
    };
    expect(await seated(carol), await seated(alice));
    expect(await seated(carol), {
      alice.id: 'member',
      dan.id: 'member',
      carol.id: 'invited',
    });
    expect((await carol.member(suratId, bob.id))?.state, isNot('member'));
    final carolRow = (await carol.member(suratId, carol.id))!;
    expect(carolRow.inviterDeviceId, alice.id);
    expect(carolRow.joinedHlc, sent.hlc);
  });

  test('rebuild is idempotent: a second run changes nothing', () async {
    final suratId = await created([bob, carol]);
    await bobAccepts(suratId);
    await settle();
    final before = await alice.members(suratId);
    final changesBefore = alice.changes.length;
    final s1 = await alice.surat.rebuild(suratId);
    final s2 = await alice.surat.rebuild(suratId);
    await settle();
    expect(s2, s1);
    expect(
      (await alice.members(suratId)).map((m) => m.toJson()),
      before.map((m) => m.toJson()),
    );
    expect(alice.changes.length, changesBefore);
  });

  test(
    'a surat contact keeps its row while an event to it is queued',
    () async {
      // Carol knows Bob only as a surat contact; when the surat ends her leave
      // must still reach him.
      const suratId = 's2';
      await carol.db.delete(carol.db.peers).go();
      await insertPeer(
        carol.db,
        alice.keys,
        name: 'Alice',
        fingerprint: 'fp-Alice',
      );
      await insertPeer(carol.db, bob.keys, name: 'Bob', trust: 'surat_contact');
      await carol.db
          .into(carol.db.channels)
          .insert(
            ChannelsCompanion.insert(
              id: suratId,
              kind: 'surat',
              createdAt: now,
              name: const Value('Trip'),
              creatorDeviceId: Value(alice.id),
            ),
          );
      await carol.storeIncoming(
        suratId,
        from: alice,
        hlc: Hlc(now, 0).encode(),
        event: CreateEvent(
          name: 'Trip',
          invitees: [bob.card, carol.card],
          vouches: {
            bob.id: await vouch(alice.keys.signing, suratId, bob.card),
            carol.id: await vouch(alice.keys.signing, suratId, carol.card),
          },
        ),
      );
      for (final (i, s) in [(1, bob), (2, carol)]) {
        await carol.storeIncoming(
          suratId,
          from: s,
          hlc: Hlc(now + i, 0).encode(),
          event: const AcceptEvent(),
        );
      }
      await carol.storeIncoming(
        suratId,
        from: alice,
        hlc: Hlc(now + 3, 0).encode(),
        event: const LeaveEvent(),
      );
      await carol.surat.rebuild(suratId);
      now += 1000;
      final draftId = await carol.surat.draftLeave(suratId);
      await carol.messages.approve(draftId);

      expect((await carol.channel(suratId))!.closedAt, isNotNull);
      expect((await carol.queuedFor(bob, draftId)).event, isA<LeaveEvent>());
      final peers = await carol.db.select(carol.db.peers).get();
      expect(peers.map((p) => p.deviceId), contains(bob.id));
    },
  );
}
