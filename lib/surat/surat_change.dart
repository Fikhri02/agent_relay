import 'surat_state.dart';

/// Every seat (members plus invitees) of a surat is taken.
class TooManyMembers implements Exception {
  const TooManyMembers();
  @override
  String toString() => 'a surat holds at most $suratSeatCap members';
}

/// The change is not this device's to make (e.g. rename by a non-renamer).
class NotAllowed implements Exception {
  const NotAllowed(this.reason);
  final String reason;
  @override
  String toString() => 'not allowed: $reason';
}

/// The device to invite is not a paired peer of mine.
class UnknownPeer implements Exception {
  const UnknownPeer(this.deviceId);
  final String deviceId;
  @override
  String toString() => 'not a paired peer: $deviceId';
}

/// What a surat rebuild changed that the person should hear about.
sealed class SuratChange {
  const SuratChange(this.suratId);
  final String suratId;
}

/// I was invited.
class Invited extends SuratChange {
  const Invited(super.suratId, this.inviter);
  final String inviter;
}

/// Someone else invited [newcomer]; I'm a member and haven't decided yet.
class NewcomerToApprove extends SuratChange {
  const NewcomerToApprove(super.suratId, this.newcomer, this.inviter);
  final String newcomer;
  final String inviter;
}

class Renamed extends SuratChange {
  const Renamed(super.suratId, this.name);
  final String name;
}

class Ended extends SuratChange {
  const Ended(super.suratId);
}

class MemberLeft extends SuratChange {
  const MemberLeft(super.suratId, this.deviceId);
  final String deviceId;
}

/// [deviceId] and I now approve each other.
class BecameMutual extends SuratChange {
  const BecameMutual(super.suratId, this.deviceId);
  final String deviceId;
}
