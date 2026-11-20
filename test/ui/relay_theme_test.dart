import 'dart:math' as math;

import 'package:agent_relay/ui/theme/relay_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, theme) in [
    ('light', RelayTheme.light()),
    ('dark', RelayTheme.dark()),
  ]) {
    test('$name: every text/background pair is at least 4.5:1', () {
      final c = theme.extension<RelayColors>()!;
      final s = theme.colorScheme;
      void pass(String what, Color fg, Color bg) =>
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: what);
      final stage = {
        'bg': s.surface,
        'surface': c.surface,
        'raised': c.surfaceRaised,
      };
      final texts = {
        'text': s.onSurface,
        'muted': c.muted,
        'primaryText': c.primaryText,
        'success': c.success,
        'warning': c.warning,
        'danger': c.danger,
        'info': c.info,
      };
      for (final bg in stage.entries) {
        for (final fg in texts.entries) {
          pass('${fg.key} on ${bg.key}', fg.value, bg.value);
        }
      }
      pass('tabText on tab', c.tabText, c.tab);
      pass('tabCount on tab', c.tabCount, c.tab);
      pass('chromeText on chrome', c.chromeText, c.chrome);
      pass('onPrimary on primary', s.onPrimary, s.primary);
    });
  }

  test('corner scale: buttons and inputs 8, cards 12, dialogs 16', () {
    final t = RelayTheme.light();
    RoundedRectangleBorder shape(WidgetStateProperty<OutlinedBorder?>? p) =>
        p!.resolve({})! as RoundedRectangleBorder;
    expect(
      shape(t.filledButtonTheme.style!.shape).borderRadius,
      BorderRadius.circular(8),
    );
    expect(
      shape(t.outlinedButtonTheme.style!.shape).borderRadius,
      BorderRadius.circular(8),
    );
    expect(
      (t.inputDecorationTheme.border! as OutlineInputBorder).borderRadius,
      BorderRadius.circular(8),
    );
    expect(
      (t.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(12),
    );
    expect(
      (t.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
  });
}
