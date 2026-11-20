import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'app/relay_app.dart';
import 'config/app_config.dart';
import 'node/relay_node.dart';
import 'ui/shell/local_notifier_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await localNotifier.setup(appName: 'Agent Relay');
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Agent Relay',
      size: Size(1000, 680),
      minimumSize: Size(720, 480),
      center: true,
      skipTaskbar: true,
    ),
    // Starts hidden: the app lives in the menu bar until asked for.
    () => windowManager.hide(),
  );
  await windowManager.setPreventClose(true);

  final config = AppConfig.fromEnvironment(
    Platform.environment,
    homeDir: Platform.environment['HOME'] ?? '',
  );
  final notifier = LocalNotifierNotifier();
  final node = await RelayNode.start(config, notifier: notifier);
  runApp(RelayApp(node: node, notifier: notifier));
}
