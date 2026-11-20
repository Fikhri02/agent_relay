import 'package:flutter/material.dart';

import '../common/relay_widgets.dart';
import '../theme/relay_theme.dart';

/// First run: who this person is and what this Mac is called.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    this.initialName = '',
    this.initialDeviceName = '',
    required this.onStart,
    this.busy = false,
    this.error,
  });

  /// Prefill, e.g. the macOS full name.
  final String initialName;

  /// Prefill, e.g. `scutil --get ComputerName`.
  final String initialDeviceName;

  /// Called with trimmed, non-empty values.
  final void Function(String personName, String deviceName) onStart;

  /// Disables the button while the relay starts.
  final bool busy;

  /// A start failure, shown above the button.
  final String? error;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _device = TextEditingController(text: widget.initialDeviceName);
  String? _nameError;
  String? _deviceError;

  @override
  void dispose() {
    _name.dispose();
    _device.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final device = _device.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Enter your name' : null;
      _deviceError = device.isEmpty ? 'Enter a name for this Mac' : null;
    });
    if (_nameError == null && _deviceError == null) {
      widget.onStart(name, device);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: RelayPanel(
            maxWidth: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Set up Agent Relay', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Teammates see these names when you pair and when your '
                  'agent sends them a message.',
                  style: TextStyle(fontSize: 12, height: 1.45, color: c.muted),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('setup-name'),
                  controller: _name,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Your name',
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('setup-device'),
                  controller: _device,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'This Mac',
                    errorText: _deviceError,
                  ),
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.error!,
                    style: TextStyle(fontSize: 12, color: c.danger),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: widget.busy ? null : _submit,
                    child: const Text('Start Agent Relay'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
