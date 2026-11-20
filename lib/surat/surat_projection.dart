import 'dart:convert';

import 'package:drift/drift.dart';

import '../crypto/identity_keys.dart';
import '../crypto/vouch.dart';
import '../data/relay_database.dart';
import '../identity/local_identity.dart';
import '../messaging/message_service.dart' show UnknownChannel;
import 'surat_change.dart';
import 'surat_event.dart';
import 'surat_state.dart';

/// The joinedHlc a row holds before it has a real one (the column is NOT
/// NULL): my row between drafting and publishing a create.
const zeroHlc = '0000000000000-00000';

/// A surat's stored event log, sorted, and the state it replays to.
/// [snapshotHlc] is the hlc of the invite whose snapshot the replay started
/// from, when there was one.
typedef SuratLog = ({
  Channel channel,
  List<LoggedEvent> log,
  SuratState state,
  String? snapshotHlc,
});

/// Reads a surat's event log, replays it, writes the result into
/// `ChannelMembers` and `Channels`, and builds the snapshot a newcomer needs.
class SuratProjection {
  SuratProjection({
    required this.db,
    required this.me,
    required this.keys,
    required int Function() nowMs,
    this.myPort,
  }) : _now = nowMs;

  final RelayDatabase db;
  final LocalIdentity me;
  final IdentityKeys keys;

  /// This Mac's peer port, put in my card for a newcomer.
  final int Function()? myPort;
  final int Function() _now;

  /// Writes the replay of [suratId] into the tables and returns it with what
  /// changed since the previous projection. Writes nothing while the log has
  /// no create or snapshot yet. Run it inside a transaction.
  Future<({SuratState state, List<SuratChange> changes})> project(
    String suratId,
  ) async {
    final loaded = await load(suratId);
    final state = loaded.state;
    if (state.members.isEmpty) {
      return (state: state, changes: const <SuratChange>[]); // nothing yet
    }
    final prev = {
      for (final m in await (db.select(
        db.channelMembers,
      )..where((m) => m.channelId.equals(suratId))).get())
        m.deviceId: m,
    };
    final peers = {
      for (final p in await db.select(db.peers).get()) p.deviceId: p,
    };
    final cards = _eventCards(loaded.log);
    final seatedAt = <String, String>{
      for (final e in loaded.log)
        ...switch (e.event) {
          CreateEvent(:final invitees) => {
            for (final c in invitees) c.deviceId: e.hlc,
          },
          InviteEvent(:final newcomer) => {newcomer.deviceId: e.hlc},
          _ => const <String, String>{},
        },
    };
    final mine = me.deviceId;
    for (final MapEntry(key: id, value: m) in state.members.entries) {
      final peer = peers[id], card = cards[id];
      await db
          .into(db.channelMembers)
          .insertOnConflictUpdate(
            ChannelMembersCompanion.insert(
              channelId: suratId,
              deviceId: id,
              joinedHlc:
                  m.joinedHlc ?? seatedAt[id] ?? loaded.snapshotHlc ?? zeroHlc,
              leftHlc: Value(m.leftHlc),
              state: Value(m.state.name),
              inviterDeviceId: Value(m.inviter),
              myApproval: Value(state.approvals[mine]?[id]),
              theirApproval: Value(state.approvals[id]?[mine]),
              personName: Value(
                id == mine
                    ? me.personName
                    : peer?.personName ?? card?.personName,
              ),
              deviceName: Value(
                id == mine
                    ? me.deviceName
                    : peer?.deviceName ?? card?.deviceName,
              ),
            ),
          );
    }
    await (db.delete(db.channelMembers)..where(
          (m) =>
              m.channelId.equals(suratId) &
              m.deviceId.isNotIn(state.members.keys),
        ))
        .go();
    final channel = loaded.channel;
    await (db.update(db.channels)..where((c) => c.id.equals(suratId))).write(
      ChannelsCompanion(
        name: state.name.isEmpty ? const Value.absent() : Value(state.name),
        closedAt: state.ended && channel.closedAt == null
            ? Value(_now())
            : const Value.absent(),
      ),
    );
    return (state: state, changes: _diff(suratId, channel, prev, state));
  }

  List<SuratChange> _diff(
    String suratId,
    Channel channel,
    Map<String, ChannelMember> prev,
    SuratState s,
  ) {
    final mine = me.deviceId;
    final out = <SuratChange>[];
    bool seated(String? state) => state == 'member' || state == 'invited';
    final self = s.members[mine];
    if (self?.state == MemberState.invited &&
        prev[mine]?.state != 'invited' &&
        self!.inviter != null) {
      out.add(Invited(suratId, self.inviter!));
    }
    if (channel.name != null && s.name.isNotEmpty && channel.name != s.name) {
      out.add(Renamed(suratId, s.name));
    }
    for (final id in s.members.keys.toList()..sort()) {
      if (id == mine) continue;
      final m = s.members[id]!, was = prev[id];
      final inviter = m.inviter;
      if (seated(m.state.name) &&
          !seated(was?.state) &&
          self?.state == MemberState.member &&
          inviter != null &&
          inviter != mine &&
          s.approvals[mine]?[id] == null) {
        out.add(NewcomerToApprove(suratId, id, inviter));
      }
      if (m.state == MemberState.left && was?.state == 'member') {
        out.add(MemberLeft(suratId, id));
      }
      final wasMutual =
          was?.myApproval == 'approved' && was?.theirApproval == 'approved';
      if (!wasMutual && s.mutual(mine, id)) out.add(BecameMutual(suratId, id));
    }
    if (s.ended && channel.closedAt == null) out.add(Ended(suratId));
    return out;
  }

