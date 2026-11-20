import 'dart:convert';

import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:flutter_test/flutter_test.dart';

MemberCard _card(String id, {String? address, int? port, String? hlc}) =>
    MemberCard(
      deviceId: id,
      personName: 'P$id',
      deviceName: 'D$id',
      signPub: List.filled(32, 1),
      boxPub: List.filled(32, 2),
      certFingerprint: 'cd' * 32,
      address: address,
      port: port,
      joinedHlc: hlc,
    );

SuratEvent _roundTrip(SuratEvent e) =>
    SuratEvent.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map);

void main() {
  test('every event type round-trips through JSON', () {
    final snapshot = SuratSnapshot(
      name: 'Team',
      creatorDeviceId: 'a',
      members: [_card('a', address: '10.0.0.1', port: 8790, hlc: 'h1')],
      invited: [_card('b')],
      approvals: {
        'a': {'b': 'approve'},
      },
    );
    final events = <SuratEvent>[
      CreateEvent(
        name: 'Team',
        invitees: [_card('b'), _card('c')],
        vouches: {'b': 'sigb', 'c': 'sigc'},
      ),
      InviteEvent(newcomer: _card('d'), vouch: 'sigd', snapshot: snapshot),
      InviteEvent(newcomer: _card('d'), vouch: 'sigd', snapshot: null),
      AcceptEvent(),
      DeclineInviteEvent(),
      ApproveEvent('x'),
      DeclineEvent('y'),
      LeaveEvent(),
      RenameEvent('New name'),
    ];
    const types = [
      'create',
      'invite',
      'invite',
      'accept',
      'decline_invite',
      'approve',
      'decline',
      'leave',
      'rename',
    ];
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      expect(e.type, types[i]);
      final back = _roundTrip(e);
      expect(back.runtimeType, e.runtimeType);
      expect(jsonEncode(back.toJson()), jsonEncode(e.toJson()));
    }
    final inv = _roundTrip(events[1]) as InviteEvent;
    expect(inv.snapshot!.approvals['a']!['b'], 'approve');
    expect(inv.snapshot!.members.single.port, 8790);
    expect((_roundTrip(events[2]) as InviteEvent).snapshot, isNull);
  });

  test('fromJson rejects an unknown type with FormatException', () {
    expect(
      () => SuratEvent.fromJson({'type': 'explode'}),
      throwsFormatException,
    );
    expect(() => SuratEvent.fromJson({}), throwsFormatException);
  });

  test('fromJson rejects missing required fields with FormatException', () {
    expect(
      () => SuratEvent.fromJson({'type': 'rename'}),
      throwsFormatException,
    );
    expect(
      () => SuratEvent.fromJson({'type': 'approve'}),
      throwsFormatException,
    );
    expect(
      () => SuratEvent.fromJson({'type': 'invite', 'vouch': 'x'}),
      throwsFormatException,
    );
  });
}
