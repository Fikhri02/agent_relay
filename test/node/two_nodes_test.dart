import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/node/notifier.dart';
import 'package:agent_relay/node/relay_node.dart';
import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  late Directory dirA, dirB;
  final secretsA = InMemorySecretStore(), secretsB = InMemorySecretStore();

  setUpAll(() async {
    dirA = await tempDir('nodeA');
    dirB = await tempDir('nodeB');
  });
  tearDownAll(() async {
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  Future<RelayNode> start(Directory dir, SecretStore s, {int peerPort = 0}) =>
      RelayNode.start(
        AppConfig(
          dataDir: dir,
          peerPort: peerPort,
          localPort: 0,
          keychainPrefix: dir.path.hashCode.toString(),
        ),
        secrets: s,
        notifier: RecordingNotifier(),
        discovery: false,
        bindAddress: InternetAddress.loopbackIPv4,
      );

  test(
    'pair, send, read, reply, receipts, offline queue and restart',
    () async {
      var a = await start(dirA, secretsA);
      var b = await start(dirB, secretsB);
      await a.setup(personName: 'Irfan', deviceName: 'A');
      await b.setup(personName: 'Xavier', deviceName: 'B');

      // Pair.
      a.pairing.openWindow();
      b.pairing.openWindow();
      await b.pairing.connect((
        host: '127.0.0.1',
        port: a.peerPort,
        pinnedFingerprint: null,
      ));
      final doneA = a.pairing.events.firstWhere((e) => e is PairingSucceeded);
      final doneB = b.pairing.events.firstWhere((e) => e is PairingSucceeded);
      await a.pairing.confirm(b.identity!.deviceId);
      await b.pairing.confirm(a.identity!.deviceId);
      await Future.wait([doneA, doneB]).timeout(const Duration(seconds: 5));
      final ch = privateChannelId(a.identity!.deviceId, b.identity!.deviceId);

      // A sends; B's agent reads.
      final d = await a.messages.draft(
        channelId: ch,
        body: 'Tiered discount is on staging.api',
      );
      await a.messages.approve(d.id);
      await a.worker.runOnce();
      final firstRead = await b.messages.read(ch, by: Reader.agent);
      expect(firstRead.single.body, 'Tiered discount is on staging.api');
      expect(firstRead.single.status, 'unread');
      expect((await b.db.channelMessages(ch)).single.status, 'read');

      // B's receipt reaches A.
      await b.worker.runOnce();
      final receipt = (await a.messages.receiptsFor(d.id)).single;
      expect(receipt.deliveredAt, isNotNull);
      expect(receipt.agentReadAt, isNotNull);

      // B replies; A sees it after the original.
      final r = await b.messages.draft(
        channelId: ch,
        body: 'Holding until 5 PM',
        replyTo: d.id,
      );
      await b.messages.approve(r.id);
      await b.worker.runOnce();
      expect((await a.db.channelMessages(ch)).map((m) => m.body), [
        'Tiered discount is on staging.api',
        'Holding until 5 PM',
      ]);

      // B goes offline; A's message waits.
      final bPort = b.peerPort;
      await b.stop();
      final q = await a.messages.draft(
        channelId: ch,
        body: 'Staging is free now',
      );
      await a.messages.approve(q.id);
      await a.worker.runOnce();
      final waiting = await (a.db.select(
        a.db.deliveries,
      )..where((x) => x.messageId.equals(q.id))).getSingle();
      expect(waiting.status, 'queued');
      expect(waiting.attempts, 1);

      // B comes back on the same port; A is told it was seen and delivers once.
      b = await start(dirB, secretsB, peerPort: bPort);
      expect(b.identity!.personName, 'Xavier');
      await a.worker.peerSeen(b.identity!.deviceId);
      await a.worker.runOnce();
      await a.worker.runOnce();
      final timeline = await b.db.channelMessages(ch);
      expect(timeline.map((m) => m.body), [
        'Tiered discount is on staging.api',
        'Holding until 5 PM',
        'Staging is free now',
      ]);

      await a.stop();
      await b.stop();
    },
  );
}