  /// The stored log, sorted, and the state it replays to. Starts from the
  /// latest snapshot sent to me with an invite, else from the creator.
  Future<SuratLog> load(String suratId) async {
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(suratId))).getSingleOrNull();
    if (channel == null || channel.kind != 'surat') {
      throw const UnknownChannel();
    }
    final rows =
        await (db.select(db.messages)..where(
              (m) =>
                  m.channelId.equals(suratId) &
                  m.kind.equals('event') &
                  m.hlc.isNotNull(),
            ))
            .get();
    final log =
        <LoggedEvent>[
          for (final r in rows)
            if (decode(r.body) case final e?)
              (hlc: r.hlc!, from: r.fromDeviceId, event: e),
        ]..sort((a, b) {
          final byHlc = a.hlc.compareTo(b.hlc);
          return byHlc != 0 ? byHlc : a.from.compareTo(b.from);
        });
    ({String hlc, SuratSnapshot snapshot})? start;
    for (final e in log) {
      if (e.event case InviteEvent(:final newcomer, :final snapshot?)
          when newcomer.deviceId == me.deviceId) {
        start = (hlc: e.hlc, snapshot: snapshot);
      }
    }
    return (
      channel: channel,
      log: log,
      state: SuratState.replay(
        suratId: suratId,
        snapshot: start?.snapshot,
        creatorDeviceId: channel.creatorDeviceId,
        events: log,
      ),
      snapshotHlc: start?.hlc,
    );
  }

  /// The surat as a newcomer needs it, before the invite: every member and
  /// invitee's card (mine with my peer port) and the approvals involving me.
  Future<SuratSnapshot> snapshot(String suratId) async {
    final loaded = await load(suratId);
    final s = loaded.state;
    final cards = _eventCards(loaded.log);
    for (final p in await db.select(db.peers).get()) {
      cards[p.deviceId] = cardOf(p);
    }
    cards[me.deviceId] = MemberCard(
      deviceId: me.deviceId,
      personName: me.personName,
      deviceName: me.deviceName,
      signPub: keys.signPub,
      boxPub: keys.boxPub,
      certFingerprint: me.certFingerprint,
      port: myPort?.call(),
    );
    List<MemberCard> inState(MemberState state) => [
      for (final id in s.members.keys.toList()..sort())
        if (s.members[id]!.state == state && cards[id] != null)
          _dated(cards[id]!, s.members[id]!.joinedHlc),
    ];
    final mine = me.deviceId;
    final approvals = <String, Map<String, String>>{};
    for (final a in s.approvals.entries) {
      for (final b in a.value.entries) {
        if (a.key == mine || b.key == mine) {
          (approvals[a.key] ??= {})[b.key] = b.value;
        }
      }
    }
    return SuratSnapshot(
      name: s.name,
      creatorDeviceId: loaded.channel.creatorDeviceId ?? mine,
      members: inState(MemberState.member),
      invited: inState(MemberState.invited),
      approvals: approvals,
    );
  }

  /// Cards carried in the log, later ones winning.
  Map<String, MemberCard> _eventCards(List<LoggedEvent> log) => {
    for (final e in log)
      ...switch (e.event) {
        CreateEvent(:final invitees) => {
          for (final c in invitees) c.deviceId: c,
        },
        InviteEvent(:final newcomer, :final snapshot) => {
          for (final c in [...?snapshot?.members, ...?snapshot?.invited])
            c.deviceId: c,
          newcomer.deviceId: newcomer,
        },
        _ => const <String, MemberCard>{},
      },
  };

  MemberCard _dated(MemberCard c, String? joinedHlc) => MemberCard(
    deviceId: c.deviceId,
    personName: c.personName,
    deviceName: c.deviceName,
    signPub: c.signPub,
    boxPub: c.boxPub,
    certFingerprint: c.certFingerprint,
    address: c.address,
    port: c.port,
    joinedHlc: joinedHlc,
  );

  static MemberCard cardOf(Peer p) => MemberCard(
    deviceId: p.deviceId,
    personName: p.personName,
    deviceName: p.deviceName,
    signPub: p.signPub,
    boxPub: p.boxPub,
    certFingerprint: p.certFingerprint,
    address: p.lastAddress,
    port: p.lastPort,
  );

  static SuratEvent? decode(String? body) {
    if (body == null) return null;
    try {
      return SuratEvent.fromJson(jsonDecode(body) as Map);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
