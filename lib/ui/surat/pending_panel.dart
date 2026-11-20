import 'package:flutter/material.dart';

import '../theme/relay_theme.dart';

enum PendingKind {
  /// I was invited: Accept / Decline.
  invite,

  /// Someone else invited a newcomer: Approve / Decline.
  newcomer,
}

/// A decision waiting for me, with names already resolved for display
/// ("{person} ({device})" where two members share a person name).
class PendingView {
  const PendingView({
    required this.id,
    required this.suratId,
    required this.kind,
    required this.suratName,
    this.inviter,
    this.newcomer = '',
    this.declined = false,
  });

  /// The pending id `SuratService.decide` takes.
  final String id;
  final String suratId;
  final PendingKind kind;
  final String suratName;

  /// Who sent the invite; null when unknown.
  final String? inviter;

  /// The newcomer's name ([PendingKind.newcomer] only).
  final String newcomer;

  /// I declined this newcomer before; I can still approve them.
  final bool declined;

  /// The line the panel and the notification show.
  String get line => switch (kind) {
    PendingKind.invite =>
      inviter == null
          ? "You're invited to $suratName"
          : '$inviter invited you to $suratName',
    PendingKind.newcomer =>
      inviter == null
          ? '$newcomer was invited to $suratName'
          : '$inviter invited $newcomer to $suratName',
  };
}

/// Invites to me and newcomers waiting for my approval, one card each with
/// its answer buttons. Renders nothing when [items] is empty.
class PendingPanel extends StatelessWidget {
  const PendingPanel({super.key, required this.items, required this.onDecide});

  final List<PendingView> items;
  final void Function(String id, {required bool approve}) onDecide;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in items.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _PendingCard(item: p, onDecide: onDecide),
        ],
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.item, required this.onDecide});

  final PendingView item;
  final void Function(String id, {required bool approve}) onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    final invite = item.kind == PendingKind.invite;
    return Container(
      key: ValueKey('pending-${item.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(
            invite ? Icons.mail_outline : Icons.person_add_alt_1_outlined,
            size: 16,
            color: c.primaryText,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.line, style: theme.textTheme.bodyMedium),
                if (item.declined)
                  Text(
                    'You declined ${item.newcomer}',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!item.declined) ...[
            OutlinedButton(
              onPressed: () => onDecide(item.id, approve: false),
              child: const Text('Decline'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton(
            onPressed: () => onDecide(item.id, approve: true),
            child: Text(invite ? 'Accept' : 'Approve'),
          ),
        ],
      ),
    );
  }
}
