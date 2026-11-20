// Adapted from gallery_bridge apps/macos/lib/app/tray_menu.dart (TrayMenuBinder)
import 'dart:async';

import 'package:tray_manager/tray_manager.dart';

import 'tray_entries.dart';

/// Pushes [TrayEntry] lists to the real menu bar menu, at most once a second.
class TrayController with TrayListener {
  TrayController({required this.onCommand});

  final void Function(TrayCommand command, String? channelId) onCommand;
  List<TrayEntry>? _pending;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
    await trayManager.setToolTip('Agent Relay');
  }

  void update(List<TrayEntry> entries) {
    _pending = entries;
    final wait =
        const Duration(seconds: 1) - DateTime.now().difference(_lastPush);
    if (wait <= Duration.zero) {
      _push();
    } else {
      _timer ??= Timer(wait, _push);
    }
  }

  Future<void> setUnread(int unread) =>
      trayManager.setTitle(unread > 0 ? '$unread' : '');

  void _push() {
    _timer = null;
    final entries = _pending;
    if (entries == null) return;
    _pending = null;
    _lastPush = DateTime.now();
    unawaited(
      trayManager.setContextMenu(
        Menu(
          items: [
            for (final entry in entries)
              switch (entry) {
                TrayLabel(:final text) => MenuItem(label: text, disabled: true),
                TraySeparator() => MenuItem.separator(),
                TrayAction(:final label, :final command, :final checked)
                    when command == TrayCommand.toggleLaunchAtLogin =>
                  MenuItem.checkbox(
                    key: command.name,
                    label: label,
                    checked: checked,
                  ),
                TrayAction(:final label, :final command, :final channelId) =>
                  MenuItem(
                    key: '${command.name}|${channelId ?? ''}',
                    label: label,
                  ),
              },
          ],
        ),
      ),
    );
  }

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final parts = (menuItem.key ?? '').split('|');
    final command = TrayCommand.values
        .where((c) => c.name == parts.first)
        .firstOrNull;
    if (command == null) return;
    onCommand(
      command,
      parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
    );
  }

  void dispose() {
    _timer?.cancel();
    trayManager.removeListener(this);
  }
}
