import 'package:flutter/material.dart';

import '../common/relay_widgets.dart';
import '../theme/relay_format.dart';
import '../theme/relay_theme.dart';
import 'message_view.dart';

/// One message as a memo: a surface card with a From / Ref / Time header,
/// the body as selectable text, an "Arrived late" line and a Copy button.
///
/// My memos are indented 48 from the left, theirs 48 from the right. A
/// locked message is a dashed box with a lock and no Copy button.
class MessageTile extends StatelessWidget {
  const MessageTile({super.key, required this.message, this.onCopy});

  final MessageView message;

  /// Copy is shown on readable memos only when this is set.
  final ValueChanged<MessageView>? onCopy;

  @override
  Widget build(BuildContext context) {
    final indent = message.mine
        ? const EdgeInsets.only(left: 48)
        : const EdgeInsets.only(right: 48);
    return Padding(
      padding: indent,
      child: KeyedSubtree(
        key: ValueKey('memo-${message.id}'),
        child: message.locked ? _locked(context) : _memo(context),
      ),
    );
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
              "Locked — ${message.senderName} hasn't approved you yet",
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
                    color: theme.colorScheme.onSurface,
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
