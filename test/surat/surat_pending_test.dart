import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/surat/surat_event.dart';
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

  Future<void> deliver(Side from, Side to, String messageId) async {
    final q = await from.queuedFor(to, messageId);
    await to.surat.receiveEvent(q.env, from: await to.peerOf(from));
  }

  /// My latest outgoing event row.
  Future<Message> lastEvent(Side s) async =>
      (await (s.db.select(s.db.messages)
                ..where(
                  (m) => m.kind.equals('event') & m.direction.equals('out'),
                )
                ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
              .get())
          .first;

  /// Decides one step later than the previous event, so order is clear.
  Future<void> decide(Side s, String id, {required bool approve}) {
    now += 1000;
    return s.surat.decide(id, approve: approve);
  }

  /// Alice's "Trip" with Bob invited; Bob has received the create.
  Future<String> tripWithBobInvited() async {
    final draft = await alice.surat.draftCreate('Trip', [bob.id]);
    await alice.messages.approve(draft);
    await deliver(alice, bob, draft);
    return (await alice.message(draft)).channelId;
  }

  /// Bob accepted on both Macs, Alice invited Carol, Bob has the invite.
  Future<String> carolInvitedByAlice() async {
    final suratId = await tripWithBobInvited();
    await decide(bob, 'invite:$suratId:${bob.id}', approve: true);
    await deliver(bob, alice, (await lastEvent(bob)).id);
    final invite = await alice.surat.draftInvite(suratId, carol.id);
    await alice.messages.approve(invite);
    await deliver(alice, bob, invite);
    return suratId;
  }

  test('an invite to me is pending until accepted; accepting publishes accept to every member', () async {
    final suratId = await tripWithBobInvited();
    final items = await bob.surat.pending();
    expect(items, hasLength(1));
    expect(items.single.id, 'invite:$suratId:${bob.id}');
    expect(items.single.kind, 'invite');
    expect(items.single.suratName, 'Trip');
    expect(items.single.inviterName, 'Alice');
    expect(items.single.declined, isFalse);
    expect(await alice.surat.pending(), isEmpty);

    await decide(bob, items.single.id, approve: true);

    expect(await bob.surat.pending(), isEmpty);
    expect((await bob.member(suratId, bob.id))!.state, 'member');
    final sent = await lastEvent(bob);
    expect(sent.status, 'queued');
    expect(sent.hlc, isNotNull);
    final q = await bob.queuedFor(alice, sent.id);
    expect(q.event, isA<AcceptEvent>());
    expect(await bob.db.drafts(), isEmpty);
  });

  test('a newcomer is pending for members but not for the inviter', () async {
    final suratId = await carolInvitedByAlice();
    final items = await bob.surat.pending();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.id, 'newcomer:$suratId:${carol.id}');
    expect(item.kind, 'newcomer');
    expect(item.personName, 'Carol');
    expect(item.inviterName, 'Alice');
    expect(item.declined, isFalse);
    expect(await alice.surat.pending(), isEmpty);
  });

  test(
    'decline keeps them pending as declined; approve later succeeds',
    () async {
      final suratId = await carolInvitedByAlice();
      final id = 'newcomer:$suratId:${carol.id}';
      await decide(bob, id, approve: false);
      final sent = await lastEvent(bob);
      expect((await bob.queuedFor(alice, sent.id)).event, isA<DeclineEvent>());
      expect((await bob.surat.pending()).single.declined, isTrue);

      // Declining again is a no-op.
      await decide(bob, id, approve: false);
      expect((await lastEvent(bob)).id, sent.id);

      await decide(bob, id, approve: true);
      final approved = await lastEvent(bob);
      final event = (await bob.queuedFor(alice, approved.id)).event;
      expect(event, isA<ApproveEvent>());
      expect((event as ApproveEvent).deviceId, carol.id);
      expect(await bob.surat.pending(), isEmpty);
      expect(await bob.db.drafts(), isEmpty);
    },
  );

  test('decline after approve throws AlreadyApproved', () async {
    final suratId = await carolInvitedByAlice();
    final id = 'newcomer:$suratId:${carol.id}';
    await decide(bob, id, approve: true);
    expect(
      () => decide(bob, id, approve: false),
      throwsA(isA<AlreadyApproved>()),
    );
  });

  test('unknown pending id throws UnknownPending', () async {
    final suratId = await tripWithBobInvited();
    for (final id in [
      'nonsense',
      'invite:no-such:${bob.id}',
      'newcomer:$suratId:${carol.id}',
      'invite:$suratId:${alice.id}',
    ]) {
      expect(
        () => decide(bob, id, approve: true),
        throwsA(isA<UnknownPending>()),
        reason: id,
      );
    }
  });

  test('deciding in an ended surat is not allowed', () async {
    final suratId = await tripWithBobInvited();
    final leave = await alice.surat.draftLeave(suratId);
    await alice.messages.approve(leave);
    await deliver(alice, bob, leave);
    expect((await bob.channel(suratId))!.closedAt, isNotNull);
    expect(await bob.surat.pending(), isEmpty);
    expect(
      () => decide(bob, 'invite:$suratId:${bob.id}', approve: true),
      throwsA(isA<NotAllowed>()),
    );
  });

  test('declining an invite publishes decline_invite to every other member and invitee', () async {
    final draft = await alice.surat.draftCreate('Trip', [bob.id, carol.id]);
    await alice.messages.approve(draft);
    await deliver(alice, bob, draft);
    final suratId = (await alice.message(draft)).channelId;
    final id = 'invite:$suratId:${bob.id}';
    expect((await bob.surat.pending()).map((i) => i.id), [id]);

    await decide(bob, id, approve: false);

    final sent = await lastEvent(bob);
    expect(sent.status, 'queued');
    expect(sent.hlc, isNotNull);
    for (final to in [alice, carol]) {
      expect(
        (await bob.queuedFor(to, sent.id)).event,
        isA<DeclineInviteEvent>(),
        reason: to.name,
      );
    }
    expect((await bob.member(suratId, bob.id))!.state, 'declined');
    expect(await bob.surat.pending(), isEmpty);
    expect(await bob.db.drafts(), isEmpty);
  });

  test(
    'a newcomer decision from a device that is only invited is refused',
    () async {
      final draft = await alice.surat.draftCreate('Trip', [bob.id, carol.id]);
      await alice.messages.approve(draft);
      await deliver(alice, bob, draft);
      final suratId = (await alice.message(draft)).channelId;
      final before = (await bob.db.select(bob.db.messages).get()).length;
      for (final approve in [true, false]) {
        expect(
          () => decide(bob, 'newcomer:$suratId:${carol.id}', approve: approve),
          throwsA(isA<UnknownPending>()),
        );
      }
      expect((await bob.db.select(bob.db.messages).get()).length, before);
    },
  );

  test(
    'the inviter has no newcomer decision about their own invitee',
    () async {
      final suratId = await carolInvitedByAlice();
      final before = (await alice.db.select(alice.db.messages).get()).length;
      for (final approve in [true, false]) {
        expect(
          () =>
              decide(alice, 'newcomer:$suratId:${carol.id}', approve: approve),
          throwsA(isA<UnknownPending>()),
        );
      }
      expect((await alice.db.select(alice.db.messages).get()).length, before);
    },
  );

  test(
    'a newcomer decision in an ended surat is not allowed, even a repeat',
    () async {
      final suratId = await carolInvitedByAlice();
      final id = 'newcomer:$suratId:${carol.id}';
      await decide(bob, id, approve: false);
      // The reducer never leaves a seated newcomer in an ended surat, so close
      // the channel directly to exercise the guard.
      await (bob.db.update(bob.db.channels)..where((c) => c.id.equals(suratId)))
          .write(const ChannelsCompanion(closedAt: Value(1)));
      final before = (await bob.db.select(bob.db.messages).get()).length;
      for (final approve in [true, false]) {
        expect(
          () => decide(bob, id, approve: approve),
          throwsA(isA<NotAllowed>()),
        );
      }
      expect((await bob.db.select(bob.db.messages).get()).length, before);
      expect(await bob.surat.pending(), isEmpty);
    },
  );
}
