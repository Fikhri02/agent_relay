// Adapted from gallery_bridge apps/macos/lib/core/pairing/pairing_window.dart
import 'dart:async';

import 'pairing_service.dart';

/// The 5-minute span in which this Mac accepts a new pairing.
class PairingWindow {
  PairingWindow({
    DateTime Function()? clock,
    this.length = const Duration(minutes: 5),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration length;
  DateTime? _closesAt;
  Timer? _timer;
  final _events = StreamController<PairingEvent>.broadcast();

  Stream<PairingEvent> get events => _events.stream;
  DateTime? get closesAt => _closesAt;
  bool get isOpen => _closesAt != null && _clock().isBefore(_closesAt!);

  void open() {
    _closesAt = _clock().add(length);
    _timer?.cancel();
    _timer = Timer(length, () {
      if (_closesAt != null) {
        _closesAt = null;
        _events.add(const PairingExpired());
      }
    });
    _events.add(PairingOpened(_closesAt!));
  }

  void close() {
    _timer?.cancel();
    _closesAt = null;
  }

  void dispose() {
    close();
    _events.close();
  }
}
