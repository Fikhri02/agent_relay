import 'dart:convert';

import 'surat_event.dart';

/// One signed surat event as it sits in the log: when, from whom, what.
typedef LoggedEvent = ({String hlc, String from, SuratEvent event});

enum MemberState { invited, member, left, declined }

/// The most members plus invitees a surat holds at once.
const int suratSeatCap = 5;

/// Where one device stands in a surat.
class MemberEntry {
  const MemberEntry({
    required this.state,
    this.inviter,
    this.joinedHlc,
    this.leftHlc,
  });

  final MemberState state;

  /// Who invited this device; null for the creator and for invitees that
  /// arrived in a snapshot.
  final String? inviter;

  /// HLC of the accept (or of the create, for the creator).
  final String? joinedHlc;
  final String? leftHlc;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'inviter': inviter,
    'joinedHlc': joinedHlc,
    'leftHlc': leftHlc,
  };

  @override
  bool operator ==(Object other) =>
      other is MemberEntry &&
      other.state == state &&
      other.inviter == inviter &&
      other.joinedHlc == joinedHlc &&
      other.leftHlc == leftHlc;

  @override
  int get hashCode => Object.hash(state, inviter, joinedHlc, leftHlc);

  @override
  String toString() => 'MemberEntry(${toJson()})';
}

/// Who is in a surat, who approved whom, who may rename, and whether it ended,
/// as decided by replaying the surat's event log.
///
/// Pure: the same log in any order gives an equal state on every Mac.
/// Equality compares [toJson], which lists every map in key order.
class SuratState {
  SuratState._({
    required this.suratId,
    required this.name,
    required this.renamer,
    required this.ended,
    required Map<String, MemberEntry> members,
    required Map<String, Map<String, String>> approvals,
    required List<String> rejectedInvites,
  }) : members = Map.unmodifiable(members),
       approvals = Map.unmodifiable({
         for (final e in approvals.entries)
           e.key: Map<String, String>.unmodifiable(e.value),
       }),
       rejectedInvites = List.unmodifiable(rejectedInvites);

  final String suratId;
  final String name;

  /// Device id holding rename rights; null when no member is left to hold them.
  final String? renamer;
  final bool ended;
  final Map<String, MemberEntry> members;

  /// `approvals[a][b]` is a's decision about b: `approved` or `declined`.
  final Map<String, Map<String, String>> approvals;

  /// Devices whose invite arrived when every seat was taken, in log order.
  final List<String> rejectedInvites;

  bool mutual(String a, String b) =>
      approvals[a]?[b] == 'approved' && approvals[b]?[a] == 'approved';

  /// Folds [events] over the starting state. With a [snapshot] (the
  /// newcomer's case) the surat starts as the snapshot shows it; otherwise it
  /// starts empty and only a `create` from [creatorDeviceId] opens it.
  /// Events are sorted by (hlc, from), duplicates dropped, invalid ones
  /// ignored.
  static SuratState replay({
    required String suratId,
    SuratSnapshot? snapshot,
    String? creatorDeviceId,
    required List<LoggedEvent> events,
  }) {
    final fold = _Fold(creatorDeviceId);
    if (snapshot != null) fold.startFrom(snapshot);
    for (final e in _ordered(events)) {
      if (fold.ended) break;
      fold.apply(e.hlc, e.from, e.event);
    }
    return SuratState._(
      suratId: suratId,
      name: fold.name,
      renamer: fold.renamer,
      ended: fold.ended,
      members: fold.members,
      approvals: fold.approvals,
      rejectedInvites: fold.rejected,
    );
  }

  Map<String, Object?> toJson() => {
    'suratId': suratId,
    'name': name,
    'renamer': renamer,
    'ended': ended,
    'members': {
      for (final id in members.keys.toList()..sort()) id: members[id]!.toJson(),
    },
    'approvals': {
      for (final a in approvals.keys.toList()..sort())
        a: {
          for (final b in approvals[a]!.keys.toList()..sort())
            b: approvals[a]![b],
        },
    },
    'rejectedInvites': rejectedInvites,
  };

  @override
  bool operator ==(Object other) =>
      other is SuratState && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'SuratState(${jsonEncode(toJson())})';
}

/// Dedupes on (hlc, from, event JSON) and sorts by (hlc, from); the event
/// JSON breaks any remaining tie so the order is total.
List<LoggedEvent> _ordered(List<LoggedEvent> events) {
  final keyed = <String, ({String json, LoggedEvent e})>{};
  for (final e in events) {
    final json = jsonEncode(e.event.toJson());
    keyed['${e.hlc}|${e.from}|$json'] = (json: json, e: e);
  }
  final list = keyed.values.toList()
    ..sort((x, y) {
      final byHlc = x.e.hlc.compareTo(y.e.hlc);
      if (byHlc != 0) return byHlc;
      final byFrom = x.e.from.compareTo(y.e.from);
      return byFrom != 0 ? byFrom : x.json.compareTo(y.json);
    });
  return [for (final k in list) k.e];
}

class _Fold {
  _Fold(this.creatorDeviceId);

