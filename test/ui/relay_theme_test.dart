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

  for (final (name, theme) in [
    ('light', RelayTheme.light()),
    ('dark', RelayTheme.dark()),
  ]) {
    test('$name: person colours read as text and carry the disc initial', () {
      final c = theme.extension<RelayColors>()!;
      final bg = theme.colorScheme.surface;
      expect(c.people, hasLength(greaterThanOrEqualTo(5)));
      for (final p in [...c.people, c.primaryText]) {
        expect(_contrast(p, bg), greaterThanOrEqualTo(4.5), reason: '$p on bg');
        expect(
          _contrast(p, c.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$p on memo',
        );
        expect(
          _contrast(c.surface, p),
          greaterThanOrEqualTo(4.5),
          reason: 'initial on $p',
        );
      }
    });
  }

  test('a person keeps one colour; my own memos use primaryText', () {
    final c = RelayTheme.light().extension<RelayColors>()!;
    expect(c.person('abc'), c.person('abc'));
    expect(c.person('abc', mine: true), c.primaryText);
    final picks = {for (var i = 0; i < 40; i++) c.person('device-$i')};
    expect(
      picks.length,
      c.people.length,
      reason: 'ids spread over the palette',
    );
  });
}
