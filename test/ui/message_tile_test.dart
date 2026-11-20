import 'package:agent_relay/ui/channels/message_tile.dart';
import 'package:agent_relay/ui/channels/message_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  final sentAt = DateTime(2026, 11, 20, 9, 41);

  testWidgets('message tile shows arrived late chip and context line', (
    tester,
  ) async {
    MessageView? copied;
    final message = MessageView(
      id: 'm1',
      senderName: 'Xavier',
      sentAt: sentAt,
      body: "Got it. I'll hold the Middleware deploy until 5 PM.",
      context: const MessageContext(
        repo: 'Middleware',
        branch: 'irfan/tiered-discount',
        commit: 'f6a96a1',
      ),
      arrivedLate: true,
    );
    await pumpUi(
      tester,
      MessageTile(message: message, onCopy: (m) => copied = m),
    );

    expect(find.text('Arrived late'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(
      find.text('Middleware · irfan/tiered-discount · f6a96a1'),
      findsOneWidget,
    );
    expect(
      find.text("Got it. I'll hold the Middleware deploy until 5 PM."),
      findsOneWidget,
    );
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Ref'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Xavier'), findsOneWidget);
    expect(find.text('20 Nov 2026, 9:41 AM'), findsOneWidget);

    final copy = find.widgetWithText(OutlinedButton, 'Copy');
    expect(copy, findsOneWidget);
    await tester.tap(copy);
    expect(copied?.id, 'm1');
  });

  testWidgets('a message on time has no arrived late chip', (tester) async {
    await pumpUi(
      tester,
      MessageTile(
        message: MessageView(
          id: 'm2',
          senderName: 'Xavier',
          sentAt: sentAt,
          body: 'Hi',
        ),
        onCopy: (_) {},
      ),
    );
    expect(find.text('Arrived late'), findsNothing);
    expect(find.text('Ref'), findsNothing, reason: 'Ref row only with context');
  });

  testWidgets('my memos indent from the left, theirs from the right', (
    tester,
  ) async {
    await pumpUi(
      tester,
      Column(
        children: [
          MessageTile(
            key: const ValueKey('mine'),
            message: MessageView(
              id: 'a',
              senderName: 'You',
              sentAt: sentAt,
              body: 'x',
              mine: true,
            ),
            onCopy: (_) {},
          ),
          MessageTile(
            key: const ValueKey('theirs'),
            message: MessageView(
              id: 'b',
              senderName: 'Xavier',
              sentAt: sentAt,
              body: 'y',
            ),
            onCopy: (_) {},
          ),
        ],
      ),
    );
    final mine = tester.getRect(find.byKey(const ValueKey('memo-a')));
    final theirs = tester.getRect(find.byKey(const ValueKey('memo-b')));
    expect(mine.left - theirs.left, 48);
    expect(mine.right - theirs.right, 48);
  });

  testWidgets('locked message shows Locked text and no Copy button', (
    tester,
  ) async {
    await pumpUi(
      tester,
      MessageTile(
        message: MessageView(
          id: 'm3',
          senderName: 'Shaw Ping',
          sentAt: sentAt,
          locked: true,
        ),
        onCopy: (_) {},
      ),
    );

    expect(
      find.text("Locked — Shaw Ping hasn't approved you yet"),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
  });

  test(
    'context parses from the stored JSON and joins repo, branch, commit',
    () {
      final ctx = MessageContext.fromJson(
        '{"repo":"Middleware","branch":"main","commit":"abc1234","path":"src"}',
      );
      expect(ctx?.line, 'Middleware · main · abc1234');
      expect(MessageContext.fromJson(null), isNull);
      expect(MessageContext.fromJson('not json'), isNull);
      expect(MessageContext.fromJson('{}'), isNull);
    },
  );
}
