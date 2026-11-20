import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../node/notifier.dart';
import '../node/relay_node.dart';
import '../ui/channels/channels_screen.dart';
import '../ui/outbox/outbox_screen.dart';
import '../ui/pairing/pairing_screen.dart';
import '../ui/setup/setup_screen.dart';
import '../ui/shell/login_item.dart';
import '../ui/shell/tray_controller.dart';
import '../ui/shell/tray_entries.dart';
import '../ui/theme/relay_theme.dart';
import 'app_controller.dart';

/// The window: setup on first run, then the memo desk. The app keeps running
/// in the menu bar when the window is closed.
class RelayApp extends StatefulWidget {
  const RelayApp({super.key, required this.node, required this.notifier});

  final RelayNode node;
  final Notifier notifier;

  @override
  State<RelayApp> createState() => _RelayAppState();
}

class _RelayAppState extends State<RelayApp> with WindowListener {
  final _nav = GlobalKey<NavigatorState>();
  AppController? _ctl;
  late final TrayController _tray;
  final _login = const LoginItem();
  bool _launchAtLogin = false;
  bool _visible = false;
  bool _setupBusy = false;
  String? _setupError;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _tray = TrayController(onCommand: _onTray);
    unawaited(_tray.init().then((_) => _pushTray()));
    unawaited(
      _login.isEnabled().then((v) => setState(() => _launchAtLogin = v)),
    );
    if (widget.node.identity != null) {
      unawaited(_startController());
    } else {
      unawaited(_show());
    }
  }

  Future<void> _startController() async {
    final ctl = AppController(
      widget.node,
      widget.notifier,
      windowVisible: () => _visible,
    );
    ctl.addListener(() {
      _pushTray();
      if (mounted) setState(() {});
    });
    await ctl.init();
    setState(() => _ctl = ctl);
  }

  void _pushTray() {
    final ctl = _ctl;
    final channels = ctl?.channels ?? const [];
    _tray.update(
      trayEntries(
        unread: {for (final c in channels) c.id: c.unread},
        channels: channels,
        awaitingApproval: ctl?.awaitingApproval ?? 0,
        launchAtLogin: _launchAtLogin,
      ),
    );
    unawaited(_tray.setUnread(channels.fold(0, (n, c) => n + c.unread)));
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
    _visible = true;
  }

  Future<void> _onTray(TrayCommand command, String? channelId) async {
    switch (command) {
      case TrayCommand.openChannel:
        await _show();
        if (channelId != null) await _ctl?.select(channelId);
      case TrayCommand.openOutbox:
        await _show();
        await _ctl?.select(outboxSelectionId);
      case TrayCommand.openRelay:
        await _show();
      case TrayCommand.pairTeammate:
        await _show();
        _openPairing();
      case TrayCommand.toggleLaunchAtLogin:
        final v = await _login.setEnabled(!_launchAtLogin);
        setState(() => _launchAtLogin = v);
        _pushTray();
      case TrayCommand.quit:
        await widget.node.stop();
        exit(0);
    }
  }

  void _openPairing() {
    final ctl = _ctl;
    if (ctl == null) return;
    widget.node.pairing.openWindow();
    _nav.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => _PairingPage(node: widget.node, ctl: ctl),
      ),
    );
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
    _visible = false;
  }

  @override
  void onWindowFocus() {
    _visible = true;
    final id = _ctl?.selectedId;
    if (id != null) unawaited(_ctl!.select(id));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tray.dispose();
    _ctl?.dispose();
    super.dispose();
  }

  Future<void> _setup(String name, String device) async {
    setState(() {
      _setupBusy = true;
      _setupError = null;
    });
    try {
      await widget.node.setup(personName: name, deviceName: device);
      await _startController();
    } on Object catch (e) {
      setState(() => _setupError = "Couldn't start Agent Relay: $e");
    } finally {
      if (mounted) setState(() => _setupBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    return MaterialApp(
      navigatorKey: _nav,
      debugShowCheckedModeBanner: false,
      title: 'Agent Relay',
      theme: RelayTheme.light(),
      darkTheme: RelayTheme.dark(),
      home: Scaffold(
        body: ctl == null
            ? SetupScreen(
                initialDeviceName: Platform.localHostname.split('.').first,
                onStart: _setup,
                busy: _setupBusy,
                error: _setupError,
              )
            : ChannelsScreen(
                channels: ctl.channels,
                selectedId: ctl.selectedId,
                messages: ctl.messages,
                gaps: ctl.gaps,
                peers: ctl.peers,
                awaitingApproval: ctl.awaitingApproval,
                onSelect: (id) => unawaited(ctl.select(id)),
                onCopy: (m) =>
                    Clipboard.setData(ClipboardData(text: m.body ?? '')),
                onPairTeammate: _openPairing,
                outboxPane: OutboxScreen(
                  drafts: ctl.drafts,
                  onSend: (id) => unawaited(ctl.approve(id)),
                  onDiscard: (id) => unawaited(ctl.discard(id)),
                ),
              ),
      ),
    );
  }
}

class _PairingPage extends StatefulWidget {
  const _PairingPage({required this.node, required this.ctl});
  final RelayNode node;
  final AppController ctl;

  @override
  State<_PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<_PairingPage> {
  late final Timer _tick;
  String? _addressError;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    widget.ctl.addListener(_changed);
  }

  void _changed() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    _tick.cancel();
    widget.ctl.removeListener(_changed);
    super.dispose();
  }

  Future<void> _connect(String host, int port) async {
    setState(() => _addressError = null);
    try {
      await widget.node.pairing.connect((
        host: host,
        port: port,
        pinnedFingerprint: null,
      ));
    } on Object {
      setState(
        () => _addressError =
            "Couldn't reach $host:$port. Check that Agent Relay is open there and its pairing is open.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.node.pairing.window;
    final closes = window.isOpen ? window.closesAt : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Pair a teammate')),
      body: PairingScreen(
        windowRemaining: closes?.difference(DateTime.now()),
        discovered: widget.ctl.discovered.values.toList(),
        code: widget.ctl.pairingCode,
        addressError: _addressError,
        onOpenPairing: () => setState(window.open),
        onClosePairing: () => setState(window.close),
        onPairWith: (mac) {
          final i = mac.address.lastIndexOf(':');
          unawaited(
            _connect(
              mac.address.substring(0, i),
              int.parse(mac.address.substring(i + 1)),
            ),
          );
        },
        onConnectAddress: (h, p) => unawaited(_connect(h, p)),
        onCodesMatch: () async {
          await widget.ctl.confirmPairing();
          if (context.mounted && widget.ctl.pairingCode == null) {
            Navigator.of(context).pop();
          }
        },
        onCancelCode: widget.ctl.cancelPairing,
      ),
    );
  }
}
