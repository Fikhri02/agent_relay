import 'package:agent_relay/ui/channels/channel_summary.dart';
import 'package:agent_relay/ui/channels/channels_screen.dart';
import 'package:agent_relay/ui/channels/message_view.dart';
import 'package:agent_relay/ui/outbox/outbox_screen.dart';
import 'package:agent_relay/ui/pairing/pairing_screen.dart';
import 'package:agent_relay/ui/setup/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

const long =
    'Got it. I will hold the Middleware deploy until 5 PM. My agent checked: '
    'the scheduler host does not touch tiers, so I will only redeploy that one. ';

final drafts = [
  for (var i = 0; i < 4; i++)
    DraftView(
      id: 'd$i',
      channelName: 'Xavier',
      body: long * 3,
      context: const MessageContext(
        repo: 'Middleware',
        branch: 'irfan/a-very-long-branch-name-for-the-tiered-discount',
        commit: 'f6a96a1',
      ),
      createdAt: DateTime(2026, 11, 20, 9, 41),
    ),
];

final messages = [
  for (var i = 0; i < 30; i++)
    MessageView(
      id: 'm$i',
      senderName: i.isEven ? 'Xavier Anak Benedict Long Surname' : 'You',
      sentAt: DateTime(2026, 11, 20, 9, i),
      body: long * (i % 5 + 1),
      context: const MessageContext(
        repo: 'Middleware',
        branch: 'irfan/a-very-long-branch-name-for-the-tiered-discount',
        commit: 'f6a96a1',
      ),
      arrivedLate: i == 29,
      locked: i == 3,
      mine: i.isOdd,
    ),
];

final List<ChannelSummary> channels = [
  for (var i = 0; i < 25; i++)
    (
      id: 'c$i',
      name: 'Teammate with a long display name $i',
      unread: i * 7,
      closed: i == 4,
    ),
];

Map<String, Widget Function()> screensUnderTest() => {
  'channels': () => ChannelsScreen(
    channels: channels,
    surat: [
      (id: 'su', name: 'tiered-discount staging', unread: 3, closed: false),
    ],
    selectedId: 'c0',
    messages: messages,
    gaps: const [(personName: 'Xavier', missing: 120)],
    peers: const {
      'c0': (
        deviceName: "Xavier's MacBook Pro 16-inch with a long name",
        status: PeerOnline(),
      ),
      'c1': (deviceName: 'iMac', status: PeerOffline()),
      'c2': (deviceName: 'Mac mini', status: PeerClockSkew(45000)),
      'c3': (deviceName: 'MacBook Air', status: PeerIdentityChanged()),
    },
    awaitingApproval: 120,
    onSelect: (_) {},
    onCopy: (_) {},
  ),
  'channels surat': () => ChannelsScreen(
    channels: channels,
    surat: [
      (id: 'su', name: 'tiered-discount staging', unread: 3, closed: false),
    ],
    suratMembers: const {
      'su': ['You', 'Xavier', 'Tommy', 'Shaw Ping'],
    },
    selectedId: 'su',
    messages: messages,
    onSelect: (_) {},
    onCopy: (_) {},
  ),
  'channels loading': () => ChannelsScreen(
    channels: null,
    selectedId: null,
    messages: null,
    onSelect: (_) {},
    onCopy: (_) {},
  ),
  'channels empty': () => ChannelsScreen(
    channels: const [],
    selectedId: null,
    messages: const [],
    onSelect: (_) {},
    onCopy: (_) {},
    onPairTeammate: () {},
  ),
  'channels outbox': () => ChannelsScreen(
    channels: channels,
    selectedId: outboxSelectionId,
    messages: null,
    awaitingApproval: 4,
    onSelect: (_) {},
    onCopy: (_) {},
    outboxPane: OutboxScreen(drafts: drafts, onSend: (_) {}, onDiscard: (_) {}),
  ),
  'outbox': () =>
      OutboxScreen(drafts: drafts, onSend: (_) {}, onDiscard: (_) {}),
  'pairing idle': () => PairingScreen(
    windowRemaining: const Duration(minutes: 5),
    discovered: [
      for (var i = 0; i < 12; i++)
        DiscoveredMac(
          id: '$i',
          personName: 'Teammate with a long display name $i',
          deviceName: "Teammate's MacBook Pro 16-inch M4 Max",
          address: '192.168.100.200:8790',
        ),
    ],
    code: null,
    addressError: 'Could not reach 192.168.1.20:8790',
    onOpenPairing: () {},
    onClosePairing: () {},
    onPairWith: (_) {},
    onConnectAddress: (_, _) {},
    onCodesMatch: () {},
    onCancelCode: () {},
  ),
  'pairing loading': () => PairingScreen(
    windowRemaining: null,
    discovered: null,
    code: null,
    onOpenPairing: () {},
    onClosePairing: () {},
    onPairWith: (_) {},
    onConnectAddress: (_, _) {},
    onCodesMatch: () {},
    onCancelCode: () {},
  ),
  'pairing code': () => PairingScreen(
    windowRemaining: const Duration(minutes: 4),
    discovered: const [],
    code: const PairingCodePrompt(
      code: '482913',
      personName: 'Xavier',
      deviceName: "Xavier's MacBook Pro",
    ),
    onOpenPairing: () {},
    onClosePairing: () {},
    onPairWith: (_) {},
    onConnectAddress: (_, _) {},
    onCodesMatch: () {},
    onCancelCode: () {},
  ),
  'setup': () => SetupScreen(
    initialName: 'Irfan Fikhri',
    initialDeviceName: 'Irfan MacBook Pro',
    error: 'Could not start the relay: port 8790 is in use',
    onStart: (_, _) {},
  ),
};

void main() {
  for (final brightness in Brightness.values) {
    for (final entry in screensUnderTest().entries) {
      testWidgets('${entry.key} renders in ${brightness.name} at 1000x640', (
        tester,
      ) async {
        await pumpUi(tester, entry.value(), brightness: brightness);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
