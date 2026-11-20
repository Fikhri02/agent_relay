import 'package:agent_relay/ui/setup/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('setup screen requires a name, error under the field', (
    tester,
  ) async {
    final starts = <(String, String)>[];
    await pumpUi(
      tester,
      SetupScreen(
        initialDeviceName: 'Irfan MacBook Pro',
        onStart: (name, device) => starts.add((name, device)),
      ),
    );
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('This Mac'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Start Agent Relay'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(starts, isEmpty);
    final nameField = find.byKey(const ValueKey('setup-name'));
    expect(
      tester.getTopLeft(find.text('Enter your name')).dy,
      greaterThan(tester.getTopLeft(nameField).dy),
    );

    await tester.enterText(nameField, '  Irfan Fikhri ');
    await tester.tap(find.widgetWithText(FilledButton, 'Start Agent Relay'));
    await tester.pump();
    expect(find.text('Enter your name'), findsNothing);
    expect(starts, [('Irfan Fikhri', 'Irfan MacBook Pro')]);
  });
}
