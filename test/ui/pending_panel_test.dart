import 'package:agent_relay/ui/surat/pending_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

const items = [
  PendingView(
    id: 'invite:s1:me',
    suratId: 's1',
    kind: PendingKind.invite,
    suratName: 'Release',
    inviter: 'Xaves',
  ),
  PendingView(
    id: 'newcomer:s2:d3',
    suratId: 's2',
    kind: PendingKind.newcomer,
    suratName: 'Staging',
    inviter: 'Xaves',
    newcomer: 'Tommy',
  ),
];

void main() {
  late List<(String, bool)> decided;
  setUp(() => decided = []);
  Widget panel(List<PendingView> list) => PendingPanel(
    items: list,
    onDecide: (id, {required approve}) => decided.add((id, approve)),
  );

  testWidgets('pending panel approve calls decide(id, approve: true)', (
    tester,
  ) async {
    await pumpUi(tester, panel(items));
    expect(find.text('Xaves invited Tommy to Staging'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    expect(decided, [('newcomer:s2:d3', true)]);
  });

  testWidgets('an invite offers Accept and Decline', (tester) async {
    await pumpUi(tester, panel(items));
    expect(find.text('Xaves invited you to Release'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pending-invite:s1:me')),
        matching: find.widgetWithText(OutlinedButton, 'Decline'),
      ),
    );
    expect(decided, [('invite:s1:me', true), ('invite:s1:me', false)]);
  });

  testWidgets('a declined newcomer can still be approved, not declined again', (
    tester,
  ) async {
    await pumpUi(
      tester,
      panel(const [
        PendingView(
          id: 'newcomer:s2:d3',
          suratId: 's2',
          kind: PendingKind.newcomer,
          suratName: 'Staging',
          inviter: 'Xaves',
          newcomer: 'Tommy',
          declined: true,
        ),
      ]),
    );
    expect(find.text('You declined Tommy'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Decline'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    expect(decided, [('newcomer:s2:d3', true)]);
  });

  testWidgets('nothing pending renders nothing', (tester) async {
    await pumpUi(tester, panel(const []));
    expect(find.byType(FilledButton), findsNothing);
  });

  for (final b in Brightness.values) {
    testWidgets('renders in ${b.name} mode', (tester) async {
      await pumpUi(tester, panel(items), brightness: b);
      final ctx = tester.element(find.text('Xaves invited you to Release'));
      expect(Theme.of(ctx).brightness, b);
      expect(tester.takeException(), isNull);
    });
  }
}
