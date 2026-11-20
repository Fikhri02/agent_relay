import 'dart:convert';
import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/node/notifier.dart';
import 'package:agent_relay/node/relay_node.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:agent_relay/peer/trust.dart';
import 'package:agent_relay/surat/surat_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Four real nodes on loopback. Workers run only when [deliverAll] pumps
/// them, so every step is deterministic.
void main() {
  final dirs = <Directory>[];
  // Four nodes, four database files: not the same database opened twice.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() async {
    for (final d in dirs) {
      await d.delete(recursive: true);
    }
  });

  Future<RelayNode> start(String name) async {
    final dir = await tempDir('surat$name');
    dirs.add(dir);
    final node = await RelayNode.start(
      AppConfig(
        dataDir: dir,
        peerPort: 0,
        localPort: 0,
        keychainPrefix: 'surat${dir.path.hashCode}',
      ),
      secrets: InMemorySecretStore(),
      notifier: RecordingNotifier(),
      discovery: false,
      bindAddress: InternetAddress.loopbackIPv4,
      workerTick: null,
    );
    return node;
  }

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

  test('surat lifecycle across four Macs', () async {
    final a = await start('A'), b = await start('B');
    final c = await start('C'), d = await start('D');
    final nodes = [a, b, c, d];
    await a.setup(personName: 'Irfan', deviceName: 'A');
    await b.setup(personName: 'Xavier', deviceName: 'B');
    await c.setup(personName: 'Chin', deviceName: 'C');
    await d.setup(personName: 'Dina', deviceName: 'D');
    String id(RelayNode n) => n.identity!.deviceId;
    String nm(RelayNode n) => n.identity!.deviceName;
    final dChanges = <SuratChange>[];
    final sub = d.surat.changes.listen(dChanges.add);

    /// Runs every worker, each retry made due at once, until no delivery
    /// is queued on any node. Fails with what is still queued otherwise.
    Future<void> deliverAll() async {
      for (var round = 0; round < 20; round++) {
        var queued = 0;
        for (final n in nodes) {
          for (final other in nodes) {
            if (other != n) await n.worker.peerSeen(id(other));
          }
          await n.worker.runOnce();
        }
        for (final n in nodes) {
          queued += (await (n.db.select(
            n.db.deliveries,
          )..where((x) => x.status.equals('queued'))).get()).length;
        }
        if (queued == 0) return;
      }
      final left = [
        for (final n in nodes)
          for (final x in await (n.db.select(
            n.db.deliveries,
          )..where((x) => x.status.equals('queued'))).get())
            '${n.identity!.deviceName} -> ${x.recipientDeviceId}: '
                '${x.messageId} ${x.lastError}',
      ];
      fail('deliveries still queued:\n${left.join('\n')}');
    }

    Future<Map<String, Map<String, Object?>>> members(
      RelayNode n,
      String s,
    ) async => {
      for (final m in await (n.db.select(
        n.db.channelMembers,
      )..where((m) => m.channelId.equals(s))).get())
        m.deviceId: {
          'state': m.state,
          'mine': m.myApproval,
          'theirs': m.theirApproval,
        },
    };

    Future<String?> nameOn(RelayNode n, String s) async => (await (n.db.select(
      n.db.channels,
    )..where((x) => x.id.equals(s))).getSingle()).name;

    /// Messages (not events) of [s] on [n], in timeline order.
    Future<List<Message>> timeline(RelayNode n, String s) async => [
      for (final m in await n.db.channelMessages(s))
        if (m.kind == 'message') m,
    ];

    Future<({int status, Object? json})> api(
      RelayNode n,
      String method,
      String path, [
      Object? body,
    ]) async {
      final token = await File('${n.config.dataDir.path}/local-token')
          .readAsString();
      final client = HttpClient();
      try {
        final req = await client.open(
          method,
          '127.0.0.1',
          n.local.boundPort,
          path,
        );
        req.headers.set('authorization', 'Bearer $token');
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        return (status: res.statusCode, json: jsonDecode(text));
      } finally {
        client.close(force: true);
      }
    }

    Future<void> send(RelayNode n, String s, String body) async {
      final m = await n.messages.draft(channelId: s, body: body);
      await n.messages.approve(m.id);
      await deliverAll();
    }

    String pendingId(String kind, String s, RelayNode who) =>
        '$kind:$s:${id(who)}';

    // 1. A pairs with B, C and D; B, C and D are not paired with each other.
    await pair(a, b);
    await pair(a, c);
    await pair(a, d);
    expect(
      {
        for (final p in await a.db.select(a.db.peers).get())
          p.deviceId: p.trust,
      },
      {id(b): trustPaired, id(c): trustPaired, id(d): trustPaired},
    );
    for (final n in [b, c, d]) {
      final peers = await n.db.select(n.db.peers).get();
      expect(peers.map((p) => (p.deviceId, p.trust)), [(id(a), trustPaired)]);
    }

    // 2. A creates "refund" inviting B and C and approves the draft; B and C
    // accept.
    final createId = await a.surat.draftCreate('refund', [id(b), id(c)]);
    final s = (await (a.db.select(
      a.db.messages,
    )..where((m) => m.id.equals(createId))).getSingle()).channelId;
    await a.messages.approve(createId);
    await deliverAll();
    for (final n in [b, c]) {
      expect((await n.surat.pending()).map((p) => p.id), [
        pendingId('invite', s, n),
      ]);
    }
    await b.surat.decide(pendingId('invite', s, b), approve: true);
    await deliverAll();
    await c.surat.decide(pendingId('invite', s, c), approve: true);
    await deliverAll();
    for (final n in [a, b, c]) {
      final rows = await members(n, s);
      expect(rows.keys.toSet(), {id(a), id(b), id(c)}, reason: nm(n));
      for (final MapEntry(key: who, value: row) in rows.entries) {
        expect(row['state'], 'member');
        if (who == id(n)) continue;
        expect(row['mine'], 'approved', reason: 'mutual on ${nm(n)}');
        expect(row['theirs'], 'approved', reason: 'mutual on ${nm(n)}');
      }
      expect(await nameOn(n, s), 'refund');
    }
    Future<String?> trustOf(RelayNode n, RelayNode x) async =>
        (await (n.db.select(
          n.db.peers,
        )..where((p) => p.deviceId.equals(id(x)))).getSingleOrNull())?.trust;
    expect(await trustOf(b, c), trustSuratContact);
    expect(await trustOf(c, b), trustSuratContact);

    // 3. A sends "m1", B sends "m2" (and C "c0", history D must not get yet);
    // all three read them.
    await send(a, s, 'm1');
    await send(b, s, 'm2');
    await send(c, s, 'c0');
    for (final n in [a, b, c]) {
      final read = [
        for (final m in await n.messages.read(s, by: Reader.agent))
          if (m.kind == 'message') m,
      ];
      expect(read.map((m) => m.body), ['m1', 'm2', 'c0'], reason: nm(n));
      expect(read.where((m) => m.status == 'locked'), isEmpty);
    }
    final aLine = await timeline(a, s);
    final before = [for (final m in aLine) m.id];

    // 4. A invites D and approves; D accepts; B approves D, C declines D.
    final inviteId = await a.surat.draftInvite(s, id(d));
    await a.messages.approve(inviteId);
    await deliverAll();
    expect((await d.surat.pending()).map((p) => p.id), [
      pendingId('invite', s, d),
    ]);
    await d.surat.decide(pendingId('invite', s, d), approve: true);
    await deliverAll();
    for (final n in [b, c]) {
      expect(
        (await n.surat.pending()).map((p) => p.id),
        contains(pendingId('newcomer', s, d)),
      );
    }
    await b.surat.decide(pendingId('newcomer', s, d), approve: true);
    await deliverAll();
    await c.surat.decide(pendingId('newcomer', s, d), approve: false);
    await deliverAll();
    for (final n in nodes) {
      final rows = await members(n, s);
      expect(rows.keys.toSet(), {id(a), id(b), id(c), id(d)}, reason: nm(n));
      expect(rows.values.map((r) => r['state']).toSet(), {'member'});
    }
    final onD = await members(d, s);
    expect(onD[id(a)], {
      'state': 'member',
      'mine': 'approved',
      'theirs': 'approved',
    });
    expect(onD[id(b)], {
      'state': 'member',
      'mine': 'approved',
      'theirs': 'approved',
    });
    expect(onD[id(c)], {
      'state': 'member',
      'mine': 'approved',
      'theirs': 'declined',
    });
    expect((await members(c, s))[id(d)]?['mine'], 'declined');

    // 5. C sends "m3" and "m4": locked on D. D has A's and B's history from
    // before it joined, re-shared in original order, and none of C's.
    await send(c, s, 'm3');
    await send(c, s, 'm4');
    final dLine = await timeline(d, s);
    expect(dLine.map((m) => (m.id, m.fromDeviceId)), [
      (before[0], id(a)),
      (before[1], id(b)),
      (dLine[2].id, id(c)),
      (dLine[3].id, id(c)),
    ]);
    expect(dLine.take(2).map((m) => (m.body, m.hlc, m.seq)), [
      for (final m in aLine.take(2)) (m.body, m.hlc, m.seq),
    ]);
    final lockedOnD = [
      for (final m in dLine)
        if (m.fromDeviceId == id(c)) m,
    ];
    expect(lockedOnD.map((m) => (m.status, m.body)), [
      ('locked', null),
      ('locked', null),
    ]);
    final cSent = [
      for (final m in await timeline(c, s))
        if (m.fromDeviceId == id(c)) m.id,
    ];
    expect(lockedOnD.map((m) => m.id), cSent.sublist(1)); // m3, m4, not c0
    final apiRead = await api(d, 'GET', '/channels/$s/messages');
    expect(apiRead.status, 200);
    final apiLocked = [
      for (final m in ((apiRead.json! as Map)['messages'] as List).cast<Map>())
        if (m['status'] == 'locked') m,
    ];
    expect(apiLocked.map((m) => m['id']), lockedOnD.map((m) => m.id));
    expect(apiLocked.map((m) => m['lockedReason']).toSet(), {
      'they_have_not_approved_you',
    });
    for (final n in [a, b]) {
      expect((await timeline(n, s)).map((m) => m.body), [
        'm1',
        'm2',
        'c0',
        'm3',
        'm4',
      ]);
    }

    // 6. C approves D: D's rows from C unlock with the same ids and order,
    // and C's earlier "c0" arrives as history.
    await c.surat.decide(pendingId('newcomer', s, d), approve: true);
    await deliverAll();
    final dAfter = await timeline(d, s);
    expect(dAfter.map((m) => m.body), ['m1', 'm2', 'c0', 'm3', 'm4']);
    expect(dAfter.where((m) => m.status == 'locked'), isEmpty);
    final unlocked = [
      for (final m in dAfter)
        if (lockedOnD.any((l) => l.id == m.id)) m.id,
    ];
    expect(unlocked, lockedOnD.map((m) => m.id));
    expect(dAfter[2].id, cSent[0]);
    expect((await members(d, s))[id(c)]?['theirs'], 'approved');
    // The agent saw only placeholders; the unlocked text is new to it, and
    // reading it now tells C.
    final fresh = await d.messages.read(s, unreadOnly: true, by: Reader.agent);
    expect(fresh.map((m) => m.body), ['c0', 'm3', 'm4']);
    await deliverAll();
    for (final m in lockedOnD) {
      final r = (await c.messages.receiptsFor(m.id))
          .firstWhere((r) => r.deviceId == id(d));
      expect(r.agentReadAt, isNotNull);
    }

    // 7. A renames to "refund-v2"; every node shows it.
    final renameId = await a.surat.draftRename(s, 'refund-v2');
    await a.messages.approve(renameId);
    await deliverAll();
    for (final n in nodes) {
      expect(await nameOn(n, s), 'refund-v2', reason: nm(n));
    }

    // 8. A leaves. B (lowest joinedHlc after A) may rename, C may not.
    final leaveA = await a.surat.draftLeave(s);
    await a.messages.approve(leaveA);
    await deliverAll();
    for (final n in [b, c, d]) {
      expect((await members(n, s))[id(a)]?['state'], 'left');
      final channels = await api(n, 'GET', '/channels');
      final row = (channels.json! as List).cast<Map>().firstWhere(
        (x) => x['id'] == s,
      );
      expect(row['renamer'], id(b), reason: nm(n));
    }
    final byC = await api(c, 'POST', '/surat/$s/rename', {'name': 'mine'});
    expect(byC.status, 403);
    expect(byC.json, {'error': 'not_allowed'});
    final byB = await api(b, 'POST', '/surat/$s/rename', {'name': 'refund-v3'});
    expect(byB.status, 201);
    await b.messages.approve((byB.json! as Map)['id'] as String);
    await deliverAll();
    for (final n in [b, c, d]) {
      expect(await nameOn(n, s), 'refund-v3', reason: nm(n));
    }

    // B, then C leave: D is the last member and the surat ends.
    for (final n in [b, c]) {
      await n.messages.approve(await n.surat.draftLeave(s));
      await deliverAll();
    }
    final onDEnd = await members(d, s);
    expect(onDEnd[id(d)]?['state'], 'member');
    expect(
      [
        for (final x in [a, b, c]) onDEnd[id(x)]?['state'],
      ],
      ['left', 'left', 'left'],
    );
    expect(
      (await (d.db.select(
        d.db.channels,
      )..where((x) => x.id.equals(s))).getSingle()).closedAt,
      isNotNull,
    );
    expect(dChanges.whereType<Ended>().map((e) => e.suratId), [s]);
    final dChannels = await api(d, 'GET', '/channels');
    final dRow = (dChannels.json! as List).cast<Map>().firstWhere(
      (x) => x['id'] == s,
    );
    expect(dRow['closed'], true);
    final late = await api(d, 'POST', '/channels/$s/send', {'body': 'hello?'});
    expect(late.status, 409);
    expect(late.json, {'error': 'channel_closed'});

    // No message, event or history copy was refused along the way, and no
    // worker had to warn anyone. (Receipts for history copies are refused
    // 404 by their sender, which tracks no delivery under that id.)
    for (final n in nodes) {
      final failed = [
        for (final x
            in await (n.db.select(n.db.deliveries)..where(
                  (x) =>
                      x.status.equals('delivered').not() &
                      x.messageId.like('receipt:%').not(),
                ))
                .get())
          '${nm(n)} -> ${x.recipientDeviceId}: ${x.messageId} '
              '${x.status} ${x.lastError}',
      ];
      expect(failed, isEmpty, reason: nm(n));
      expect((n.notifier as RecordingNotifier).shown, isEmpty, reason: nm(n));
    }

    await sub.cancel();
    for (final n in nodes) {
      await n.stop();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
