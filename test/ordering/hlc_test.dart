import 'package:agent_relay/ordering/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plan', () {
    test('tick is monotonic even when wall clock goes back', () {
      var now = 1000;
      final c = HlcClock(nowMs: () => now);
      final a = c.tick();
      now = 900;
      final b = c.tick();
      expect(b.compareTo(a), greaterThan(0));
    });

    test('a stamp after observing a remote one sorts after it, despite a slow clock', () {
      final c = HlcClock(nowMs: () => 1000);
      c.observe(Hlc(5000, 3));
      final mine = c.tick();
      expect(mine.compareTo(Hlc(5000, 3)), greaterThan(0));
    });

    test('encode is fixed width and string-sortable', () {
      expect(Hlc(1700000000000, 2).encode(), '1700000000000-00002');
      expect(Hlc.decode('1700000000000-00002'), Hlc(1700000000000, 2));
    });
  });

  group('tick', () {
    test('uses the wall clock with counter 0 when the wall clock is ahead', () {
      var now = 1000;
      final c = HlcClock(nowMs: () => now);
      expect(c.tick(), Hlc(1000, 0));
      now = 2000;
      expect(c.tick(), Hlc(2000, 0));
    });

    test('increments the counter when the wall time is equal', () {
      final c = HlcClock(nowMs: () => 1000);
      expect(c.tick(), Hlc(1000, 0));
      expect(c.tick(), Hlc(1000, 1));
      expect(c.tick(), Hlc(1000, 2));
    });

    test(
      'keeps the last wall time and bumps the counter when the clock goes back',
      () {
        var now = 1000;
        final c = HlcClock(nowMs: () => now);
        c.tick();
        now = 900;
        expect(c.tick(), Hlc(1000, 1));
      },
    );

    test('updates last', () {
      final c = HlcClock(nowMs: () => 1000);
      final a = c.tick();
      expect(c.last, a);
    });

    test('resumes after a restored last stamp', () {
      final c = HlcClock(nowMs: () => 1000, last: Hlc(5000, 7));
      expect(c.last, Hlc(5000, 7));
      expect(c.tick(), Hlc(5000, 8));
    });

    test('starts from zero when no last stamp is given', () {
      final c = HlcClock(nowMs: () => 1000);
      expect(c.last, Hlc(0, 0));
    });
  });

  group('observe', () {
    test('remote ahead: takes remote wall time and remote counter + 1', () {
      final c = HlcClock(nowMs: () => 1000);
      expect(c.observe(Hlc(5000, 3)), Hlc(5000, 4));
      expect(c.last, Hlc(5000, 4));
    });

    test('local ahead: keeps local wall time and bumps local counter', () {
      final c = HlcClock(nowMs: () => 1000, last: Hlc(9000, 2));
      expect(c.observe(Hlc(5000, 30)), Hlc(9000, 3));
    });

    test('equal wall times: max of both counters + 1', () {
      final c = HlcClock(nowMs: () => 1000, last: Hlc(5000, 2));
      expect(c.observe(Hlc(5000, 9)), Hlc(5000, 10));
      final d = HlcClock(nowMs: () => 1000, last: Hlc(5000, 9));
      expect(d.observe(Hlc(5000, 2)), Hlc(5000, 10));
    });

    test('wall clock ahead of both: wall time with counter 0', () {
      final c = HlcClock(nowMs: () => 9000, last: Hlc(5000, 2));
      expect(c.observe(Hlc(6000, 4)), Hlc(9000, 0));
    });

    test('result sorts after both the remote and the previous local stamp', () {
      final c = HlcClock(nowMs: () => 1000);
      final before = c.tick();
      final remote = Hlc(1000, 5);
      final after = c.observe(remote);
      expect(after.compareTo(remote), greaterThan(0));
      expect(after.compareTo(before), greaterThan(0));
    });
  });

  group('Hlc', () {
    test('compares by wall time, then counter', () {
      expect(Hlc(1, 9).compareTo(Hlc(2, 0)), lessThan(0));
      expect(Hlc(2, 0).compareTo(Hlc(2, 1)), lessThan(0));
      expect(Hlc(2, 1).compareTo(Hlc(2, 1)), 0);
      expect(Hlc(3, 0).compareTo(Hlc(2, 99)), greaterThan(0));
    });

    test('string order matches clock order', () {
      final stamps = [
        Hlc(1700000000000, 2),
        Hlc(999, 0),
        Hlc(1700000000000, 10),
        Hlc(1699999999999, 99999),
        Hlc(0, 0),
        Hlc(9999999999999, 0),
      ];
      final byClock = [...stamps]..sort();
      final byString = stamps.map((h) => h.encode()).toList()..sort();
      expect(byString, byClock.map((h) => h.encode()).toList());
    });

    test('encode pads small values', () {
      expect(Hlc(0, 0).encode(), '0000000000000-00000');
      expect(Hlc(42, 7).encode(), '0000000000042-00007');
    });

    test('encode/decode round trip', () {
      for (final h in [Hlc(0, 0), Hlc(1700000000000, 99999), Hlc(123, 45)]) {
        expect(Hlc.decode(h.encode()), h);
      }
    });

    test('== and hashCode are by value', () {
      expect(Hlc(5, 6), Hlc(5, 6));
      expect(Hlc(5, 6).hashCode, Hlc(5, 6).hashCode);
      expect(Hlc(5, 6) == Hlc(5, 7), isFalse);
      expect(Hlc(5, 6) == Hlc(6, 6), isFalse);
    });

    test('rejects values that do not fit the fixed-width encoding', () {
      expect(() => Hlc(-1, 0), throwsRangeError);
      expect(() => Hlc(10000000000000, 0), throwsRangeError);
      expect(() => Hlc(0, -1), throwsRangeError);
      expect(() => Hlc(0, 100000), throwsRangeError);
    });

    test('decode rejects malformed input', () {
      for (final s in [
        '',
        '1700000000000',
        '1700000000000-',
        '1700000000000-2',
        '170000000000-00002',
        '17000000000000-00002',
        '1700000000000-000002',
        '1700000000000_00002',
        '1700000000000-0000a',
        ' 1700000000000-00002',
        '1700000000000-00002 ',
        '-700000000000-00002',
        '1700000000000--0002',
        '1700000000000-00002-00001',
      ]) {
        expect(() => Hlc.decode(s), throwsFormatException, reason: s);
      }
    });
  });
}
