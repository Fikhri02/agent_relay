import 'package:flutter/material.dart';

import '../channels/message_view.dart';
import '../common/relay_widgets.dart';
import '../theme/relay_format.dart';
import '../theme/relay_theme.dart';

/// A message awaiting approval.
class DraftView {
  const DraftView({
    required this.id,
    required this.channelName,
    required this.body,
    required this.createdAt,
    this.context,
  });

  final String id;

  /// Person or surat it goes to: the card reads "Send to {channelName}?".
  final String channelName;
  final String body;
  final DateTime createdAt;
  final MessageContext? context;
}

/// Drafts awaiting approval, each with a red outlined Discard and a solid
/// Send. Used as the Outbox tab's stage and on its own.
class OutboxScreen extends StatelessWidget {
  const OutboxScreen({
    super.key,
    required this.drafts,
    required this.onSend,
    required this.onDiscard,
  });

  /// Null while loading.
  final List<DraftView>? drafts;
  final ValueChanged<String> onSend;
  final ValueChanged<String> onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = RelayColors.of(context);
    final list = drafts;
    if (list == null) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: PlaceholderRows(height: 120),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Nothing awaiting approval — drafts your agent writes appear '
            'here for you to send or discard',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => Align(
        alignment: Alignment.topLeft,
        child: _DraftCard(draft: list[i], onSend: onSend, onDiscard: onDiscard),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.onSend,
    required this.onDiscard,
  });

  final DraftView draft;
  final ValueChanged<String> onSend;
  final ValueChanged<String> onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    final ref = draft.context?.line;
    return RelayPanel(
      maxWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Send to ${draft.channelName}?',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatDateTime(draft.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: c.muted,
                  fontFeatures: RelayText.tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              draft.body,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (ref != null) ...[
            const SizedBox(height: 8),
            Text('Ref: $ref', style: RelayText.mono(c.muted)),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => onDiscard(draft.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.danger,
                  side: BorderSide(color: c.danger),
                  overlayColor: c.danger,
                ),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => onSend(draft.id),
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
