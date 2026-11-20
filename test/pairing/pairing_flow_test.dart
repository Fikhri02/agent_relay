import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
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

  Future<void> pairAB() async {
    a.window.open();
    b.window.open();
    await b.pairing.connect(a.target);
    final doneA = a.pairing.events.firstWhere((e) => e is PairingSucceeded);
    await a.pairing.confirm(b.me.deviceId);
    await b.pairing.confirm(a.me.deviceId);
    await doneA.timeout(const Duration(seconds: 5));
  }

  Future<void> shareSurat(TestNode n) async {
    await n.db
        .into(n.db.channels)
        .insert(
          ChannelsCompanion.insert(id: 'surat1', kind: 'surat', createdAt: 1),
        );
    for (final id in [a.me.deviceId, b.me.deviceId]) {
      await n.db
          .into(n.db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: 'surat1',
              deviceId: id,
              joinedHlc: '0000000000000-00000',
            ),
          );
    }
  }

  test('unpairing keeps a surat link as a contact', () async {
    await pairAB();
    await shareSurat(a);
    final gone = b.pairing.events.firstWhere((e) => e is PeerUnpaired);
    await a.pairing.unpair(b.me.deviceId);
    await gone.timeout(const Duration(seconds: 5));
    expect((await a.db.select(a.db.peers).getSingle()).trust, 'surat_contact');
    // B shares no surat in its own database, so it is unpaired as before.
    expect((await b.db.select(b.db.peers).getSingle()).trust, 'unpaired');
    final private = privateChannelId(a.me.deviceId, b.me.deviceId);
    final ch = await (a.db.select(
      a.db.channels,
    )..where((c) => c.id.equals(private))).getSingle();
    expect(ch.closedAt, isNotNull);
  });

  test('a surat contact cannot call /pair/unpair', () async {
    await pairAB();
    await (a.db.update(a.db.peers))
        .write(const PeersCompanion(trust: Value('surat_contact')));
    await b.pairing.unpair(a.me.deviceId);
    final res = await b.client.post(
      (
        host: '127.0.0.1',
        port: a.port,
        pinnedFingerprint: a.me.certFingerprint,
      ),
      '/pair/unpair',
      {},
    );
    expect(res.status, 401);
    expect(res.json['error'], 'untrusted');
    expect((await a.db.select(a.db.peers).getSingle()).trust, 'surat_contact');
    final ch = await a.db.select(a.db.channels).getSingle();
    expect(ch.closedAt, isNull);
  });

  test('a second hello while a pairing is pending aborts both', () async {
    final c = await TestNode.start('tommy', clock: () => now);
    addTearDown(c.stop);
    a.window.open();
    b.window.open();
    c.window.open();
    await b.pairing.connect(a.target);
    final failed = a.pairing.events.firstWhere((e) => e is PairingFailed);
    await expectLater(
      c.pairing.connect(a.target),
      throwsA(isA<PairingRejected>()),
    );
    await failed.timeout(const Duration(seconds: 5));
    await expectLater(
      a.pairing.confirm(b.me.deviceId),
      throwsA(isA<PairingRejected>()),
    );
  });

  test('confirm fails when the other side has no such pairing', () async {
    a.window.open();
    b.window.open();
    await b.pairing.connect(a.target);
    a.pairing.cancel(b.me.deviceId);
    await expectLater(
      b.pairing.confirm(a.me.deviceId),
      throwsA(isA<PairingRejected>()),
    );
    expect(await b.db.select(b.db.peers).get(), isEmpty);
  });

  test('the code is only shown on the responder after the initiator reveals its nonce', () async {
    a.window.open();
    b.window.open();
    final shown = codeShownOn(a);
    final pending = await b.pairing.connect(a.target);
    expect(await shown.timeout(const Duration(seconds: 5)), pending.code);
  });
}
