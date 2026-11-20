import 'package:agent_relay/ui/channels/channel_summary.dart';
import 'package:agent_relay/ui/channels/channels_screen.dart';
import 'package:agent_relay/ui/channels/message_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

const List<ChannelSummary> channels = [
  (id: 'x', name: 'Xavier', unread: 2, closed: false),
  (id: 's', name: 'Shaw Ping', unread: 0, closed: false),
];

const List<ChannelSummary> surat = [
  (id: 't', name: 'tiered-discount staging', unread: 1, closed: false),
];

final messages = [
  MessageView(
    id: 'm1',
    senderName: 'You',
    sentAt: DateTime(2026, 11, 20, 9, 38),
    body: "Tiered discount is on staging.api — please don't redeploy",
    context: const MessageContext(
      repo: 'Middleware',
      branch: 'irfan/tiered-discount',
      commit: 'f6a96a1',
    ),
    mine: true,
  ),
  MessageView(
    id: 'm2',
    senderName: 'Xavier',
    sentAt: DateTime(2026, 11, 20, 9, 41),
    body: "Got it. I'll hold it until 5 PM.",
    arrivedLate: true,
  ),
];

Widget screen({
  List<ChannelSummary>? chans = channels,
  List<ChannelSummary> suratList = surat,
  String? selectedId = 'x',
  List<MessageView>? msgs,
  List<GapView> gaps = const [],
  ValueChanged<String>? onSelect,
  Widget? outboxPane,
}) => ChannelsScreen(
  channels: chans,
  surat: suratList,
  selectedId: selectedId,
  messages: msgs,
  gaps: gaps,
  peers: const {
    'x': (deviceName: "Xavier's MacBook Pro", status: PeerOnline()),
    's': (deviceName: "Shaw Ping's iMac", status: PeerOffline()),
  },
  suratMembers: const {
    't': ['You', 'Xavier', 'Tommy', 'Shaw Ping'],
  },
  awaitingApproval: 3,
  onSelect: onSelect ?? (_) {},
  onCopy: (_) {},
  outboxPane: outboxPane,
);

void main() {
  testWidgets('channels screen shows the gap banner', (tester) async {
    await pumpUi(
      tester,
      screen(
        msgs: messages,
        gaps: const [
          (personName: 'Xavier', missing: 2),
          (personName: 'Tommy', missing: 1),
        ],
      ),
    );
    expect(find.text('Waiting for 2 messages from Xavier'), findsOneWidget);
    expect(find.text('Waiting for 1 message from Tommy'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
  });

  testWidgets('one tab per conversation plus Outbox, with unread counts', (
    tester,
  ) async {
    final selected = <String>[];
    await pumpUi(tester, screen(msgs: messages, onSelect: selected.add));
    for (final name in [
      'Xavier',
      'Shaw Ping',
      'tiered-discount staging',
      'Outbox',
    ]) {
      expect(find.byKey(ValueKey('tab-$name')), findsOneWidget, reason: name);
    }
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-Shaw Ping')));
    await tester.tap(find.byKey(const ValueKey('tab-Outbox')));
    expect(selected, ['s', outboxSelectionId]);
  });

  testWidgets('stage shows the peer status line and memos in time order', (
    tester,
  ) async {
    await pumpUi(tester, screen(msgs: messages));
    expect(find.text("Xavier's MacBook Pro · "), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    expect(find.text('From'), findsNWidgets(2));
    expect(find.text('Ref'), findsOneWidget);
    expect(find.text('Arrived late'), findsOneWidget);
    expect(find.text('20 Nov 2026, 9:38 AM'), findsOneWidget);
    final first = tester.getTopLeft(find.text('20 Nov 2026, 9:38 AM')).dy;
    final second = tester.getTopLeft(find.text('20 Nov 2026, 9:41 AM')).dy;
    expect(first, lessThan(second));
    expect(find.widgetWithText(OutlinedButton, 'Copy'), findsNWidgets(2));
  });

  testWidgets('surat stage lists its members', (tester) async {
    await pumpUi(tester, screen(selectedId: 't', msgs: const []));
    expect(find.text('Surat · You, Xavier, Tommy, Shaw Ping'), findsOneWidget);
  });

  testWidgets('Outbox tab shows the outbox pane in the stage', (tester) async {
    await pumpUi(
      tester,
      screen(
        selectedId: outboxSelectionId,
        outboxPane: const Text('outbox pane'),
      ),
    );
    expect(find.text('outbox pane'), findsOneWidget);
  });

  testWidgets('loading shows placeholder rows, not a blank stage', (
    tester,
  ) async {
    await pumpUi(tester, screen(chans: null, msgs: null));
    expect(find.byKey(const ValueKey('placeholder-rows')), findsWidgets);
  });

  testWidgets('no channels says why and the way out', (tester) async {
    await pumpUi(
      tester,
      screen(
        chans: const [],
        suratList: const [],
        selectedId: null,
        msgs: const [],
      ),
    );
    expect(
      find.text('No messages yet — pair a teammate to start'),
      findsOneWidget,
    );
  });

  test('peer status labels', () {
    expect(
      peerStatusLabel(const PeerClockSkew(-12400)),
      'clocks differ by 12 s',
    );
    expect(
      peerStatusLabel(const PeerIdentityChanged()),
      'identity changed — pair again',
    );
    expect(peerStatusLabel(const PeerOffline()), 'offline');
    expect(peerStatusLabel(const PeerOnline()), 'online');
  });
}
