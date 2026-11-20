import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

export 'tables.dart';

part 'relay_database.g.dart';

@DriftDatabase(tables: [Peers, Channels, ChannelMembers, Messages, Deliveries])
class RelayDatabase extends _$RelayDatabase {
  /// Tests pass `NativeDatabase.memory()`; the app uses [open].
  RelayDatabase(super.executor);

  /// The app's on-disk database, opened on a background isolate.
  static RelayDatabase open(File file) =>
      RelayDatabase(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 1;

  /// The channel timeline, ordered by `hlc` then `fromDeviceId`. Drafts
  /// (`hlc` null) are excluded.
  Future<List<Message>> channelMessages(
    String channelId, {
    bool unreadOnly = false,
  }) {
    final q = select(messages)
      ..where((m) => m.channelId.equals(channelId) & m.hlc.isNotNull())
      ..orderBy([
        (m) => OrderingTerm.asc(m.hlc),
        (m) => OrderingTerm.asc(m.fromDeviceId),
      ]);
    if (unreadOnly) q.where((m) => m.status.equals('unread'));
    return q.get();
  }

  /// Unread message count per channel id. Channels with none are absent.
  Future<Map<String, int>> unreadCounts() async {
    final count = messages.id.count();
    final q = selectOnly(messages)
      ..addColumns([messages.channelId, count])
      ..where(messages.status.equals('unread'))
      ..groupBy([messages.channelId]);
    return {
      for (final row in await q.get())
        row.read(messages.channelId)!: row.read(count)!,
    };
  }

  /// Per incoming sender in the channel: max seq − count of distinct seqs.
  /// Only senders with at least one missing message are returned, ordered by
  /// device id.
  Future<List<({String fromDeviceId, int missing})>> gaps(
    String channelId,
  ) async {
    final missing = messages.seq.max() - messages.seq.count(distinct: true);
    final q = selectOnly(messages)
      ..addColumns([messages.fromDeviceId, missing])
      ..where(
        messages.channelId.equals(channelId) &
            messages.direction.equals('in') &
            messages.seq.isNotNull(),
      )
      ..groupBy([messages.fromDeviceId], having: missing.isBiggerThanValue(0))
      ..orderBy([OrderingTerm.asc(messages.fromDeviceId)]);
    return [
      for (final row in await q.get())
        (
          fromDeviceId: row.read(messages.fromDeviceId)!,
          missing: row.read(missing)!,
        ),
    ];
  }

  /// 1 + the highest seq this sender has used in the channel (1 when none).
  Future<int> nextSeq(String channelId, String deviceId) async {
    final maxSeq = messages.seq.max();
    final q = selectOnly(messages)
      ..addColumns([maxSeq])
      ..where(
        messages.channelId.equals(channelId) &
            messages.fromDeviceId.equals(deviceId),
      );
    final row = await q.getSingle();
    return (row.read(maxSeq) ?? 0) + 1;
  }

  /// Inserts a received message unless one with the same `id` exists.
  /// Returns false for a duplicate (idempotent receive).
  Future<bool> insertIncomingIfNew(MessagesCompanion m) async {
    final row = await into(messages)
        .insertReturningOrNull(m, onConflict: DoNothing());
    return row != null;
  }

  /// Queued deliveries whose `nextAttemptAt` is at or before [nowMs], oldest
  /// attempt first.
  Future<List<Delivery>> dueDeliveries(int nowMs) {
    return (select(deliveries)
          ..where(
            (d) =>
                d.status.equals('queued') &
                d.nextAttemptAt.isSmallerOrEqualValue(nowMs),
          )
          ..orderBy([
            (d) => OrderingTerm.asc(d.nextAttemptAt),
            (d) => OrderingTerm.asc(d.createdAt),
          ]))
        .get();
  }

  /// Outgoing messages awaiting approval, oldest first.
  Future<List<Message>> drafts() {
    return (select(messages)
          ..where(
            (m) =>
                m.direction.equals('out') &
                m.status.equals('awaiting_approval'),
          )
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .get();
  }
}
