import 'package:agent_relay/ui/channels/message_tile.dart';
import 'package:agent_relay/ui/channels/message_view.dart';
import 'package:agent_relay/ui/theme/relay_theme.dart';
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

  group('receipts on my memos', () {
    MessageView mine(List<ReceiptView> receipts) => MessageView(
      id: 'm2',
      senderName: 'You',
      sentAt: sentAt,
      body: 'Staging is free now',
      mine: true,
      receipts: receipts,
    );

    testWidgets('not yet delivered says it is waiting for their Mac', (
      tester,
    ) async {
      await pumpUi(
        tester,
        MessageTile(
          message: mine([
            (
              personName: 'Xavier',
              deliveredAt: null,
              seenAt: null,
              agentReadAt: null,
            ),
          ]),
        ),
      );
      expect(find.text("Waiting for Xavier's Mac"), findsOneWidget);
    });

    testWidgets(
      'delivered, seen and read by their agent each show with a time',
      (tester) async {
        await pumpUi(
          tester,
          MessageTile(
            message: mine([
              (
                personName: 'Xavier',
                deliveredAt: DateTime(2026, 11, 20, 9, 41),
                seenAt: DateTime(2026, 11, 20, 9, 42),
                agentReadAt: DateTime(2026, 11, 20, 9, 44),
              ),
            ]),
          ),
        );
        expect(find.text('Seen 9:42 AM'), findsOneWidget);
        expect(find.text("Xavier's agent read it 9:44 AM"), findsOneWidget);
        expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
        expect(find.byIcon(Icons.done_all), findsOneWidget);
      },
    );

    testWidgets('delivered but unread says Delivered', (tester) async {
      await pumpUi(
        tester,
        MessageTile(
          message: mine([
            (
              personName: 'Xavier',
              deliveredAt: DateTime(2026, 11, 20, 9, 41),
              seenAt: null,
              agentReadAt: null,
            ),
          ]),
        ),
      );
      expect(find.text('Delivered 9:41 AM'), findsOneWidget);
    });

    testWidgets('their memos show no receipt line', (tester) async {
      await pumpUi(
        tester,
        MessageTile(
          message: MessageView(
            id: 'x',
            senderName: 'Xavier',
            sentAt: sentAt,
            body: 'hi',
          ),
        ),
      );
      expect(find.textContaining('Delivered'), findsNothing);
      expect(find.textContaining('Waiting for'), findsNothing);
    });
  });

  group('sender disc', () {
    testWidgets('shows the initial in the sender colour; mine on the right', (
      tester,
    ) async {
      await pumpUi(
        tester,
        Column(
          children: [
            MessageTile(
              message: MessageView(
                id: 'in1',
                senderName: 'Xaves',
                senderId: 'dev-x',
                sentAt: sentAt,
                body: 'hello',
              ),
            ),
            MessageTile(
              message: MessageView(
                id: 'out1',
                senderName: 'You',
                senderId: 'dev-me',
                initial: 'I',
                mine: true,
                sentAt: sentAt,
                body: 'hi',
              ),
            ),
          ],
        ),
      );
      final ctx = tester.element(find.byType(Column).first);
      final c = RelayColors.of(ctx);
      Color fill(String id) =>
          ((tester.widget<Container>(find.byKey(ValueKey('disc-$id'))))
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(find.text('X'), findsOneWidget);
      expect(find.text('I'), findsOneWidget);
      expect(fill('in1'), c.person('dev-x'));
      expect(fill('out1'), c.primaryText);
      final width = tester.getSize(find.byType(Column).first).width;
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('disc-in1'))).dx,
        lessThan(width / 2),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('disc-out1'))).dx,
        greaterThan(width / 2),
      );
    });

    testWidgets('follows a long memo while it scrolls, then stops at its end', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpUi(
        tester,
        SizedBox(
          height: 400,
          child: ListView(
            controller: controller,
            children: [
              MessageTile(
                message: MessageView(
                  id: 'long',
                  senderName: 'Xaves',
                  senderId: 'dev-x',
                  sentAt: sentAt,
                  body: List.filled(
                    80,
                    'A line of the refund update.',
                  ).join('\n'),
                ),
              ),
              const SizedBox(height: 600),
            ],
          ),
        ),
      );
      final disc = find.byKey(const ValueKey('disc-long'));
      final memo = find.byKey(const ValueKey('memo-long'));
      final viewTop = tester.getTopLeft(find.byType(ListView)).dy;
      expect(tester.getTopLeft(disc).dy, tester.getTopLeft(memo).dy);

      controller.jumpTo(300);
      await tester.pump();
      expect(tester.getTopLeft(memo).dy, lessThan(viewTop));
      expect(tester.getTopLeft(disc).dy, closeTo(viewTop + 8, 0.5));

      final memoHeight = tester.getSize(memo).height;
      controller.jumpTo(memoHeight - 10);
      await tester.pump();
      expect(
        tester.getBottomLeft(disc).dy,
        closeTo(tester.getBottomLeft(memo).dy, 0.5),
        reason: 'stops at the bottom of its own memo',
      );
    });
  });
}