  final String? creatorDeviceId;
  bool started = false;
  String name = '';
  String? renamer;
  bool ended = false;

  /// Whether a valid accept, decline_invite or leave has been applied.
  bool settled = false;
  final members = <String, MemberEntry>{};
  final approvals = <String, Map<String, String>>{};
  final rejected = <String>[];

  bool isIn(String id, MemberState s) => members[id]?.state == s;
  bool isPresent(String id) =>
      isIn(id, MemberState.member) || isIn(id, MemberState.invited);
  int get seatsTaken => members.values
      .where(
        (m) => m.state == MemberState.member || m.state == MemberState.invited,
      )
      .length;

  void setApproval(String a, String b, String decision) =>
      (approvals[a] ??= {})[b] = decision;

  void startFrom(SuratSnapshot snapshot) {
    started = true;
    name = snapshot.name;
    for (final c in snapshot.members) {
      members[c.deviceId] = MemberEntry(
        state: MemberState.member,
        joinedHlc: c.joinedHlc,
      );
    }
    for (final c in snapshot.invited) {
      members.putIfAbsent(
        c.deviceId,
        () => const MemberEntry(state: MemberState.invited),
      );
    }
    for (final a in snapshot.approvals.entries) {
      approvals[a.key] = {...a.value};
    }
    renamer = isIn(snapshot.creatorDeviceId, MemberState.member)
        ? snapshot.creatorDeviceId
        : earliestMember();
  }

  /// The member with the lowest joinedHlc (tie → lowest device id); a missing
  /// joinedHlc sorts last.
  String? earliestMember() {
    final ids =
        [
          for (final e in members.entries)
            if (e.value.state == MemberState.member) e.key,
        ]..sort((x, y) {
          final hx = members[x]!.joinedHlc, hy = members[y]!.joinedHlc;
          if (hx != hy) {
            if (hx == null) return 1;
            if (hy == null) return -1;
            return hx.compareTo(hy);
          }
          return x.compareTo(y);
        });
    return ids.isEmpty ? null : ids.first;
  }

  void apply(String hlc, String from, SuratEvent event) {
    if (!started && event is! CreateEvent) return;
    switch (event) {
      case CreateEvent():
        if (!started && from == creatorDeviceId) create(hlc, from, event);
        return;
      case InviteEvent(:final newcomer):
        invite(from, newcomer.deviceId);
      case AcceptEvent():
        if (!isIn(from, MemberState.invited)) return;
        for (final id in members.keys) {
          if (id != from && isPresent(id)) setApproval(from, id, 'approved');
        }
        members[from] = MemberEntry(
          state: MemberState.member,
          inviter: members[from]!.inviter,
          joinedHlc: hlc,
        );
        settled = true;
      case DeclineInviteEvent():
        if (!isIn(from, MemberState.invited)) return;
        members[from] = MemberEntry(
          state: MemberState.declined,
          inviter: members[from]!.inviter,
        );
        settled = true;
      case ApproveEvent(:final deviceId):
        if (mayJudge(from, deviceId)) setApproval(from, deviceId, 'approved');
      case DeclineEvent(:final deviceId):
        if (mayJudge(from, deviceId) &&
            approvals[from]?[deviceId] != 'approved') {
          setApproval(from, deviceId, 'declined');
        }
      case LeaveEvent():
        if (!isIn(from, MemberState.member)) return;
        final was = members[from]!;
        members[from] = MemberEntry(
          state: MemberState.left,
          inviter: was.inviter,
          joinedHlc: was.joinedHlc,
          leftHlc: hlc,
        );
        if (renamer == from) renamer = earliestMember();
        settled = true;
      case RenameEvent(name: final newName):
        if (from == renamer && newName.isNotEmpty) name = newName;
    }
    ended =
        settled &&
        !members.values.any((m) => m.state == MemberState.invited) &&
        members.values.where((m) => m.state == MemberState.member).length == 1;
  }

  void create(String hlc, String creator, CreateEvent event) {
    started = true;
    name = event.name;
    renamer = creator;
    members[creator] = MemberEntry(state: MemberState.member, joinedHlc: hlc);
    for (final card in event.invitees) {
      invite(creator, card.deviceId);
    }
  }

  /// Seats [newcomer] as invited by [inviter], who approves it implicitly. A
  /// device returning after leaving or declining starts with no approvals.
  void invite(String inviter, String newcomer) {
    if (!isIn(inviter, MemberState.member) || isPresent(newcomer)) return;
    if (seatsTaken >= suratSeatCap) {
      rejected.add(newcomer);
      return;
    }
    approvals.remove(newcomer);
    for (final row in approvals.values) {
      row.remove(newcomer);
    }
    approvals.removeWhere((_, row) => row.isEmpty);
    members[newcomer] = MemberEntry(
      state: MemberState.invited,
      inviter: inviter,
    );
    setApproval(inviter, newcomer, 'approved');
  }

  bool mayJudge(String from, String about) =>
      from != about && isIn(from, MemberState.member) && isPresent(about);
}
