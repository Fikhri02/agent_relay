// Adapted from gallery_bridge apps/macos/lib/app/tray_menu.dart
import '../channels/channel_summary.dart';

enum TrayCommand {
  openChannel,
  openOutbox,
  openRelay,
  pairTeammate,
  newSurat,
  toggleLaunchAtLogin,
  quit,
}

sealed class TrayEntry {
  const TrayEntry();
}

class TrayLabel extends TrayEntry {
  const TrayLabel(this.text);
  final String text;
}

class TrayAction extends TrayEntry {
  const TrayAction(
    this.label,
    this.command, {
    this.checked = false,
    this.channelId,
  });
  final String label;
  final TrayCommand command;
  final bool checked;

  /// Set for [TrayCommand.openChannel].
  final String? channelId;
}

class TraySeparator extends TrayEntry {
  const TraySeparator();
}

/// What the menu bar menu shows. Pure, so it is tested directly.
///
/// [unread] maps channel id → unread count and is the source of the counts.
List<TrayEntry> trayEntries({
  required Map<String, int> unread,
  required List<ChannelSummary> channels,
  required int awaitingApproval,
  bool launchAtLogin = false,
}) {
  final total = unread.values.fold(0, (a, b) => a + b);
  return [
    TrayLabel(total > 0 ? 'Agent Relay — $total unread' : 'Agent Relay'),
    for (final c in channels)
      if ((unread[c.id] ?? 0) > 0)
        TrayAction(
          '${c.name} (${unread[c.id]})',
          TrayCommand.openChannel,
          channelId: c.id,
        ),
    if (awaitingApproval > 0)
      TrayAction('Outbox ($awaitingApproval)', TrayCommand.openOutbox),
    const TraySeparator(),
    const TrayAction('Open Relay', TrayCommand.openRelay),
    const TrayAction('Pair a Teammate…', TrayCommand.pairTeammate),
    const TrayAction('New surat…', TrayCommand.newSurat),
    TrayAction(
      'Launch at Login',
      TrayCommand.toggleLaunchAtLogin,
      checked: launchAtLogin,
    ),
    const TraySeparator(),
    const TrayAction('Quit Agent Relay', TrayCommand.quit),
  ];
}
