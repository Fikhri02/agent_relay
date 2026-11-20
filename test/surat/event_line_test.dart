import 'dart:typed_data';

import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/surat/event_line.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const names = {'a': 'Aina', 'b': 'Budi', 'me': 'You'};
  String nameOf(String id) => names[id] ?? 'Unknown';
  MemberCard card(String id) => MemberCard(
    deviceId: id,
    personName: 'x',
    deviceName: 'y',
    signPub: Uint8List(32),
    boxPub: Uint8List(32),
    certFingerprint: 'fp',
  );
  String line(SuratEvent e, {String from = 'a', String? suratName}) =>
      eventLine(e, from: from, nameOf: nameOf, suratName: suratName);

  test('create', () {
    final e = CreateEvent(name: 'Release', invitees: [card('b')], vouches: {});
    expect(line(e), 'Aina created Release');
    expect(line(e, suratName: 'Shipping'), 'Aina created Shipping');
    expect(line(e, from: 'me'), 'You created Release');
  });

  test('invite names the newcomer', () {
    final e = InviteEvent(newcomer: card('b'), vouch: 'v', snapshot: null);
    expect(line(e), 'Aina invited Budi');
    expect(line(e, from: 'me'), 'You invited Budi');
  });

  test('accept and decline_invite are about the sender', () {
    expect(line(const AcceptEvent(), from: 'b'), 'Budi joined');
    expect(line(const AcceptEvent(), from: 'me'), 'You joined');
    expect(
      line(const DeclineInviteEvent(), from: 'b'),
      'Budi declined the invite',
    );
  });

  test('approve and decline name the subject', () {
    expect(line(const ApproveEvent('b')), 'Aina approved Budi');
    expect(line(const DeclineEvent('b')), 'Aina declined Budi');
    expect(line(const ApproveEvent('b'), from: 'me'), 'You approved Budi');
  });

  test('leave and rename', () {
    expect(line(const LeaveEvent(), from: 'b'), 'Budi left');
    expect(
      line(const RenameEvent('Launch')),
      'Aina renamed the surat to Launch',
    );
  });

  test('ended line', () {
    expect(endedLine('Aina'), 'Surat ended — Aina is the last member');
  });
}
