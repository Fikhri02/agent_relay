import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/messaging/envelope.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:agent_relay/surat/surat_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/surat_side.dart';

void main() {
  late Side alice, bob, carol, dave;

  // Each side has its own in-memory database on purpose.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    now = 1700000000000;
    alice = await Side.make('Alice');
    bob = await Side.make('Bob');
    carol = await Side.make('Carol');
    dave = await Side.make('Dave');
    await alice.pair(bob);
    await alice.pair(carol);
    await bob.pair(alice);
    await carol.pair(alice);
  });
  tearDown(() async {
    for (final s in [alice, bob, carol, dave]) {
      await s.db.close();
    }
  });

  String stamp() => Hlc(now += 1000, 0).encode();

  /// Alice creates "Trip" with [invitees] and approves it. Returns the surat
  /// id and the create's draft id.
  Future<(String, String)> created(List<Side> invitees) async {
    final draftId = await alice.surat.draftCreate('Trip', [
      for (final s in invitees) s.id,
    ]);
    await alice.messages.approve(draftId);
    return ((await alice.message(draftId)).channelId, draftId);
  }

  /// [to] receives what [from] queued for it under [messageId].
  Future<({bool duplicate})> deliver(
    Side from,
    Side to,
    String messageId,
  ) async {
    final q = await from.queuedFor(to, messageId);
    expect(q.path, eventPath);
    return to.surat.receiveEvent(q.env, from: await to.peerOf(from));
  }

  /// Bob's Mac in Alice's surat with Bob a member; Alice has his accept.
  Future<String> bobIsMember() async {
    final (suratId, createId) = await created([bob]);
    await deliver(alice, bob, createId);
    final hlc = stamp();
    await bob.storeIncoming(
      suratId,
      from: bob,
      hlc: hlc,
      event: const AcceptEvent(),
    );
    await bob.surat.rebuild(suratId);
    await alice.storeIncoming(
      suratId,
      from: bob,
      hlc: hlc,
      event: const AcceptEvent(),
    );
    await alice.surat.rebuild(suratId);
    return suratId;
  }

  Future<int> eventRows(Side s) async => (await (s.db.select(
    s.db.messages,
  )..where((m) => m.kind.equals('event'))).get()).length;

  Future<Peer?> peerRow(Side s, String deviceId) => (s.db.select(
    s.db.peers,
  )..where((p) => p.deviceId.equals(deviceId))).getSingleOrNull();

  MemberCard forged(MemberCard c, {List<int>? boxPub}) => MemberCard(
    deviceId: c.deviceId,
    personName: c.personName,
    deviceName: c.deviceName,
    signPub: c.signPub,
    boxPub: boxPub ?? c.boxPub,
    certFingerprint: c.certFingerprint,
    joinedHlc: c.joinedHlc,
  );

  test(
    'an invite from a paired peer creates the surat and the contacts',
    () async {
      final suratId = await bobIsMember();
      final inviteId = await alice.surat.draftInvite(suratId, carol.id);
      await alice.messages.approve(inviteId);

      final r = await deliver(alice, carol, inviteId);
      await settle();

      expect(r.duplicate, isFalse);
      final channel = (await carol.channel(suratId))!;
      expect(channel.kind, 'surat');
      expect(channel.name, 'Trip');
      expect(channel.creatorDeviceId, alice.id);
      final rows = {
        for (final m in await carol.members(suratId)) m.deviceId: m,
      };
      expect(rows[carol.id]!.state, 'invited');
      expect(rows[carol.id]!.inviterDeviceId, alice.id);
      expect(rows[alice.id]!.state, 'member');
      expect(rows[bob.id]!.state, 'member');
      // Bob is reachable through the card Alice vouched for; Alice stays
      // paired; I am never my own contact.
      expect((await peerRow(carol, bob.id))!.trust, 'surat_contact');
      expect((await peerRow(carol, alice.id))!.trust, 'paired');
      expect(await peerRow(carol, carol.id), isNull);
      final stored = await carol.message(inviteId);
      expect((stored.kind, stored.direction, stored.seq), ('event', 'in', 0));
      expect(carol.changes.whereType<Invited>().single.inviter, alice.id);
    },
  );

  test(
    'a create from a paired peer opens the surat and adds the other invitees',
    () async {
      await bob.pair(carol); // only to prove a paired row is left alone
      final (suratId, createId) = await created([bob, carol]);

      await deliver(alice, bob, createId);

      final channel = (await bob.channel(suratId))!;
      expect((channel.name, channel.creatorDeviceId), ('Trip', alice.id));
      final rows = {for (final m in await bob.members(suratId)) m.deviceId: m};
      expect(rows[bob.id]!.state, 'invited');
      expect(rows[carol.id]!.state, 'invited');
      expect(rows[alice.id]!.state, 'member');
      expect((await peerRow(bob, carol.id))!.trust, 'paired');
      expect(await peerRow(bob, bob.id), isNull);
    },
  );

  test('an invite from a non-paired sender is refused', () async {
    final suratId = await bobIsMember();
    final inviteId = await alice.surat.draftInvite(suratId, carol.id);
    await alice.messages.approve(inviteId);
    await (carol.db.update(carol.db.peers)
          ..where((p) => p.deviceId.equals(alice.id)))
        .write(const PeersCompanion(trust: Value('surat_contact')));

    await expectLater(
      deliver(alice, carol, inviteId),
      throwsA(isA<NotAMember>()),
    );

    expect(await carol.channel(suratId), isNull);
    expect(await carol.members(suratId), isEmpty);
    expect(await eventRows(carol), 0);
    expect(await peerRow(carol, bob.id), isNull);
  });

  group('carried cards (R12)', () {
    test('a bad vouch refuses the whole invite', () async {
      final suratId = await bobIsMember();
      final inviteId = await alice.surat.draftInvite(suratId, carol.id);
      await alice.messages.approve(inviteId);
      final real =
          (await alice.queuedFor(carol, inviteId)).event as InviteEvent;
      // Signed by Bob, not by the inviter.
      final env = await alice.sealFor(
        carol,
        suratId,
        InviteEvent(
          newcomer: real.newcomer,
          vouch: await vouch(bob.keys.signing, suratId, real.newcomer),
          snapshot: real.snapshot,
        ),
        id: 'forged',
        hlc: stamp(),
      );

      await expectLater(
        carol.surat.receiveEvent(env, from: await carol.peerOf(alice)),
        throwsA(isA<BadEnvelope>()),
      );

      expect(await carol.channel(suratId), isNull);
      expect(await eventRows(carol), 0);
      expect(await peerRow(carol, bob.id), isNull);
    });

    test('a bad invitee vouch refuses the whole create', () async {
      final (suratId, createId) = await created([bob, carol]);
      final real = (await alice.queuedFor(bob, createId)).event as CreateEvent;
      final env = await alice.sealFor(
        bob,
        suratId,
        CreateEvent(
          name: real.name,
          invitees: real.invitees,
          vouches: {
            ...real.vouches,
            // Vouched for another surat.
            carol.id: await vouch(alice.keys.signing, 'other', carol.card),
          },
        ),
        id: 'forged',
        hlc: stamp(),
      );

      await expectLater(
        bob.surat.receiveEvent(env, from: await bob.peerOf(alice)),
        throwsA(isA<BadEnvelope>()),
      );

      expect(await bob.channel(suratId), isNull);
      expect(await eventRows(bob), 0);
      expect(await peerRow(bob, carol.id), isNull);
    });

    test('a create missing an invitee vouch is refused', () async {
      final (suratId, createId) = await created([bob, carol]);
      final real = (await alice.queuedFor(bob, createId)).event as CreateEvent;
      final env = await alice.sealFor(
        bob,
        suratId,
        CreateEvent(
          name: real.name,
          invitees: real.invitees,
          vouches: {bob.id: real.vouches[bob.id]!},
        ),
        id: 'forged',
        hlc: stamp(),
      );

      await expectLater(
        bob.surat.receiveEvent(env, from: await bob.peerOf(alice)),
        throwsA(isA<BadEnvelope>()),
      );
      expect(await bob.channel(suratId), isNull);
    });

    test("a snapshot card whose device id doesn't match its keys refuses the invite", () async {
      final suratId = await bobIsMember();
      final inviteId = await alice.surat.draftInvite(suratId, carol.id);
      await alice.messages.approve(inviteId);
      final real =
          (await alice.queuedFor(carol, inviteId)).event as InviteEvent;
      final snap = real.snapshot!;
      final other = await IdentityKeys.generate();
      final env = await alice.sealFor(
        carol,
        suratId,
        InviteEvent(
          newcomer: real.newcomer,
          vouch: real.vouch,
          snapshot: SuratSnapshot(
            name: snap.name,
            creatorDeviceId: snap.creatorDeviceId,
            members: [
              for (final c in snap.members)
                c.deviceId == bob.id ? forged(c, boxPub: other.boxPub) : c,
            ],
            invited: snap.invited,
            approvals: snap.approvals,
          ),
        ),
        id: 'forged',
        hlc: stamp(),
      );

      await expectLater(
        carol.surat.receiveEvent(env, from: await carol.peerOf(alice)),
        throwsA(isA<BadEnvelope>()),
      );

      expect(await carol.channel(suratId), isNull);
      expect(await eventRows(carol), 0);
      expect(await peerRow(carol, bob.id), isNull);
    });

    test(
      "a member gets the newcomer's card only with the inviter's vouch",
      () async {
        final suratId = await bobIsMember();
        final inviteId = await alice.surat.draftInvite(suratId, carol.id);
        await alice.messages.approve(inviteId);
        final real =
            (await alice.queuedFor(bob, inviteId)).event as InviteEvent;
        final bad = await alice.sealFor(
          bob,
          suratId,
          InviteEvent(
            newcomer: real.newcomer,
            vouch: await vouch(carol.keys.signing, suratId, real.newcomer),
            snapshot: null,
          ),
          id: 'forged',
          hlc: stamp(),
        );
        final before = await eventRows(bob);

        await expectLater(
          bob.surat.receiveEvent(bad, from: await bob.peerOf(alice)),
          throwsA(isA<BadEnvelope>()),
        );
        expect(await eventRows(bob), before);
        expect(await peerRow(bob, carol.id), isNull);

        await deliver(alice, bob, inviteId);
        expect((await peerRow(bob, carol.id))!.trust, 'surat_contact');
        expect((await bob.member(suratId, carol.id))!.state, 'invited');
      },
    );
  });

  test('accept before invite still lands', () async {
    final suratId = await bobIsMember();
    await bob.pair(carol); // reaches Bob's route before Bob knows of her
    final inviteId = await alice.surat.draftInvite(suratId, carol.id);
    await alice.messages.approve(inviteId);
    final accept = await carol.sealFor(
      bob,
      suratId,
      const AcceptEvent(),
      id: 'carol-accept',
      hlc: stamp(),
    );
    final carolPeer = await bob.peerOf(carol);

    // Alice's Mac is slow: Carol's accept reaches Bob first. Bob can't place
    // it yet and refuses it; Carol's worker keeps it queued and retries.
    await expectLater(
      bob.surat.receiveEvent(accept, from: carolPeer),
      throwsA(isA<NotAMember>()),
    );
    expect(await bob.member(suratId, carol.id), isNull);

    await deliver(alice, bob, inviteId);
    expect((await bob.member(suratId, carol.id))!.state, 'invited');

    final r = await bob.surat.receiveEvent(accept, from: carolPeer);
    expect(r.duplicate, isFalse);
    final row = (await bob.member(suratId, carol.id))!;
    expect(row.state, 'member');
    expect(row.joinedHlc, accept.hlc);
  });

  test(
    'a duplicate event is acknowledged as duplicate and changes nothing',
    () async {
      final suratId = await bobIsMember();
      final inviteId = await alice.surat.draftInvite(suratId, carol.id);
      await alice.messages.approve(inviteId);
      await deliver(alice, carol, inviteId);
      await settle();
      final members = await carol.members(suratId);
      final changes = carol.changes.length;

      final r = await deliver(alice, carol, inviteId);
      await settle();

      expect(r.duplicate, isTrue);
      expect(await eventRows(carol), 1);
      expect(await carol.members(suratId), members);
      expect(carol.changes.length, changes);
    },
  );

  group('only members and invitees write to a surat', () {
    test('a paired device outside the surat is refused', () async {
      final suratId = await bobIsMember();
      await bob.pair(dave);
      final members = await bob.members(suratId);
      for (final event in <SuratEvent>[
        const RenameEvent('Mine now'),
        ApproveEvent(bob.id),
        const AcceptEvent(),
        const LeaveEvent(),
      ]) {
        final env = await dave.sealFor(
          bob,
          suratId,
          event,
          id: 'dave-${event.type}',
          hlc: stamp(),
        );
        await expectLater(
          bob.surat.receiveEvent(env, from: await bob.peerOf(dave)),
          throwsA(isA<NotAMember>()),
        );
      }
      expect(await bob.members(suratId), members);
      expect((await bob.channel(suratId))!.name, 'Trip');
      expect(
        await (bob.db.select(
          bob.db.messages,
        )..where((m) => m.fromDeviceId.equals(dave.id))).get(),
        isEmpty,
      );
    });

    test("a paired device can't invite into a surat it isn't in, even naming a contact", () async {
      final suratId = await bobIsMember();
      await bob.pair(dave);
      final env = await dave.sealFor(
        bob,
        suratId,
        InviteEvent(
          newcomer: carol.card,
          vouch: await vouch(dave.keys.signing, suratId, carol.card),
          snapshot: null,
        ),
        id: 'dave-invite',
        hlc: stamp(),
      );
      await expectLater(
        bob.surat.receiveEvent(env, from: await bob.peerOf(dave)),
        throwsA(isA<NotAMember>()),
      );
      expect(await bob.member(suratId, carol.id), isNull);
      expect(await peerRow(bob, carol.id), isNull);
    });

    test('an event for a surat this Mac does not hold is refused', () async {
      final env = await alice.sealFor(
        bob,
        'unknown',
        const RenameEvent('x'),
        id: 'e1',
        hlc: stamp(),
      );
      await expectLater(
        bob.surat.receiveEvent(env, from: await bob.peerOf(alice)),
        throwsA(isA<NotAMember>()),
      );
      expect(await bob.channel('unknown'), isNull);
    });

    test('a private channel id takes no events', () async {
      await bob.db
          .into(bob.db.channels)
          .insert(
            ChannelsCompanion.insert(id: 'p1', kind: 'private', createdAt: 1),
          );
      final env = await alice.sealFor(
        bob,
        'p1',
        const RenameEvent('x'),
        id: 'e1',
        hlc: stamp(),
      );
      await expectLater(
        bob.surat.receiveEvent(env, from: await bob.peerOf(alice)),
        throwsA(isA<NotAMember>()),
      );
      expect(await eventRows(bob), 0);
    });

    test("a member's leave lands; after it, its events are refused", () async {
      final (suratId, _) = await created([bob, carol]);
      Future<void> fromCarol(SuratEvent e, String id) async =>
          alice.surat.receiveEvent(
            await carol.sealFor(alice, suratId, e, id: id, hlc: stamp()),
            from: await alice.peerOf(carol),
          );
      await fromCarol(const AcceptEvent(), 'c-accept');
      expect((await alice.member(suratId, carol.id))!.state, 'member');
      await fromCarol(const LeaveEvent(), 'c-leave');
      expect((await alice.member(suratId, carol.id))!.state, 'left');

      await expectLater(
        fromCarol(DeclineEvent(bob.id), 'c-decline'),
        throwsA(isA<NotAMember>()),
      );
      await expectLater(
        fromCarol(const AcceptEvent(), 'c-accept-2'),
        throwsA(isA<NotAMember>()),
      );
      expect((await alice.member(suratId, carol.id))!.state, 'left');
      for (final id in ['c-decline', 'c-accept-2']) {
        expect(
          await (alice.db.select(
            alice.db.messages,
          )..where((m) => m.id.equals(id))).getSingleOrNull(),
          isNull,
        );
      }
    });

    test("an invitee's decline lands once", () async {
      final (suratId, _) = await created([bob, carol]);
      Future<void> fromCarol(SuratEvent e, String id) async =>
          alice.surat.receiveEvent(
            await carol.sealFor(alice, suratId, e, id: id, hlc: stamp()),
            from: await alice.peerOf(carol),
          );
      await fromCarol(const DeclineInviteEvent(), 'c-no');
      expect((await alice.member(suratId, carol.id))!.state, 'declined');
      await expectLater(
        fromCarol(const DeclineInviteEvent(), 'c-no-2'),
        throwsA(isA<NotAMember>()),
      );
    });

    test(
      "a member's invite copy may not carry a snapshot for someone else",
      () async {
        final suratId = await bobIsMember();
        final inviteId = await alice.surat.draftInvite(suratId, carol.id);
        await alice.messages.approve(inviteId);
        final withSnap =
            (await alice.queuedFor(carol, inviteId)).event as InviteEvent;
        final env = await alice.sealFor(
          bob,
          suratId,
          withSnap,
          id: 'snap-for-carol',
          hlc: stamp(),
        );
        await expectLater(
          bob.surat.receiveEvent(env, from: await bob.peerOf(alice)),
          throwsA(isA<BadEnvelope>()),
        );
      },
    );

    test(
      'an invite naming me while I am in the surat keeps no snapshot',
      () async {
        final suratId = await bobIsMember();
        final before = await bob.members(suratId);
        // A snapshot that would drop Alice from Bob's view.
        final env = await alice.sealFor(
          bob,
          suratId,
          InviteEvent(
            newcomer: bob.card,
            vouch: await vouch(alice.keys.signing, suratId, bob.card),
            snapshot: SuratSnapshot(
              name: 'Hijack',
              creatorDeviceId: alice.id,
              members: [alice.card],
              invited: const [],
              approvals: const {},
            ),
          ),
          id: 're-invite',
          hlc: stamp(),
        );

        await bob.surat.receiveEvent(env, from: await bob.peerOf(alice));

        final stored = await bob.message('re-invite');
        expect(stored.body, isNot(contains('Hijack')));
        expect(await bob.members(suratId), before);
        expect((await bob.channel(suratId))!.name, 'Trip');
      },
    );
  });

  group('malformed events', () {
    test('a message-kind envelope is refused on the event path', () async {
      final suratId = await bobIsMember();
      final env = await alice.sealFor(
        bob,
        suratId,
        const RenameEvent('x'),
        id: 'm1',
        hlc: stamp(),
      );
      final asMessage = Envelope(
        id: env.id,
        channelId: env.channelId,
        kind: 'message',
        from: env.from,
        sentAt: env.sentAt,
        hlc: env.hlc,
        seq: 0,
        sealed: env.sealed,
      );
      await expectLater(
        bob.surat.receiveEvent(asMessage, from: await bob.peerOf(alice)),
        throwsA(isA<BadEnvelope>()),
      );
    });

    test(
      'an event sealed for someone else or with no seal is refused',
      () async {
        final suratId = await bobIsMember();
        final forCarol = await alice.sealFor(
          carol,
          suratId,
          const RenameEvent('x'),
          id: 'e1',
          hlc: stamp(),
        );
        final alicePeer = await bob.peerOf(alice);
        await expectLater(
          bob.surat.receiveEvent(forCarol, from: alicePeer),
          throwsA(isA<BadEnvelope>()),
        );
        final unsealed = Envelope(
          id: 'e2',
          channelId: suratId,
          kind: 'event',
          from: alice.id,
          sentAt: now,
          hlc: stamp(),
          seq: 0,
          sealed: null,
        );
        await expectLater(
          bob.surat.receiveEvent(unsealed, from: alicePeer),
          throwsA(isA<BadEnvelope>()),
        );
        expect((await bob.channel(suratId))!.name, 'Trip');
      },
    );

    test(
      'an envelope from another device than the caller is refused',
      () async {
        final suratId = await bobIsMember();
        await bob.pair(dave);
        final env = await alice.sealFor(
          bob,
          suratId,
          const RenameEvent('x'),
          id: 'e1',
          hlc: stamp(),
        );
        await expectLater(
          bob.surat.receiveEvent(env, from: await bob.peerOf(dave)),
          throwsA(isA<NotAMember>()),
        );
      },
    );

    test('an event stamped too far ahead is refused', () async {
      final suratId = await bobIsMember();
      final env = await alice.sealFor(
        bob,
        suratId,
        const RenameEvent('x'),
        id: 'e1',
        hlc: Hlc(now + maxFutureSkewMs + 1000, 0).encode(),
      );
      await expectLater(
        bob.surat.receiveEvent(env, from: await bob.peerOf(alice)),
        throwsA(isA<BadEnvelope>()),
      );
    });
  });
}
