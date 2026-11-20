import 'package:agent_relay/ui/pairing/pairing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('pairing screen shows the code with a space and both buttons', (
    tester,
  ) async {
    var matched = 0, cancelled = 0;
    await pumpUi(
      tester,
      PairingScreen(
        windowRemaining: const Duration(minutes: 4, seconds: 12),
        discovered: const [],
        code: const PairingCodePrompt(
          code: '482913',
          personName: 'Xavier',
          deviceName: "Xavier's MacBook Pro",
        ),
        onOpenPairing: () {},
        onClosePairing: () {},
        onPairWith: (_) {},
        onConnectAddress: (_, _) {},
        onCodesMatch: () => matched++,
        onCancelCode: () => cancelled++,
      ),
    );
    expect(find.text('482 913'), findsOneWidget);
    expect(find.text("Pair with Xavier's MacBook Pro"), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Codes match'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    expect((matched, cancelled), (1, 1));
  });

  Widget idle({
    Duration? remaining,
    List<DiscoveredMac> found = const [],
    void Function(String, int)? onConnect,
    VoidCallback? onOpen,
  }) => PairingScreen(
    windowRemaining: remaining,
    discovered: found,
    code: null,
    onOpenPairing: onOpen ?? () {},
    onClosePairing: () {},
    onPairWith: (_) {},
    onConnectAddress: onConnect ?? (_, _) {},
    onCodesMatch: () {},
    onCancelCode: () {},
  );

  testWidgets('closed window offers Open pairing with the 5:00 length', (
    tester,
  ) async {
    var opened = 0;
    await pumpUi(tester, idle(onOpen: () => opened++));
    expect(find.textContaining('5:00'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Open pairing'));
    expect(opened, 1);
  });

  testWidgets('open window shows the countdown', (tester) async {
    await pumpUi(
      tester,
      idle(remaining: const Duration(minutes: 4, seconds: 5)),
    );
    expect(find.text('Pairing open · 4:05'), findsOneWidget);
  });

  testWidgets('discovered Macs are listed', (tester) async {
    await pumpUi(
      tester,
      idle(
        found: const [
          DiscoveredMac(
            id: 'a',
            personName: 'Xavier',
            deviceName: "Xavier's MacBook Pro",
            address: '192.168.1.20:8790',
          ),
        ],
      ),
    );
    expect(find.text('Xavier'), findsOneWidget);
    expect(find.textContaining("Xavier's MacBook Pro"), findsOneWidget);
  });

  testWidgets('address field shows its error under the field', (tester) async {
    final connects = <(String, int)>[];
    await pumpUi(tester, idle(onConnect: (h, p) => connects.add((h, p))));
    final field = find.byType(TextField);
    await tester.enterText(field, 'not an address');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pump();
    expect(
      find.text('Enter an address like 192.168.1.20:8790'),
      findsOneWidget,
    );
    expect(connects, isEmpty);
    final errorY = tester
        .getTopLeft(find.text('Enter an address like 192.168.1.20:8790'))
        .dy;
    expect(errorY, greaterThan(tester.getBottomLeft(field).dy - 24));

    await tester.enterText(field, '192.168.1.20:8790');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pump();
    expect(connects, [('192.168.1.20', 8790)]);
  });
}
