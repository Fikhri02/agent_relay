import 'package:flutter/material.dart';

import '../common/relay_widgets.dart';
import '../theme/relay_format.dart';
import '../theme/relay_theme.dart';

/// A Mac seen on the network by mDNS.
class DiscoveredMac {
  const DiscoveredMac({
    required this.id,
    required this.personName,
    required this.deviceName,
    required this.address,
  });

  final String id;
  final String personName;
  final String deviceName;

  /// `host:port`.
  final String address;
}

/// The comparison code both Macs show while pairing.
class PairingCodePrompt {
  const PairingCodePrompt({
    required this.code,
    required this.personName,
    required this.deviceName,
  });

  /// Six digits, shown as "482 913".
  final String code;
  final String personName;
  final String deviceName;
}

/// Pairing: open this Mac for 5:00, pick a discovered Mac or enter an
/// address, then compare the 6-digit code.
class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    required this.windowRemaining,
    required this.discovered,
    required this.code,
    this.addressError,
    required this.onOpenPairing,
    required this.onClosePairing,
    required this.onPairWith,
    required this.onConnectAddress,
    required this.onCodesMatch,
    required this.onCancelCode,
  });

  /// Time left in the pairing window; null when closed.
  final Duration? windowRemaining;

  /// Macs found on the network; null while the first browse runs.
  final List<DiscoveredMac>? discovered;

  /// When set, the screen shows only the code comparison.
  final PairingCodePrompt? code;

  /// A connect failure for the entered address, shown under the field.
  final String? addressError;

  final VoidCallback onOpenPairing;
  final VoidCallback onClosePairing;
  final ValueChanged<DiscoveredMac> onPairWith;
  final void Function(String host, int port) onConnectAddress;
  final VoidCallback onCodesMatch;
  final VoidCallback onCancelCode;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  static const _addressHelp = 'Enter an address like 192.168.1.20:8790';
  final _address = TextEditingController();
  String? _addressError;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _connect() {
    final text = _address.text.trim();
    final colon = text.lastIndexOf(':');
    final host = colon > 0 ? text.substring(0, colon) : '';
    final port = colon > 0 ? int.tryParse(text.substring(colon + 1)) : null;
    final ok =
        host.isNotEmpty &&
        !host.contains(RegExp(r'\s')) &&
        port != null &&
        port > 0 &&
        port <= 65535;
    setState(() => _addressError = ok ? null : _addressHelp);
    if (ok) widget.onConnectAddress(host, port);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = widget.code;
    return Material(
      color: theme.colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: code != null
              ? _codePanel(context, code)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _windowPanel(context),
                      const SizedBox(height: 16),
                      _pairPanel(context),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _codePanel(BuildContext context, PairingCodePrompt code) {
    final theme = Theme.of(context);
    return RelayPanel(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pair with ${code.deviceName}',
            style: theme.textTheme.titleMedium,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              formatCode(code.code),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
                fontFeatures: RelayText.tabular,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: widget.onCancelCode,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: widget.onCodesMatch,
                child: const Text('Codes match'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _windowPanel(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    final remaining = widget.windowRemaining;
    return RelayPanel(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Let a teammate pair with this Mac',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (remaining == null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pairing stays open for 5:00. Your teammate then picks '
                    'this Mac on theirs.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: c.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: widget.onOpenPairing,
                  child: const Text('Open pairing'),
                ),
              ],
            )
          else
            Row(
              children: [
                StatusDot(c.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pairing open · ${formatCountdown(remaining)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.success,
                      fontFeatures: RelayText.tabular,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: widget.onClosePairing,
                  child: const Text('Close pairing'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _pairPanel(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    final found = widget.discovered;
    return RelayPanel(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Pair with a teammate's Mac",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (found == null)
            const PlaceholderRows(count: 2, height: 64)
          else if (found.isEmpty)
            Text(
              'No Macs found on this network yet — ask your teammate to '
              'open pairing, or enter their address below',
              style: TextStyle(fontSize: 12, height: 1.45, color: c.muted),
            )
          else
            for (final mac in found) _macRow(context, mac),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('pairing-address'),
                  controller: _address,
                  onChanged: (_) {
                    if (_addressError != null) {
                      setState(() => _addressError = null);
                    }
                  },
                  onSubmitted: (_) => _connect(),
                  decoration: InputDecoration(
                    labelText: 'Enter address',
                    hintText: '192.168.1.20:8790',
                    errorText: _addressError ?? widget.addressError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton(
                  onPressed: _connect,
                  child: const Text('Connect'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macRow(BuildContext context, DiscoveredMac mac) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.laptop_mac, size: 16, color: c.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mac.personName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${mac.deviceName} · ${mac.address}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.muted,
                    fontFeatures: RelayText.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => widget.onPairWith(mac),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }
}
