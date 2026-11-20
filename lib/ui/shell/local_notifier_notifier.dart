import 'package:local_notifier/local_notifier.dart';

import '../../node/notifier.dart';

/// macOS notifications through `local_notifier`. A tagged notification can be
/// removed later (an approval answered elsewhere).
class LocalNotifierNotifier implements Notifier {
  final _byTag = <String, LocalNotification>{};

  @override
  Future<void> show(
    NotificationText text, {
    String? tag,
    List<String> actions = const [],
    void Function(int action)? onAction,
    void Function()? onClick,
  }) async {
    final n =
        LocalNotification(
            identifier: tag,
            title: text.title,
            body: text.body,
            actions: [
              for (final a in actions) LocalNotificationAction(text: a),
            ],
          )
          ..onClick = onClick
          ..onClickAction = onAction;
    if (tag != null) _byTag[tag] = n;
    await n.show();
  }

  @override
  Future<void> remove(String tag) async {
    await _byTag.remove(tag)?.close();
  }
}
