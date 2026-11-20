class NotificationText {
  const NotificationText(this.title, this.body);
  final String title;
  final String body;
  @override
  String toString() => '$title — $body';
}

/// macOS notifications, behind an interface so services can be tested.
abstract class Notifier {
  Future<void> show(
    NotificationText text, {
    String? tag,
    List<String> actions = const [],
    void Function(int action)? onAction,
    void Function()? onClick,
  });

  /// Removes the notification shown with [tag], if still on screen.
  Future<void> remove(String tag);
}

class RecordingNotifier implements Notifier {
  final shown = <NotificationText>[];
  final removed = <String>[];

  @override
  Future<void> show(
    NotificationText text, {
    String? tag,
    List<String> actions = const [],
    void Function(int action)? onAction,
    void Function()? onClick,
  }) async {
    shown.add(text);
  }

  @override
  Future<void> remove(String tag) async => removed.add(tag);
}
