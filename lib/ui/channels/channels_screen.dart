import 'package:flutter/material.dart';

import '../common/relay_widgets.dart';
import '../theme/relay_format.dart';
import '../theme/relay_theme.dart';
import 'channel_summary.dart';
import 'message_tile.dart';
import 'message_view.dart';

/// Pass to / receive from `onSelect` for the Outbox tab.
const outboxSelectionId = '__outbox__';

/// The main window, direction C ("Memo desk"): a dark chrome strip with one
/// tab per conversation plus Outbox, and the selected conversation's memos
/// on the stage below.
class ChannelsScreen extends StatelessWidget {
  const ChannelsScreen({
    super.key,
    required this.channels,
    this.surat = const [],
    required this.selectedId,
    required this.messages,
    this.gaps = const [],
    this.peers = const {},
    this.suratMembers = const {},
    this.awaitingApproval = 0,
    required this.onSelect,
    required this.onCopy,
    this.onPairTeammate,
    this.outboxPane,
  });

  /// Private channels, one tab each by person. Null while loading.
  final List<ChannelSummary>? channels;

  /// Surat, one tab each by name (Phase 2; empty in Phase 1).
  final List<ChannelSummary> surat;

  /// A channel id, [outboxSelectionId], or null for none.
  final String? selectedId;

  /// The selected channel's messages, oldest first. Null while loading.
  final List<MessageView>? messages;
  final List<GapView> gaps;

  /// Private channel id → its peer, for the status line.
  final Map<String, ChannelPeer> peers;

  /// Surat channel id → member names, for the status line.
  final Map<String, List<String>> suratMembers;

  /// Count on the Outbox tab.
  final int awaitingApproval;
  final ValueChanged<String> onSelect;
  final ValueChanged<MessageView> onCopy;

  /// Shown as "Pair a teammate" in the empty state when set.
  final VoidCallback? onPairTeammate;

  /// Stage content when the Outbox tab is selected (an [OutboxScreen]).
  final Widget? outboxPane;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabStrip(
            channels: channels,
            surat: surat,
            selectedId: selectedId,
            awaitingApproval: awaitingApproval,
            onSelect: onSelect,
          ),
          Expanded(child: _stage(context)),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context) {
    if (selectedId == outboxSelectionId) {
      return outboxPane ??
          const SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: PlaceholderRows(),
          );
    }
    final all = channels;
    if (all == null) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: PlaceholderRows(),
      );
    }
    if (all.isEmpty && surat.isEmpty) {
      return _Empty(
        text: 'No messages yet — pair a teammate to start',
        action: onPairTeammate == null
            ? null
            : FilledButton(
                onPressed: onPairTeammate,
                child: const Text('Pair a teammate'),
              ),
      );
    }
    final private = all.where((c) => c.id == selectedId).firstOrNull;
    final group = surat.where((c) => c.id == selectedId).firstOrNull;
    final channel = private ?? group;
    if (channel == null) {
      return const _Empty(text: 'Pick a conversation above to read it');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          private != null
              ? _PeerLine(peer: peers[channel.id], fallbackName: channel.name)
              : _SuratLine(members: suratMembers[channel.id]),
          const SizedBox(height: 12),
          Expanded(child: _timeline(context, channel)),
        ],
      ),
    );
  }

  Widget _timeline(BuildContext context, ChannelSummary channel) {
    final list = messages;
    if (list == null) {
      return const SingleChildScrollView(child: PlaceholderRows());
    }
    final items = <Widget>[
      for (final m in list) MessageTile(message: m, onCopy: onCopy),
      for (final g in gaps) _GapLine(gap: g),
    ];
    if (items.isEmpty) {
      return _Empty(
        text:
            'No messages with ${channel.name} yet — ask your agent to '
            'send one',
      );
    }
    // Newest at the bottom and in view; short timelines sit at the top.
    return Align(
      alignment: Alignment.topCenter,
      child: ListView.separated(
        reverse: true,
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => items[items.length - 1 - i],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.channels,
    required this.surat,
    required this.selectedId,
    required this.awaitingApproval,
    required this.onSelect,
  });

  final List<ChannelSummary>? channels;
  final List<ChannelSummary> surat;
  final String? selectedId;
  final int awaitingApproval;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = RelayColors.of(context);
    final list = channels;
    return Container(
      color: c.chrome,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (list == null)
              for (var i = 0; i < 3; i++) const _TabPlaceholder()
            else
              for (final ch in [...list, ...surat])
                _Tab(
                  label: ch.name,
                  count: ch.unread,
                  closed: ch.closed,
                  active: ch.id == selectedId,
                  onTap: () => onSelect(ch.id),
                ),
            _Tab(
              label: 'Outbox',
              count: awaitingApproval,
              active: selectedId == outboxSelectionId,
              onTap: () => onSelect(outboxSelectionId),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    this.closed = false,
  });

  final String label;
  final int count;
  final bool active;
  final bool closed;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    final active = widget.active;
    final fill = active
        ? theme.colorScheme.surface
        : _hover
        ? Color.alphaBlend(c.tabText.withValues(alpha: .10), c.tab)
        : c.tab;
    final textColor = active ? theme.colorScheme.onSurface : c.tabText;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            key: ValueKey('tab-${widget.label}'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      widget.closed ? '${widget.label} · closed' : widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (widget.count > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${widget.count}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: RelayText.tabular,
                        color: active ? c.primaryText : c.tabCount,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabPlaceholder extends StatelessWidget {
  const _TabPlaceholder();

  @override
  Widget build(BuildContext context) {
    final c = RelayColors.of(context);
    return Container(
      width: 96,
      height: 36,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: c.tab,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
    );
  }
}

class _PeerLine extends StatelessWidget {
  const _PeerLine({required this.peer, required this.fallbackName});

  final ChannelPeer? peer;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final c = RelayColors.of(context);
    final p = peer;
    final muted = TextStyle(fontSize: 12, color: c.muted);
    if (p == null) return Text(fallbackName, style: muted);
    final color = switch (p.status) {
      PeerOnline() => c.success,
      PeerOffline() => c.muted,
      PeerClockSkew() => c.warning,
      PeerIdentityChanged() => c.danger,
    };
    return Row(
      children: [
        StatusDot(color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${p.deviceName} · ',
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          peerStatusLabel(p.status),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SuratLine extends StatelessWidget {
  const _SuratLine({required this.members});

  final List<String>? members;

  @override
  Widget build(BuildContext context) {
    final m = members;
    return Text(
      m == null || m.isEmpty ? 'Surat' : 'Surat · ${m.join(', ')}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: RelayColors.of(context).muted),
    );
  }
}

class _GapLine extends StatelessWidget {
  const _GapLine({required this.gap});

  final GapView gap;

  @override
  Widget build(BuildContext context) {
    final c = RelayColors.of(context);
    return Row(
      children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: c.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Waiting for ${plural(gap.missing, 'message', 'messages')} '
            'from ${gap.personName}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.warning,
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: RelayColors.of(context).muted,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
