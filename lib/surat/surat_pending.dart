import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/relay_database.dart';
import '../identity/local_identity.dart';
import 'surat_change.dart';
import 'surat_event.dart';

/// A decision waiting for me: an invite to a surat (`invite`) or a newcomer
/// someone else invited (`newcomer`). `id` is `'$kind:$suratId:$deviceId'`,
/// where [deviceId] is me for an invite.
typedef PendingItem = ({
  String id,
  String kind,
  String suratId,
  String suratName,
  String deviceId,
  String personName,
  String deviceName,
  String? inviterName,
  bool declined,
});

/// Lists my pending decisions from the projection and publishes my answers.
/// An answer is the person's own decision: it goes out as an event at once,
/// never as an awaiting_approval draft.
class SuratPending {
  SuratPending({
    required this.db,
    required this.me,
    required this.publish,
    required int Function() nowMs,
  }) : _now = nowMs;

  final RelayDatabase db;
  final LocalIdentity me;

  /// The service's publish path (stamp, store, seal, rebuild).
  final Future<void> Function(Message row) publish;
  final int Function() _now;

  Future<List<PendingItem>> pending() async {
    final surats = await (db.select(
      db.channels,
    )..where((c) => c.kind.equals('surat') & c.closedAt.isNull())).get();
    final out = <PendingItem>[];
    for (final c in surats) {
      final rows = await _rows(c.id);
      final mine = rows[me.deviceId];
      if (mine == null) continue;
      final name = c.name ?? '';
      String? inviterName(ChannelMember m) =>
          rows[m.inviterDeviceId]?.personName;
      if (mine.state == 'invited') {
        out.add((
          id: 'invite:${c.id}:${me.deviceId}',
          kind: 'invite',
          suratId: c.id,
          suratName: name,
          deviceId: me.deviceId,
          personName: me.personName,
          deviceName: me.deviceName,
          inviterName: inviterName(mine),
          declined: false,
        ));
      } else if (mine.state == 'member') {
        for (final m in rows.values) {
          if (m.deviceId == me.deviceId || !_seated(m)) continue;
          if (m.inviterDeviceId == me.deviceId) continue;
          if (m.myApproval == 'approved') continue;
          out.add((
            id: 'newcomer:${c.id}:${m.deviceId}',
            kind: 'newcomer',
            suratId: c.id,
            suratName: name,
            deviceId: m.deviceId,
            personName: m.personName ?? '',
            deviceName: m.deviceName ?? '',
            inviterName: inviterName(m),
            declined: m.myApproval == 'declined',
          ));
        }
      }
    }
    out.sort((a, b) {
      final byName = a.suratName.compareTo(b.suratName);
      if (byName != 0) return byName;
      final byPerson = a.personName.compareTo(b.personName);
      return byPerson != 0 ? byPerson : a.deviceId.compareTo(b.deviceId);
    });
    return out;
  }

  /// Answers [pendingId]. Throws [UnknownPending], [NotAllowed] (the surat
  /// ended) or [AlreadyApproved] (declining someone I approved). Repeating an
  /// answer I already gave publishes nothing.
  Future<void> decide(String pendingId, {required bool approve}) async {
    final parts = pendingId.split(':');
    if (parts.length != 3) throw UnknownPending(pendingId);
    final (kind, suratId, deviceId) = (parts[0], parts[1], parts[2]);
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(suratId))).getSingleOrNull();
    if (channel == null || channel.kind != 'surat') {
      throw UnknownPending(pendingId);
    }
    final rows = await _rows(suratId);
    final mine = rows[me.deviceId];
    final SuratEvent event;
    if (kind == 'invite' && deviceId == me.deviceId) {
      if (mine?.state != 'invited') throw UnknownPending(pendingId);
      event = approve ? const AcceptEvent() : const DeclineInviteEvent();
    } else if (kind == 'newcomer') {
      final them = rows[deviceId];
      if (mine?.state != 'member' ||
          them == null ||
          deviceId == me.deviceId ||
          !_seated(them) ||
          them.inviterDeviceId == me.deviceId) {
        throw UnknownPending(pendingId);
      }
      if (channel.closedAt == null) {
        final answer = them.myApproval;
        if (!approve && answer == 'approved') throw const AlreadyApproved();
        if (answer == (approve ? 'approved' : 'declined')) return;
      }
      event = approve ? ApproveEvent(deviceId) : DeclineEvent(deviceId);
    } else {
      throw UnknownPending(pendingId);
    }
    if (channel.closedAt != null) throw const NotAllowed('the surat ended');
    await db.transaction(() async {
      final id = const Uuid().v4();
      final now = _now();
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: id,
              channelId: suratId,
              kind: 'event',
              fromDeviceId: me.deviceId,
              sentAt: now,
              body: Value(jsonEncode(event.toJson())),
              direction: 'out',
              status: 'queued',
              createdAt: now,
            ),
          );
      await publish(
        await (db.select(
          db.messages,
        )..where((m) => m.id.equals(id))).getSingle(),
      );
    });
  }

  bool _seated(ChannelMember m) => m.state == 'member' || m.state == 'invited';

  Future<Map<String, ChannelMember>> _rows(String suratId) async => {
    for (final m in await (db.select(
      db.channelMembers,
    )..where((m) => m.channelId.equals(suratId))).get())
      m.deviceId: m,
  };
}
