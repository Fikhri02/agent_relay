import 'package:flutter/material.dart';

import '../../surat/surat_state.dart' show suratSeatCap;
import '../theme/relay_theme.dart';

/// A paired person the new surat can invite.
typedef PeerChoice = ({String deviceId, String personName, String deviceName});

/// People I can invite at creation: every seat but mine.
const maxInvitees = suratSeatCap - 1;

/// "New surat": a name and a checklist of paired people, at most
/// [maxInvitees]. Create hands both to [onCreate], which drafts the surat;
/// the draft then waits in the Outbox like any send.
class NewSuratDialog extends StatefulWidget {
  const NewSuratDialog({
    super.key,
    required this.people,
    required this.onCreate,
  });

  final List<PeerChoice> people;
  final Future<void> Function(String name, List<String> deviceIds) onCreate;

  @override
  State<NewSuratDialog> createState() => _NewSuratDialogState();
}

class _NewSuratDialogState extends State<NewSuratDialog> {
  final _name = TextEditingController();
  final _picked = <String>[];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _full => _picked.length >= maxInvitees;
  bool get _ready =>
      !_busy && _name.text.trim().isNotEmpty && _picked.isNotEmpty;

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id) && !_full) _picked.add(id);
  });

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Keep the list's order, not the order of the clicks.
    final ids = [
      for (final p in widget.people)
        if (_picked.contains(p.deviceId)) p.deviceId,
    ];
    try {
      await widget.onCreate(_name.text.trim(), ids);
      if (mounted) await Navigator.of(context).maybePop();
    } on Object catch (e) {
      if (mounted) setState(() => _error = "Couldn't create the surat: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    final muted = TextStyle(fontSize: 12, color: c.muted);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New surat', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('surat-name'),
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'What it is about',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('People', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    _picked.isEmpty
                        ? 'Up to $maxInvitees people'
                        : '${_picked.length} of $maxInvitees picked',
                    style: muted.copyWith(fontFeatures: RelayText.tabular),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.people.isEmpty)
                Text(
                  'Pair a teammate first — a surat is made from paired people',
                  style: muted.copyWith(fontSize: 13),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [for (final p in widget.people) _row(p, muted)],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text('It waits in the Outbox until you send it.', style: muted),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(fontSize: 12, color: c.danger)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _ready ? _create : null,
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(PeerChoice p, TextStyle muted) {
    final picked = _picked.contains(p.deviceId);
    final enabled = picked || !_full;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? () => _toggle(p.deviceId) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('pick-${p.deviceId}'),
              value: picked,
              onChanged: enabled ? (_) => _toggle(p.deviceId) : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.personName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: enabled ? null : RelayColors.of(context).muted,
                    ),
                  ),
                  Text(
                    p.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
