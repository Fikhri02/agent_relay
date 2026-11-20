import 'dart:io';

import 'package:agent_relay/app/app_controller.dart';
import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/node/notifier.dart';
import 'package:agent_relay/node/relay_node.dart';
import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:agent_relay/ui/channels/channel_summary.dart';
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
}
