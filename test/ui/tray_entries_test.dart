import 'package:agent_relay/ui/shell/tray_entries.dart';
import 'package:flutter_test/flutter_test.dart';

String describe(TrayEntry e) => switch (e) {
  TrayLabel(:final text) => 'label:$text',
  TraySeparator() => '---',
  TrayAction(:final label, :final checked) =>
    checked ? 'action:$label [x]' : 'action:$label',
};

void main() {
  test('tray entries: unread channels, outbox count, fixed items in order', () {
    final entries = trayEntries(
      unread: {'c1': 2, 'c2': 0, 'c3': 1},
      channels: [
        (id: 'c1', name: 'Xavier', unread: 2, closed: false),
        (id: 'c2', name: 'Shaw Ping', unread: 0, closed: false),
        (id: 'c3', name: 'Tommy', unread: 1, closed: false),
      ],
      awaitingApproval: 1,
      launchAtLogin: true,
    );
    expect(entries.map(describe), [
      'label:Agent Relay — 3 unread',
      'action:Xavier (2)',
      'action:Tommy (1)',
      'action:Outbox (1)',
      '---',
      'action:Open Relay',
      'action:Pair a Teammate…',
      'action:New surat…',
      'action:Launch at Login [x]',
      '---',
      'action:Quit Agent Relay',
    ]);
    final xavier = entries[1] as TrayAction;
    expect(xavier.command, TrayCommand.openChannel);
    expect(xavier.channelId, 'c1');
    expect((entries[3] as TrayAction).command, TrayCommand.openOutbox);
    expect((entries.last as TrayAction).command, TrayCommand.quit);
    final newSurat = entries.whereType<TrayAction>().firstWhere(
      (e) => e.label == 'New surat…',
    );
    expect(newSurat.command, TrayCommand.newSurat);
  });

  test('nothing unread and empty outbox: plain title, no outbox line', () {
    final entries = trayEntries(
      unread: const {},
      channels: [(id: 'c1', name: 'Xavier', unread: 0, closed: false)],
      awaitingApproval: 0,
    );
    expect(entries.map(describe), [
      'label:Agent Relay',
      '---',
      'action:Open Relay',
      'action:Pair a Teammate…',
      'action:New surat…',
      'action:Launch at Login',
      '---',
      'action:Quit Agent Relay',
    ]);
  });
}
