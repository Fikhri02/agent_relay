import 'package:agent_relay/ui/surat/new_surat_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

const List<PeerChoice> people = [
  (deviceId: 'd1', personName: 'Xavier', deviceName: "Xavier's MacBook Pro"),
  (deviceId: 'd2', personName: 'Shaw Ping', deviceName: "Shaw Ping's iMac"),
  (deviceId: 'd3', personName: 'Tommy', deviceName: 'Tommy MBA'),
  (deviceId: 'd4', personName: 'Aina', deviceName: 'Aina Mac'),
  (deviceId: 'd5', personName: 'Budi', deviceName: 'Budi Mac'),
];

void main() {
  FilledButton create(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));
  bool? picked(WidgetTester tester, String id) =>
      tester.widget<Checkbox>(find.byKey(ValueKey('pick-$id'))).value;
  bool enabled(WidgetTester tester, String id) =>
      tester.widget<Checkbox>(find.byKey(ValueKey('pick-$id'))).onChanged !=
      null;

  testWidgets('new surat dialog caps selection at 4 and needs a name', (
    tester,
  ) async {
    (String, List<String>)? made;
    await pumpUi(
      tester,
      NewSuratDialog(
        people: people,
        onCreate: (name, ids) async => made = (name, ids),
      ),
    );
    expect(find.text('New surat'), findsOneWidget);
    expect(find.text('Up to 4 people'), findsOneWidget);
    expect(create(tester).onPressed, isNull, reason: 'nothing picked');

    for (final id in ['d1', 'd2', 'd3', 'd4']) {
      await tester.tap(find.byKey(ValueKey('pick-$id')));
      await tester.pump();
    }
    expect(find.text('4 of 4 picked'), findsOneWidget);
    expect(enabled(tester, 'd5'), isFalse, reason: 'the fifth is capped');
    await tester.tap(find.byKey(const ValueKey('pick-d5')));
    await tester.pump();
    expect(picked(tester, 'd5'), isFalse);
    expect(create(tester).onPressed, isNull, reason: 'no name yet');

    await tester.enterText(find.byKey(const ValueKey('surat-name')), '   ');
    await tester.pump();
    expect(create(tester).onPressed, isNull, reason: 'blank name');

    await tester.enterText(
      find.byKey(const ValueKey('surat-name')),
      'tiered-discount staging',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(made?.$1, 'tiered-discount staging');
    expect(made?.$2, ['d1', 'd2', 'd3', 'd4']);
  });

  testWidgets('unpicking frees a seat again', (tester) async {
    await pumpUi(
      tester,
      NewSuratDialog(people: people, onCreate: (_, _) async {}),
    );
    for (final id in ['d1', 'd2', 'd3', 'd4']) {
      await tester.tap(find.byKey(ValueKey('pick-$id')));
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pick-d2')));
    await tester.pump();
    expect(enabled(tester, 'd5'), isTrue);
    expect(find.text('3 of 4 picked'), findsOneWidget);
  });

  testWidgets('shows each person with their device', (tester) async {
    await pumpUi(
      tester,
      NewSuratDialog(people: people, onCreate: (_, _) async {}),
    );
    expect(find.text('Xavier'), findsOneWidget);
    expect(find.text("Xavier's MacBook Pro"), findsOneWidget);
  });

  testWidgets('with no paired people it says to pair first', (tester) async {
    await pumpUi(
      tester,
      NewSuratDialog(people: const [], onCreate: (_, _) async {}),
    );
    expect(
      find.text('Pair a teammate first — a surat is made from paired people'),
      findsOneWidget,
    );
  });

  testWidgets('a refused create shows why and keeps the dialog open', (
    tester,
  ) async {
    await pumpUi(
      tester,
      NewSuratDialog(
        people: people,
        onCreate: (_, _) async => throw StateError('boom'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-d1')));
    await tester.enterText(find.byKey(const ValueKey('surat-name')), 'x');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't create the surat: Bad state: boom"), findsOne);
    expect(find.text('New surat'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('renders in ${b.name} mode', (tester) async {
      await pumpUi(
        tester,
        NewSuratDialog(people: people, onCreate: (_, _) async {}),
        brightness: b,
      );
      final ctx = tester.element(find.text('New surat'));
      expect(Theme.of(ctx).brightness, b);
      expect(tester.takeException(), isNull);
    });
  }
}
