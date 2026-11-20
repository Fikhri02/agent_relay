import 'dart:math';

import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:agent_relay/surat/surat_state.dart';
import 'package:flutter_test/flutter_test.dart';

MemberCard _card(String id, {String? hlc}) => MemberCard(
  deviceId: id,
  personName: 'P$id',
  deviceName: 'D$id',
  signPub: List.filled(32, 1),
  boxPub: List.filled(32, 2),
  certFingerprint: 'cd' * 32,
  joinedHlc: hlc,
);

String h(int n) => Hlc(1700000000000 + n, 0).encode();

LoggedEvent ev(int n, String from, SuratEvent event) =>
    (hlc: h(n), from: from, event: event);

LoggedEvent create(int n, String from, List<String> invitees) => ev(
  n,
  from,
  CreateEvent(
    name: 'Team',
    invitees: [for (final id in invitees) _card(id)],
    vouches: {for (final id in invitees) id: 'sig$id'},
  ),
);

LoggedEvent invite(int n, String from, String newcomer) => ev(
  n,
  from,
  InviteEvent(newcomer: _card(newcomer), vouch: 'sig', snapshot: null),
);

LoggedEvent accept(int n, String from) => ev(n, from, const AcceptEvent());
LoggedEvent declineInvite(int n, String from) =>
    ev(n, from, const DeclineInviteEvent());
LoggedEvent leave(int n, String from) => ev(n, from, const LeaveEvent());

SuratState replay(List<LoggedEvent> events) =>
    SuratState.replay(suratId: 's1', creatorDeviceId: 'a', events: events);

