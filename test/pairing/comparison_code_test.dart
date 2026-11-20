import 'package:agent_relay/pairing/comparison_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = 'a' * 64, b = 'b' * 64, c = 'c' * 64;
  final ka = List.filled(64, 1), kb = List.filled(64, 2);

  test('code is symmetric and 6 digits', () {
    final x = comparisonCode(fpA: a, fpB: b, keysA: ka, keysB: kb);
    expect(x, comparisonCode(fpA: b, fpB: a, keysA: kb, keysB: ka));
    expect(x, matches(RegExp(r'^\d{6}$')));
  });

  test('a different fingerprint on one side gives a different code', () {
    expect(
      comparisonCode(fpA: a, fpB: b, keysA: ka, keysB: kb),
      isNot(comparisonCode(fpA: c, fpB: b, keysA: ka, keysB: kb)),
    );
  });

  test('private channel id is the same from both sides', () {
    expect(privateChannelId('x1', 'y2'), privateChannelId('y2', 'x1'));
    expect(privateChannelId('x1', 'y2'), matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}
