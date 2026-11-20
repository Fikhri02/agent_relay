import '../crypto/vouch.dart';

/// What the newcomer needs to see the surat as it stands. `approvals[a][b]` is
/// a's decision about b; only decisions involving the inviter travel.
class SuratSnapshot {
  const SuratSnapshot({
    required this.name,
    required this.creatorDeviceId,
    required this.members,
    required this.invited,
    required this.approvals,
  });

  final String name;
  final String creatorDeviceId;
  final List<MemberCard> members;
  final List<MemberCard> invited;
  final Map<String, Map<String, String>> approvals;

  Map<String, Object?> toJson() => {
    'name': name,
    'creatorDeviceId': creatorDeviceId,
    'members': [for (final m in members) m.toJson()],
    'invited': [for (final m in invited) m.toJson()],
    'approvals': approvals,
  };

  static SuratSnapshot fromJson(Map json) => _guard(
    () => SuratSnapshot(
      name: json['name'] as String,
      creatorDeviceId: json['creatorDeviceId'] as String,
      members: _cards(json['members']),
      invited: _cards(json['invited']),
      approvals: {
        for (final a in (json['approvals'] as Map).entries)
          a.key as String: {
            for (final b in (a.value as Map).entries)
              b.key as String: b.value as String,
          },
      },
    ),
  );
}

List<MemberCard> _cards(Object? raw) => [
  for (final c in raw as List) MemberCard.fromJson(c as Map),
];

T _guard<T>(T Function() build) {
  try {
    return build();
  } on TypeError {
    throw const FormatException('bad surat event');
  }
}

/// One signed fact about a surat, carried in a sealed envelope.
sealed class SuratEvent {
  const SuratEvent();

  String get type;
  Map<String, Object?> toJson();

  /// Throws [FormatException] for an unknown type or a missing field.
  static SuratEvent fromJson(Map json) => _guard(() {
    switch (json['type']) {
      case 'create':
        return CreateEvent(
          name: json['name'] as String,
          invitees: _cards(json['invitees']),
          vouches: {
            for (final e in (json['vouches'] as Map).entries)
              e.key as String: e.value as String,
          },
        );
      case 'invite':
        final snap = json['snapshot'];
        return InviteEvent(
          newcomer: MemberCard.fromJson(json['newcomer'] as Map),
          vouch: json['vouch'] as String,
          snapshot: snap == null ? null : SuratSnapshot.fromJson(snap as Map),
        );
      case 'accept':
        return AcceptEvent();
      case 'decline_invite':
        return DeclineInviteEvent();
      case 'approve':
        return ApproveEvent(json['deviceId'] as String);
      case 'decline':
        return DeclineEvent(json['deviceId'] as String);
      case 'leave':
        return LeaveEvent();
      case 'rename':
        return RenameEvent(json['name'] as String);
      default:
        throw FormatException('unknown surat event type: ${json['type']}');
    }
  });
}

class CreateEvent extends SuratEvent {
  const CreateEvent({
    required this.name,
    required this.invitees,
    required this.vouches,
  });

  final String name;
  final List<MemberCard> invitees;
  final Map<String, String> vouches;

  @override
  String get type => 'create';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'name': name,
    'invitees': [for (final c in invitees) c.toJson()],
    'vouches': vouches,
  };
}

/// [snapshot] goes only in the newcomer's copy; members' copies carry null.
class InviteEvent extends SuratEvent {
  const InviteEvent({
    required this.newcomer,
    required this.vouch,
    required this.snapshot,
  });

  final MemberCard newcomer;
  final String vouch;
  final SuratSnapshot? snapshot;

  @override
  String get type => 'invite';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'newcomer': newcomer.toJson(),
    'vouch': vouch,
    'snapshot': snapshot?.toJson(),
  };
}

class AcceptEvent extends SuratEvent {
  const AcceptEvent();

  @override
  String get type => 'accept';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

class DeclineInviteEvent extends SuratEvent {
  const DeclineInviteEvent();

  @override
  String get type => 'decline_invite';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

class ApproveEvent extends SuratEvent {
  const ApproveEvent(this.deviceId);

  final String deviceId;

  @override
  String get type => 'approve';

  @override
  Map<String, Object?> toJson() => {'type': type, 'deviceId': deviceId};
}

class DeclineEvent extends SuratEvent {
  const DeclineEvent(this.deviceId);

  final String deviceId;

  @override
  String get type => 'decline';

  @override
  Map<String, Object?> toJson() => {'type': type, 'deviceId': deviceId};
}

class LeaveEvent extends SuratEvent {
  const LeaveEvent();

  @override
  String get type => 'leave';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

class RenameEvent extends SuratEvent {
  const RenameEvent(this.name);

  final String name;

  @override
  String get type => 'rename';

  @override
  Map<String, Object?> toJson() => {'type': type, 'name': name};
}
