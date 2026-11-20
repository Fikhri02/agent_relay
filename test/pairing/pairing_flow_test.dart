import 'dart:async';

import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_node.dart';

void main() {
  late TestNode a;
  late TestNode b;
  var now = DateTime(2026, 11, 20, 9);

  setUp(() async {
    now = DateTime(2026, 11, 20, 9);
    a = await TestNode.start('irfan', clock: () => now);
    b = await TestNode.start('xavier', clock: () => now);
  });
  tearDown(() async {
    await a.stop();
    await b.stop();
  });

  Future<String> codeShownOn(TestNode n) async =>
      ((await n.pairing.events.firstWhere(
        (e) => e is PairingCodeShown,
      )) as PairingCodeShown).pending.code;

  test('two nodes pair: same code both sides, both confirm, peer + private channel on both', () async {
    a.window.open();
    b.window.open();
    final shownOnA = codeShownOn(a);
    final pending = await b.pairing.connect(a.target);
    expect(pending.personName, 'irfan');
    expect(await shownOnA, pending.code);

    final doneA = a.pairing.events.firstWhere((e) => e is PairingSucceeded);
    final doneB = b.pairing.events.firstWhere((e) => e is PairingSucceeded);
    await a.pairing.confirm(b.me.deviceId);
    await b.pairing.confirm(a.me.deviceId);
    await doneA.timeout(const Duration(seconds: 5));
    await doneB.timeout(const Duration(seconds: 5));

    final peerOnA = await a.db.select(a.db.peers).getSingle();
    expect(peerOnA.deviceId, b.me.deviceId);
    expect(peerOnA.trust, 'paired');
    expect(peerOnA.certFingerprint, b.me.certFingerprint);
    final peerOnB = await b.db.select(b.db.peers).getSingle();
    expect(peerOnB.certFingerprint, a.me.certFingerprint);

    final ch = privateChannelId(a.me.deviceId, b.me.deviceId);
    for (final n in [a, b]) {
      final channel = await n.db.select(n.db.channels).getSingle();
      expect(channel.id, ch);
      expect(channel.kind, 'private');
      final members = await n.db.select(n.db.channelMembers).get();
      expect(members.map((m) => m.deviceId).toSet(), {
        a.me.deviceId,
        b.me.deviceId,
      });
    }
  });

  test('hello is rejected when the window is closed', () async {
    b.window.open();
    await expectLater(
      b.pairing.connect(a.target),
      throwsA(isA<PairingRejected>()),
    );
  });

  test('hello is rejected after the 5 minute window', () async {
    a.window.open();
    now = now.add(const Duration(minutes: 5, seconds: 1));
    await expectLater(
      b.pairing.connect(a.target),
      throwsA(isA<PairingRejected>()),
    );
  });

  test('only one side confirming does not complete pairing', () async {
    a.window.open();
    b.window.open();
    await b.pairing.connect(a.target);
    await b.pairing.confirm(a.me.deviceId);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await a.db.select(a.db.peers).get(), isEmpty);
    expect(await b.db.select(b.db.peers).get(), isEmpty);
  });

  test('unpair closes the private channel on both sides', () async {
    a.window.open();
    b.window.open();
    await b.pairing.connect(a.target);
    final doneA = a.pairing.events.firstWhere((e) => e is PairingSucceeded);
    await a.pairing.confirm(b.me.deviceId);
    await b.pairing.confirm(a.me.deviceId);
    await doneA.timeout(const Duration(seconds: 5));

    final gone = b.pairing.events.firstWhere((e) => e is PeerUnpaired);
    await a.pairing.unpair(b.me.deviceId);
    await gone.timeout(const Duration(seconds: 5));
    for (final n in [a, b]) {
      expect((await n.db.select(n.db.peers).getSingle()).trust, 'unpaired');
      expect(
        (await n.db.select(n.db.channels).getSingle()).closedAt,
        isNotNull,
      );
    }
  });
}
