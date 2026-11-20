import 'dart:io';

import 'package:agent_relay/app/app_controller.dart';
import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/node/notifier.dart';
import 'package:agent_relay/node/relay_node.dart';
import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:agent_relay/ui/channels/channel_summary.dart';
import 'package:agent_relay/ui/surat/pending_panel.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Records notifications with their action callbacks so tests can press them.
class ActionNotifier extends RecordingNotifier {
  final actions = <String, void Function(int)>{};
  @override
  Future<void> show(
    NotificationText text, {
    String? tag,
    List<String> actions = const [],
    void Function(int action)? onAction,
    void Function()? onClick,
  }) async {
    await super.show(
      text,
      tag: tag,
      actions: actions,
      onAction: onAction,
      onClick: onClick,
    );
    if (tag != null && onAction != null) this.actions[tag] = onAction;
  }
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  late Directory dirA, dirB;
  late RelayNode a, b;
  late ActionNotifier notesA;
  late AppController ctl;
  late String ch;

  setUp(() async {
    dirA = await tempDir('ctlA');
    dirB = await tempDir('ctlB');
    notesA = ActionNotifier();
    a = await RelayNode.start(
      AppConfig(dataDir: dirA, peerPort: 0, localPort: 0, keychainPrefix: 'a'),
      secrets: InMemorySecretStore(),
      notifier: notesA,
      discovery: false,
      bindAddress: InternetAddress.loopbackIPv4,
      workerTick: null,
    );
    b = await RelayNode.start(
      AppConfig(dataDir: dirB, peerPort: 0, localPort: 0, keychainPrefix: 'b'),
      secrets: InMemorySecretStore(),
      discovery: false,
      bindAddress: InternetAddress.loopbackIPv4,
      workerTick: null,
    );
    await a.setup(personName: 'Irfan', deviceName: 'A');
    await b.setup(personName: 'Xavier', deviceName: "Xavier's MacBook Pro");
    ctl = AppController(a, notesA, windowVisible: () => true);
    await ctl.init();
    a.pairing.openWindow();
    b.pairing.openWindow();
    await b.pairing.connect((
      host: '127.0.0.1',
      port: a.peerPort,
      pinnedFingerprint: null,
    ));
    final done = a.pairing.events.firstWhere((e) => e is PairingSucceeded);
    await a.pairing.confirm(b.identity!.deviceId);
    await b.pairing.confirm(a.identity!.deviceId);
    await done;
    await settle();
    ch = privateChannelId(a.identity!.deviceId, b.identity!.deviceId);
  });
  tearDown(() async {
    ctl.dispose();
    await a.stop();
    await b.stop();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  Future<void> bSends(String body) async {
    final d = await b.messages.draft(channelId: ch, body: body);
    await b.messages.approve(d.id);
    await b.worker.runOnce();
    await settle();
  }

  test(
    'pairing shows a code notification and then the private channel tab',
    () async {
      expect(
        notesA.shown.any((n) => n.title.startsWith('Pairing code')),
        isTrue,
      );
      expect(ctl.channels!.single.name, 'Xavier');
      expect(ctl.peers[ch]!.deviceName, "Xavier's MacBook Pro");
      expect(ctl.peers[ch]!.status, isA<PeerOnline>());
    },
  );

  test(
    'incoming message notifies with channel and sender, and counts as unread',
    () async {
      ctl.select('__outbox__');
      await bSends('Tiered discount is on staging.api\nsecond line');
      final n = notesA.shown.last;
      expect(n.title, 'Xavier');
      expect(n.body, 'Tiered discount is on staging.api');
      expect(ctl.channels!.single.unread, 1);
    },
  );

  test('opening the channel shows the memo and sends a seen receipt', () async {
    await bSends('hello');
    await ctl.select(ch);
    expect(ctl.messages!.single.body, 'hello');
    expect(ctl.channels!.single.unread, 0);
    await a.worker.runOnce();
    final sent = await b.db.select(b.db.messages).getSingle();
    final r = (await b.messages.receiptsFor(sent.id)).single;
    expect(r.seenAt, isNotNull);
  });

  test('a new draft asks for approval in a notification; Send approves and clears it', () async {
    final d = await a.messages.draft(
      channelId: ch,
      body: 'Staging is free now',
    );
    await settle();
    final ask = notesA.shown.last;
    expect(ask.title, 'Send to Xavier?');
    expect(ask.body, 'Staging is free now');
    expect(ctl.awaitingApproval, 1);
    notesA.actions[d.id]!(0); // Send
    await settle();
    final m = await (a.db.select(
      a.db.messages,
    )..where((x) => x.id.equals(d.id))).getSingle();
    expect(m.status, 'queued');
    expect(notesA.removed, contains(d.id));
    expect(ctl.awaitingApproval, 0);
  });

  test(
    'approving elsewhere (the skill) clears the approval notification',
    () async {
      final d = await a.messages.draft(channelId: ch, body: 'x');
      await settle();
      await a.messages.approve(d.id);
      await settle();
      expect(notesA.removed, contains(d.id));
    },
  );

  test('Discard from the notification discards', () async {
    final d = await a.messages.draft(channelId: ch, body: 'x');
    await settle();
    notesA.actions[d.id]!(1);
    await settle();
    final m = await (a.db.select(
      a.db.messages,
    )..where((x) => x.id.equals(d.id))).getSingle();
    expect(m.status, 'discarded');
  });

  test('my sent memo carries its receipt', () async {
    final d = await a.messages.draft(channelId: ch, body: 'ping');
    await ctl.approve(d.id);
    await a.worker.runOnce();
    await ctl.select(ch);
    final mine = ctl.messages!.single;
    expect(mine.mine, isTrue);
    expect(mine.receipts.single.personName, 'Xavier');
    expect(mine.receipts.single.deliveredAt, isNotNull);
  });

  group('surat', () {
    late Directory dirC;
    late RelayNode c;
    late ActionNotifier notesB;
    AppController? ctlB;

    Future<void> pairNodes(RelayNode x, RelayNode y) async {
      x.pairing.openWindow();
      y.pairing.openWindow();
      await y.pairing.connect((
        host: '127.0.0.1',
        port: x.peerPort,
        pinnedFingerprint: null,
      ));
      final done = x.pairing.events.firstWhere((e) => e is PairingSucceeded);
      await x.pairing.confirm(y.identity!.deviceId);
      await y.pairing.confirm(x.identity!.deviceId);
      await done;
      await settle();
    }

    Future<void> startC(String person, String device) async {
      dirC = await tempDir('ctlC');
      c = await RelayNode.start(
        AppConfig(
          dataDir: dirC,
          peerPort: 0,
          localPort: 0,
          keychainPrefix: 'c',
        ),
        secrets: InMemorySecretStore(),
        discovery: false,
        bindAddress: InternetAddress.loopbackIPv4,
        workerTick: null,
      );
      await c.setup(personName: person, deviceName: device);
    }

    tearDown(() async {
      ctlB?.dispose();
      ctlB = null;
      await c.stop();
      await dirC.delete(recursive: true);
    });

    Future<void> deliverAll() async {
      for (var i = 0; i < 2; i++) {
        for (final n in [a, b, c]) {
          await n.worker.runOnce();
        }
        await settle();
      }
    }

    String id(RelayNode n) => n.identity!.deviceId;

    /// A creates "Release" with [invitees] and approves it from the
    /// notification; returns the surat id.
    Future<String> aCreates(List<RelayNode> invitees) async {
      await ctl.createSurat('Release', [for (final n in invitees) id(n)]);
      await settle();
      final draft = (await a.db.drafts()).single;
      final ask = notesA.shown.last;
      expect(ask.title, 'Send to Release?');
      expect(ask.body, 'You created Release', reason: 'never raw JSON');
      expect(ctl.drafts!.single.body, 'You created Release');
      notesA.actions[draft.id]!(0); // Send
      await settle();
      await deliverAll();
      return draft.channelId;
    }

    Future<void> accepts(RelayNode n, String s) async {
      await n.surat.decide('invite:$s:${id(n)}', approve: true);
      await deliverAll();
    }

    test('controller lists surat separately with member names '
        '"{person} ({device})" when names collide', () async {
      await startC('Xavier', 'Xavier iMac');
      await pairNodes(a, c);
      final s = await aCreates([b, c]);
      await accepts(b, s);
      await accepts(c, s);

      expect(ctl.channels!.map((x) => x.id), isNot(contains(s)));
      expect(ctl.channels, hasLength(2));
      expect(ctl.surat.single.id, s);
      expect(ctl.surat.single.name, 'Release');
      expect(ctl.suratMembers[s], [
        'You',
        'Xavier (Xavier iMac)',
        "Xavier (Xavier's MacBook Pro)",
      ]);

      await ctl.select(s);
      final lines = [for (final m in ctl.messages!) (m.kind, m.body)];
      expect(lines, [
        ('event', 'You created Release'),
        ('event', "Xavier (Xavier's MacBook Pro) joined"),
        ('event', 'Xavier (Xavier iMac) joined'),
      ]);
    });

    test('NewcomerToApprove raises the approve notification', () async {
      await startC('Cara', 'Cara Mac');
      await pairNodes(b, c);
      final s = await aCreates([b]);
      await accepts(b, s);
      final invite = await b.surat.draftInvite(s, id(c));
      await b.messages.approve(invite);
      await deliverAll();

      final tag = 'newcomer:$s:${id(c)}';
      expect(notesA.shown.last.title, 'Xavier invited Cara to Release');
      expect(ctl.pending.single.id, tag);
      expect(ctl.pending.single.kind, PendingKind.newcomer);
      notesA.actions[tag]!(0); // Approve
      await settle();
      final row =
          await (a.db.select(
                a.db.channelMembers,
              )..where((m) => m.channelId.equals(s) & m.deviceId.equals(id(c))))
              .getSingle();
      expect(row.myApproval, 'approved');
      expect(ctl.pending, isEmpty);
      expect(notesA.removed, contains(tag));
    });

    test('an invite notifies with Accept / Decline and Accept joins', () async {
      await startC('Cara', 'Cara Mac');
      notesB = ActionNotifier();
      ctlB = AppController(b, notesB, windowVisible: () => true);
      await ctlB!.init();
      final s = await aCreates([b]);

      final tag = 'invite:$s:${id(b)}';
      expect(
        notesB.shown.map((n) => n.title),
        contains('Irfan invited you to Release'),
      );
      expect(ctlB!.surat.single.id, s);
      notesB.actions[tag]!(0); // Accept
      await settle();
      final row =
          await (b.db.select(
                b.db.channelMembers,
              )..where((m) => m.channelId.equals(s) & m.deviceId.equals(id(b))))
              .getSingle();
      expect(row.state, 'member');
    });

    test(
      'a surat with one member left ends: notified, closed, ended line',
      () async {
        await startC('Cara', 'Cara Mac');
        final s = await aCreates([b]);
        await accepts(b, s);
        final leave = await b.surat.draftLeave(s);
        await b.messages.approve(leave);
        await deliverAll();

        expect(
          notesA.shown.map((n) => n.title),
          contains("Release ended — you're the last member"),
        );
        expect(ctl.surat.single.closed, isTrue);
        await ctl.select(s);
        expect(ctl.messages!.map((m) => m.body), [
          'You created Release',
          'Xavier joined',
          'Xavier left',
          'Surat ended — Irfan is the last member',
        ]);
      },
    );
  });
}