void main() {
  test(
    'create with two invitees: both invited, creator member and renamer',
    () {
      final s = replay([
        create(1, 'a', ['b', 'c']),
      ]);
      expect(s.name, 'Team');
      expect(s.renamer, 'a');
      expect(s.ended, isFalse);
      expect(
        s.members['a'],
        MemberEntry(state: MemberState.member, joinedHlc: h(1)),
      );
      for (final id in ['b', 'c']) {
        expect(
          s.members[id],
          const MemberEntry(state: MemberState.invited, inviter: 'a'),
        );
        expect(s.approvals['a']![id], 'approved');
      }
    },
  );

  test('accept makes the invitee a member approving everyone present', () {
    final s = replay([
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
    ]);
    expect(
      s.members['b'],
      MemberEntry(state: MemberState.member, inviter: 'a', joinedHlc: h(2)),
    );
    expect(s.approvals['b'], {'a': 'approved', 'c': 'approved'});
    expect(s.mutual('a', 'b'), isTrue);
  });

  test('co-invitees are mutual once both accept', () {
    final base = [
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
    ];
    expect(replay(base).mutual('b', 'c'), isFalse);
    final s = replay([...base, accept(3, 'c')]);
    expect(s.mutual('b', 'c'), isTrue);
    expect(s.mutual('c', 'b'), isTrue);
    expect(s.mutual('a', 'c'), isTrue);
  });

  test('later invite: inviter approves implicitly, other members undecided, '
      'mutual(other, newcomer) false', () {
    final s = replay([
      create(1, 'a', ['b']),
      accept(2, 'b'),
      invite(3, 'a', 'd'),
      accept(4, 'd'),
    ]);
    expect(s.members['d']!.state, MemberState.member);
    expect(s.members['d']!.inviter, 'a');
    expect(s.approvals['a']!['d'], 'approved');
    expect(s.approvals['b']?['d'], isNull);
    expect(s.approvals['d'], {'a': 'approved', 'b': 'approved'});
    expect(s.mutual('a', 'd'), isTrue);
    expect(s.mutual('b', 'd'), isFalse);
  });

  test('sixth seat: of two concurrent invites the later (hlc, from) is '
      'rejected, same result in either input order', () {
    final base = [
      create(1, 'a', ['b', 'c', 'd']),
      accept(2, 'b'),
      accept(3, 'c'),
      accept(4, 'd'),
    ];
    final x = invite(5, 'b', 'x');
    final y = invite(5, 'c', 'y'); // same hlc, 'c' sorts after 'b'
    final one = replay([...base, x, y]);
    final two = replay([y, ...base.reversed, x]);
    expect(one, two);
    expect(one.members['x']!.state, MemberState.invited);
    expect(one.members.containsKey('y'), isFalse);
    expect(one.rejectedInvites, ['y']);
  });

  test('replay is order independent', () {
    final events = [
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
      accept(3, 'c'),
      invite(4, 'b', 'd'),
      ev(5, 'a', const DeclineEvent('d')),
      ev(6, 'c', const ApproveEvent('d')),
      accept(7, 'd'),
      ev(8, 'a', const RenameEvent('Renamed')),
    ];
    final states = [
      for (final seed in [1, 2, 3]) replay([...events]..shuffle(Random(seed))),
    ];
    expect(states[0], replay(events));
    expect(states[1], states[0]);
    expect(states[2], states[0]);
    expect(states[0].name, 'Renamed');
    expect(states[0].members['d']!.state, MemberState.member);
  });

  test('duplicate events change nothing', () {
    final events = [
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
      invite(3, 'b', 'd'),
      leave(4, 'c'),
    ];
    expect(replay([...events, ...events, events[2]]), replay(events));
  });

  test('rename by a non-renamer is ignored; creator leaves → lowest joinedHlc '
      'member renames', () {
    final s = replay([
      create(1, 'a', ['b', 'c']),
      accept(2, 'c'),
      accept(3, 'b'),
      ev(4, 'b', const RenameEvent('By b')),
      ev(5, 'a', const RenameEvent('By a')),
      leave(6, 'a'),
      ev(7, 'b', const RenameEvent('By b again')),
      ev(8, 'c', const RenameEvent('By c')),
    ]);
    expect(s.renamer, 'c');
    expect(s.name, 'By c');
    expect(s.members['a']!.state, MemberState.left);
    expect(s.members['a']!.leftHlc, h(6));

    final early = replay([
      create(1, 'a', ['b', 'c']),
      accept(2, 'c'),
      accept(3, 'b'),
      ev(4, 'b', const RenameEvent('By b')),
      ev(5, 'a', const RenameEvent('By a')),
    ]);
    expect(early.name, 'By a');
    expect(early.renamer, 'a');
  });

  test('decline then approve becomes approved; approve then decline stays '
      'approved', () {
    final s = replay([
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
      accept(3, 'c'),
      invite(4, 'a', 'd'),
      ev(5, 'b', const DeclineEvent('d')),
      ev(6, 'b', const ApproveEvent('d')),
      ev(7, 'c', const ApproveEvent('d')),
      ev(8, 'c', const DeclineEvent('d')),
    ]);
    expect(s.approvals['b']!['d'], 'approved');
    expect(s.approvals['c']!['d'], 'approved');

    final declined = replay([
      create(1, 'a', ['b']),
      accept(2, 'b'),
      invite(3, 'a', 'd'),
      ev(4, 'b', const DeclineEvent('d')),
    ]);
    expect(declined.approvals['b']!['d'], 'declined');
  });

  test('ends when one member remains; later events ignored', () {
    final s = replay([
      create(1, 'a', ['b']),
      accept(2, 'b'),
      leave(3, 'b'),
      ev(4, 'a', const RenameEvent('After end')),
      invite(5, 'a', 'x'),
    ]);
    expect(s.ended, isTrue);
    expect(s.name, 'Team');
    expect(s.members.containsKey('x'), isFalse);
    expect(s.members['b']!.state, MemberState.left);
  });

  test('every invitee declines → ended; pending invites alone do not end', () {
    expect(
      replay([
        create(1, 'a', ['b']),
      ]).ended,
      isFalse,
    );
    final half = replay([
      create(1, 'a', ['b', 'c']),
      declineInvite(2, 'b'),
    ]);
    expect(half.ended, isFalse);
    expect(half.members['b']!.state, MemberState.declined);
    final all = replay([
      create(1, 'a', ['b', 'c']),
      declineInvite(2, 'b'),
      declineInvite(3, 'c'),
      ev(4, 'a', const RenameEvent('After end')),
    ]);
    expect(all.ended, isTrue);
    expect(all.name, 'Team');
    expect(all.members['c']!.state, MemberState.declined);
  });

  test('last member leaving with invites pending ends the surat; a later '
      'accept is ignored', () {
    final s = replay([
      create(1, 'a', ['b', 'c']),
      leave(2, 'a'),
      accept(3, 'b'),
    ]);
    expect(s.ended, isTrue);
    expect(s.members['a']!.state, MemberState.left);
    expect(s.members['b']!.state, MemberState.invited);
    expect(s.approvals['b'], isNull);
  });

  test('invite by a non-member and accept by a non-invitee are ignored', () {
    final base = [
      create(1, 'a', ['b']),
    ];
    final s = replay([
      ...base,
      invite(2, 'b', 'x'), // b is only invited
      invite(3, 'z', 'y'), // z is a stranger
      accept(4, 'z'),
      accept(5, 'a'), // already a member
      declineInvite(6, 'a'),
    ]);
    expect(s, replay(base));
    expect(s.rejectedInvites, isEmpty);
  });

  test('invite of a current member or invitee is ignored, not rejected; a '
      'left device may be invited again', () {
    final s = replay([
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
      invite(3, 'b', 'c'),
      invite(4, 'b', 'a'),
    ]);
    expect(s.members['c']!.inviter, 'a');
    expect(s.rejectedInvites, isEmpty);

    final back = replay([
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
      accept(3, 'c'),
      ev(4, 'a', const ApproveEvent('c')),
      ev(5, 'b', const ApproveEvent('c')),
      leave(6, 'c'),
      invite(7, 'b', 'c'),
    ]);
    expect(
      back.members['c'],
      const MemberEntry(state: MemberState.invited, inviter: 'b'),
    );
    // A returning device starts over: only its new inviter has approved it.
    expect(back.approvals['b']!['c'], 'approved');
    expect(back.approvals['a']?['c'], isNull);
    expect(back.approvals['c'], isNull);
  });

  test('create is honoured only from the creator, and only once', () {
    expect(
      replay([
        create(1, 'b', ['a']),
      ]).members,
      isEmpty,
    );
    final s = replay([
      create(1, 'a', ['b']),
      ev(
        2,
        'a',
        CreateEvent(name: 'Again', invitees: [_card('c')], vouches: {}),
      ),
    ]);
    expect(s.name, 'Team');
    expect(s.members.containsKey('c'), isFalse);
  });

  test('create past the cap rejects the extra invitees', () {
    final s = replay([
      create(1, 'a', ['b', 'c', 'd', 'e', 'f']),
    ]);
    expect(s.members.length, 5);
    expect(s.rejectedInvites, ['f']);
  });

  test('snapshot start: newcomer sees the surat; renamer is the earliest '
      'member, the creator only when no member has a joinedHlc', () {
    SuratSnapshot snap(String creator) => SuratSnapshot(
      name: 'Team',
      creatorDeviceId: creator,
      members: [
        _card('c', hlc: h(3)),
        _card('b', hlc: h(2)),
      ],
      invited: [_card('e')],
      approvals: {
        'b': {'c': 'approved'},
      },
    );
    LoggedEvent inv(SuratSnapshot sn) => ev(
      5,
      'b',
      InviteEvent(newcomer: _card('d'), vouch: 'sig', snapshot: sn),
    );

    final gone = SuratState.replay(
      suratId: 's1',
      snapshot: snap('a'),
      events: [inv(snap('a')), accept(6, 'd')],
    );
    expect(gone.name, 'Team');
    expect(gone.renamer, 'b');
    expect(gone.members['c']!.joinedHlc, h(3));
    expect(gone.members['e']!.state, MemberState.invited);
    expect(gone.members['d']!.state, MemberState.member);
    expect(gone.approvals['d'], {
      'b': 'approved',
      'c': 'approved',
      'e': 'approved',
    });
    expect(gone.mutual('b', 'd'), isTrue);

    final present = SuratState.replay(
      suratId: 's1',
      snapshot: snap('c'),
      events: [inv(snap('c'))],
    );
    // c created the surat, but b joined earlier (h2 < h3).
    expect(present.renamer, 'b');

    final undated = SuratState.replay(
      suratId: 's1',
      snapshot: SuratSnapshot(
        name: 'Team',
        creatorDeviceId: 'c',
        members: [_card('b'), _card('c')],
        invited: const [],
        approvals: const {},
      ),
      events: const [],
    );
    expect(undated.renamer, 'c');
  });

  test('snapshot and log agree on the renamer after the creator leaves and '
      'rejoins', () {
    final log = [
      create(1, 'a', ['b', 'c']),
      accept(2, 'b'),
      accept(3, 'c'),
      leave(4, 'a'),
      invite(5, 'b', 'a'),
      accept(6, 'a'),
    ];
    final members = replay(log);
    expect(members.renamer, 'b');
    expect(members.members['a']!.joinedHlc, h(6));

    final snapshot = SuratSnapshot(
      name: members.name,
      creatorDeviceId: 'a',
      members: [
        for (final e in members.members.entries)
          if (e.value.state == MemberState.member)
            _card(e.key, hlc: e.value.joinedHlc),
      ],
      invited: const [],
      approvals: {
        for (final row in members.approvals.entries)
          if (row.key == 'b')
            row.key: {...row.value}
          else if (row.value['b'] != null)
            row.key: {'b': row.value['b']!},
      },
    );
    final inviteD = ev(
      7,
      'b',
      InviteEvent(newcomer: _card('d'), vouch: 'sig', snapshot: null),
    );
    final inviteDWithSnapshot = ev(
      7,
      'b',
      InviteEvent(newcomer: _card('d'), vouch: 'sig', snapshot: snapshot),
    );
    final after = [
      accept(8, 'd'),
      ev(9, 'a', const RenameEvent('By a')),
      ev(10, 'b', const RenameEvent('By b')),
    ];
    final onMembers = replay([...log, inviteD, ...after]);
    final onD = SuratState.replay(
      suratId: 's1',
      snapshot: snapshot,
      events: [inviteDWithSnapshot, ...after],
    );
    expect(onD.renamer, onMembers.renamer);
    expect(onD.renamer, 'b');
    expect(onD.name, 'By b');
    expect(onMembers.name, 'By b');
  });
}
