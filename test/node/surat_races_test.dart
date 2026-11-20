import 'dart:convert';
import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/node/notifier.dart';
import 'package:agent_relay/node/relay_node.dart';
import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:agent_relay/peer/trust.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Real nodes on loopback, workers pumped by hand, for deliveries that race
/// each other between Macs.
void main() {
  final dirs = <Directory>[];
  final running = <RelayNode>[];
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDown(() async {
    for (final n in running) {
      await n.stop();
    }
    running.clear();
  });
  tearDownAll(() async {
    for (final d in dirs) {
      await d.delete(recursive: true);
    }
  });

  Future<RelayNode> start(String name, String person) async {
    final dir = await tempDir('race$name');
    dirs.add(dir);
    final node = await RelayNode.start(
      AppConfig(
        dataDir: dir,
        peerPort: 0,
        localPort: 0,
        keychainPrefix: 'race${dir.path.hashCode}',
      ),
      secrets: InMemorySecretStore(),
      notifier: RecordingNotifier(),
      discovery: false,
      bindAddress: InternetAddress.loopbackIPv4,
      workerTick: null,
    );
    running.add(node);
    await node.setup(personName: person, deviceName: name);
    return node;
  }

  String id(RelayNode n) => n.identity!.deviceId;

  Future<void> pair(RelayNode a, RelayNode x) async {
    a.pairing.openWindow();
    x.pairing.openWindow();
    final doneA = a.pairing.events.firstWhere((e) => e is PairingSucceeded);
    final doneX = x.pairing.events.firstWhere((e) => e is PairingSucceeded);
    await x.pairing.connect((
      host: '127.0.0.1',
      port: a.peerPort,
      pinnedFingerprint: null,
    ));
    await a.pairing.confirm(x.identity!.deviceId);
    await x.pairing.confirm(a.identity!.deviceId);
    await Future.wait([doneA, doneX]).timeout(const Duration(seconds: 5));
  }

  /// One pass of [n]'s worker with every queued delivery made due.
  Future<void> pump(RelayNode n, List<RelayNode> others) async {
    for (final o in others) {
      await n.worker.peerSeen(id(o));
    }
    await n.worker.runOnce();
  }

  Future<void> deliverAll(List<RelayNode> nodes) async {
    for (var round = 0; round < 10; round++) {
      for (final n in nodes) {
        await pump(n, [
          for (final o in nodes)
            if (o != n) o,
        ]);
      }
      var queued = 0;
      for (final n in nodes) {
        queued += (await (n.db.select(
          n.db.deliveries,
        )..where((x) => x.status.equals('queued'))).get()).length;
      }
      if (queued == 0) return;
    }
    fail('deliveries still queued');
  }

  /// A surat made by [a] with [b] in it, accepted and settled.
  Future<String> suratOf(RelayNode a, RelayNode b) async {
    final createId = await a.surat.draftCreate('race', [id(b)]);
    final s = (await (a.db.select(
      a.db.messages,
    )..where((m) => m.id.equals(createId))).getSingle()).channelId;
    await a.messages.approve(createId);
    await deliverAll([a, b]);
    await b.surat.decide('invite:$s:${id(b)}', approve: true);
    await deliverAll([a, b]);
    return s;
  }

  Future<Peer?> peerOn(RelayNode n, RelayNode x) => (n.db.select(
    n.db.peers,
  )..where((p) => p.deviceId.equals(id(x)))).getSingleOrNull();

  Future<Delivery> deliveryOf(RelayNode n, String messageId) => (n.db.select(
    n.db.deliveries,
  )..where((d) => d.messageId.equals(messageId))).getSingle();

  test('a message into a surat that just ended there leaves the pairing '
      'intact on both Macs', () async {
    final a = await start('A', 'Irfan'), b = await start('B', 'Xavier');
    await pair(a, b);
    final s = await suratOf(a, b);

    // B approves a message; A leaves before B's copy arrives, so the surat
    // has ended on A's Mac only.
    final m = await b.messages.draft(channelId: s, body: 'still there?');
    await b.messages.approve(m.id);
    await a.messages.approve(await a.surat.draftLeave(s));
    await pump(b, [a]);

    final refused = await deliveryOf(b, m.id);
    expect(
      (refused.status, refused.lastError),
      ('dropped', 'refused 409 channel_closed'),
    );
    expect((await peerOn(b, a))!.trust, trustPaired);
    expect((b.notifier as RecordingNotifier).shown, isEmpty);

    // The leave lands; private messages still flow both ways.
    await deliverAll([a, b]);
    final ch = privateChannelId(id(a), id(b));
    final p1 = await a.messages.draft(channelId: ch, body: 'from A');
    await a.messages.approve(p1.id);
    final p2 = await b.messages.draft(channelId: ch, body: 'from B');
    await b.messages.approve(p2.id);
    await deliverAll([a, b]);
    for (final n in [a, b]) {
      expect((await peerOn(n, n == a ? b : a))!.trust, trustPaired);
      expect(
        (await (n.db.select(
          n.db.channels,
        )..where((c) => c.id.equals(ch))).getSingle()).closedAt,
        isNull,
      );
      expect((await n.db.channelMessages(ch)).map((x) => x.body), [
        'from A',
        'from B',
      ]);
      expect((n.notifier as RecordingNotifier).shown, isEmpty);
    }
  });

  test('a surat message that overtakes its sender\'s accept is delivered '
      'once the accept lands', () async {
    final a = await start('A', 'Irfan'), b = await start('B', 'Xavier');
    await pair(a, b);
    final createId = await a.surat.draftCreate('race', [id(b)]);
    final s = (await (a.db.select(
      a.db.messages,
    )..where((m) => m.id.equals(createId))).getSingle()).channelId;
    await a.messages.approve(createId);
    await deliverAll([a, b]);

    // B accepts, but the accept to A sits in backoff.
    await b.surat.decide('invite:$s:${id(b)}', approve: true);
    await (b.db.update(b.db.deliveries)
          ..where((d) => d.status.equals('queued')))
        .write(const DeliveriesCompanion(nextAttemptAt: Value(1 << 52)));
    final m = await b.messages.draft(channelId: s, body: 'hello all');
    await b.messages.approve(m.id);
    await b.worker.runOnce();
    final early = await deliveryOf(b, m.id);
    expect((early.status, early.lastError), ('queued', 'not_a_member'));

    await deliverAll([a, b]);
    expect((await deliveryOf(b, m.id)).status, 'delivered');
    expect(
      [
        for (final x in await a.db.channelMessages(s))
          if (x.kind == 'message') x.body,
      ],
      ['hello all'],
    );
  });
}
