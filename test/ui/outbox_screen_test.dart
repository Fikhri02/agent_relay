import 'package:agent_relay/ui/channels/message_view.dart';
import 'package:agent_relay/ui/outbox/outbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  final drafts = [
    DraftView(
      id: 'd1',
      channelName: 'Xavier',
      body: 'Staging is free now, go ahead with the scheduler redeploy.',
      context: const MessageContext(
        repo: 'Middleware',
        branch: 'irfan/tiered-discount',
        commit: 'f6a96a1',
      ),
      createdAt: DateTime(2026, 11, 20, 9, 41),
    ),
  ];

  testWidgets(
    'outbox Send calls the send callback, Discard the discard callback',
    (tester) async {
      final sent = <String>[];
      final discarded = <String>[];
      await pumpUi(
        tester,
        OutboxScreen(
          drafts: drafts,
          onSend: sent.add,
          onDiscard: discarded.add,
        ),
      );

      expect(find.text('Send to Xavier?'), findsOneWidget);
      expect(
        find.text('Staging is free now, go ahead with the scheduler redeploy.'),
        findsOneWidget,
      );
      expect(
        find.text('Ref: Middleware · irfan/tiered-discount · f6a96a1'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      expect(sent, ['d1']);
      expect(discarded, isEmpty);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Discard'));
      expect(discarded, ['d1']);
    },
  );

  testWidgets('empty outbox says why and the way out', (tester) async {
    await pumpUi(
      tester,
      OutboxScreen(drafts: const [], onSend: (_) {}, onDiscard: (_) {}),
    );
    expect(find.textContaining('Nothing awaiting approval'), findsOneWidget);
  });

  testWidgets('loading outbox shows placeholder rows, not a blank pane', (
    tester,
  ) async {
    await pumpUi(
      tester,
      OutboxScreen(drafts: null, onSend: (_) {}, onDiscard: (_) {}),
    );
    expect(find.byKey(const ValueKey('placeholder-rows')), findsOneWidget);
  });
}
