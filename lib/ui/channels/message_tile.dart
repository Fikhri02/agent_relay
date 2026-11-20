import 'package:flutter/material.dart';

import '../common/relay_widgets.dart';
import '../theme/relay_format.dart';
import '../theme/relay_theme.dart';
import 'message_view.dart';
import 'sticky_follower.dart';

/// One message as a memo: a surface card with a From / Ref / Time header,
/// the body as selectable text, an "Arrived late" line and a Copy button.
///
/// My memos are indented 48 from the left, theirs 48 from the right. Each
/// memo has its sender's disc beside it — theirs on the left, mine on the
/// right — in the sender's colour, and the disc follows a long memo while it
/// scrolls. A locked message is a dashed box with a lock and no Copy button.
/// A surat membership event is a centred one-line system line instead, with
/// no disc and no Copy.
class MessageTile extends StatelessWidget {
  const MessageTile({super.key, required this.message, this.onCopy});

  final MessageView message;

  /// Copy is shown on readable memos only when this is set.
  final ValueChanged<MessageView>? onCopy;

  @override
  Widget build(BuildContext context) {
    if (message.isEvent) return _systemLine(context);
    final indent = message.mine
        ? const EdgeInsets.only(left: 48)
        : const EdgeInsets.only(right: 48);
    return Padding(
      padding: indent,
      child: KeyedSubtree(
        key: ValueKey('memo-${message.id}'),
        child: _withDisc(
          context,
          message.locked ? _locked(context) : _memo(context),
        ),
      ),
    );
  }

  static const discSize = 28.0;
  static const _discGap = 8.0;

  Widget _withDisc(BuildContext context, Widget memo) {
    final c = RelayColors.of(context);
    final color = c.person(message.senderId, mine: message.mine);
    final disc = Container(
      key: ValueKey('disc-${message.id}'),
      width: discSize,
      height: discSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        message.initial,
        style: TextStyle(
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w600,
          color: c.surface,
        ),
      ),
    );
    const room = discSize + _discGap;
    return Semantics(
      label: 'From ${message.senderName}',
      child: Stack(
        children: [
          Padding(
            padding: message.mine
                ? const EdgeInsets.only(right: room)
                : const EdgeInsets.only(left: room),
            child: memo,
          ),
          Positioned(
            top: 0,
            bottom: 0,
            width: discSize,
            left: message.mine ? null : 0,
            right: message.mine ? 0 : null,
            child: ExcludeSemantics(child: StickyFollower(child: disc)),
          ),
        ],
      ),
    );
  }

  Widget _systemLine(BuildContext context) {
    final c = RelayColors.of(context);
    final rule = Expanded(child: Divider(color: c.line, height: 1));
    return KeyedSubtree(
      key: ValueKey('event-${message.id}'),
      child: LayoutBuilder(
        // The rules share what the text leaves, so the line stays centred.
        builder: (context, box) => Row(
          children: [
            rule,
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * .8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  message.body ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
                ),
              ),
            ),
            rule,
          ],
        ),
      ),
    );
  }

  String get _lockedText {
    final name = message.senderName;
    return switch (message.lockedReason) {
      LockedReason.theyHaveNotApprovedYou =>
        "Locked — $name hasn't approved you",
      LockedReason.youHaveNotApprovedThem =>
        "Locked — $name hasn't been approved by you",
      null => "Locked — $name hasn't approved you yet",
    };
  }

  Widget _locked(BuildContext context) {
    final c = RelayColors.of(context);
    return DashedBorderBox(
      color: c.outline,
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _lockedText,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memo(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    final label = TextStyle(fontSize: 12, height: 1.4, color: c.muted);
    final ref = message.context?.line;
    final body = message.body;

    TableRow row(String name, Widget value) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 4),
          child: Text(name, style: label),
        ),
        Padding(padding: const EdgeInsets.only(bottom: 4), child: value),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              row(
                'From',
                Text(
                  message.senderName,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: c.person(message.senderId, mine: message.mine),
                  ),
                ),
              ),
              if (ref != null)
                row('Ref', Text(ref, style: RelayText.mono(c.muted))),
              row(
                'Time',
                Text(
                  formatDateTime(message.sentAt),
                  style: label.copyWith(fontFeatures: RelayText.tabular),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (body != null && body.isNotEmpty)
            SelectableText(body, style: theme.textTheme.bodyMedium),
          if (message.mine)
            for (final r in message.receipts) ...[
              const SizedBox(height: 8),
              _ReceiptLine(receipt: r),
            ],
          if (message.arrivedLate || onCopy != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (message.arrivedLate) ...[
                  Icon(Icons.schedule, size: 16, color: c.warning),
                  const SizedBox(width: 4),
                  Text(
                    'Arrived late',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.warning,
                    ),
                  ),
                ],
                const Spacer(),
                if (onCopy != null && body != null)
                  OutlinedButton(
                    onPressed: () => onCopy!(message),
                    child: const Text('Copy'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Delivered → seen in the app → read by their agent, for one recipient.
class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({required this.receipt});

  final ReceiptView receipt;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<RelayColors>()!;
    final style = TextStyle(
      fontSize: 12,
      color: c.muted,
      fontFeatures: RelayText.tabular,
    );
    Widget item(IconData icon, String text, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: style.copyWith(color: color)),
      ],
    );
    final r = receipt;
    final parts = <Widget>[
      if (r.deliveredAt == null)
        item(Icons.schedule, "Waiting for ${r.personName}'s Mac", c.muted)
      else if (r.seenAt == null && r.agentReadAt == null)
        item(Icons.done, 'Delivered ${formatTime(r.deliveredAt!)}', c.muted),
      if (r.seenAt != null)
        item(
          Icons.visibility_outlined,
          'Seen ${formatTime(r.seenAt!)}',
          c.muted,
        ),
      if (r.agentReadAt != null)
        item(
          Icons.done_all,
          "${r.personName}'s agent read it ${formatTime(r.agentReadAt!)}",
          c.success,
        ),
    ];
    return Wrap(spacing: 12, runSpacing: 4, children: parts);
  }
}
