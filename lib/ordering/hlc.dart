import 'dart:math' as math;

/// A hybrid logical clock stamp: wall-clock milliseconds plus a counter.
///
/// Stamps order by [wallMs], then [counter]. [encode] is fixed width
/// (13-digit wallMs, `-`, 5-digit counter) so string order equals clock order.
class Hlc implements Comparable<Hlc> {
  static const int maxWallMs = 9999999999999;
  static const int maxCounter = 99999;

  static final RegExp _format = RegExp(r'^(\d{13})-(\d{5})$');

  final int wallMs;
  final int counter;

  Hlc(this.wallMs, this.counter) {
    RangeError.checkValueInInterval(wallMs, 0, maxWallMs, 'wallMs');
    RangeError.checkValueInInterval(counter, 0, maxCounter, 'counter');
  }

  /// Parses a stamp produced by [encode]. Throws [FormatException] otherwise.
  static Hlc decode(String s) {
    final m = _format.firstMatch(s);
    if (m == null) {
      throw FormatException(
        'Not an HLC stamp (expected 13 digits-5 digits)',
        s,
      );
    }
    return Hlc(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  String encode() =>
      '${wallMs.toString().padLeft(13, '0')}-${counter.toString().padLeft(5, '0')}';

  @override
  int compareTo(Hlc other) {
    final byWall = wallMs.compareTo(other.wallMs);
    return byWall != 0 ? byWall : counter.compareTo(other.counter);
  }

  @override
  bool operator ==(Object other) =>
      other is Hlc && other.wallMs == wallMs && other.counter == counter;

  @override
  int get hashCode => Object.hash(wallMs, counter);

  @override
  String toString() => 'Hlc(${encode()})';
}

/// Issues [Hlc] stamps using the standard HLC send and receive rules.
class HlcClock {
  final int Function() _nowMs;
  Hlc _last;

  HlcClock({required this._nowMs, Hlc? last}) : _last = last ?? Hlc(0, 0);

  /// The highest stamp issued or observed so far.
  Hlc get last => _last;

  /// Stamps a local event (send rule).
  Hlc tick() {
    final wall = math.max(_last.wallMs, _nowMs());
    final counter = wall == _last.wallMs ? _last.counter + 1 : 0;
    return _last = Hlc(wall, counter);
  }

  /// Merges a received stamp (receive rule); the result sorts after both
  /// [remote] and every stamp this clock issued before.
  Hlc observe(Hlc remote) {
    final wall = math.max(math.max(_last.wallMs, remote.wallMs), _nowMs());
    final int counter;
    if (wall == _last.wallMs && wall == remote.wallMs) {
      counter = math.max(_last.counter, remote.counter) + 1;
    } else if (wall == _last.wallMs) {
      counter = _last.counter + 1;
    } else if (wall == remote.wallMs) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }
    return _last = Hlc(wall, counter);
  }
}
