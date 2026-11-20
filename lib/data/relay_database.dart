import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

export 'tables.dart';

part 'relay_database.g.dart';

/// Who read a message: the person in the app, or their agent via the API.
/// Each keeps its own unread state — opening a message in the app does not
/// mark it read for the agent, and the agent reading it does not clear the
/// app's badge.
enum Reader { person, agent }

@DriftDatabase(tables: [Peers, Channels, ChannelMembers, Messages, Deliveries])
class RelayDatabase extends _$RelayDatabase {
  /// Tests pass `NativeDatabase.memory()`; the app uses [open].
  RelayDatabase(super.executor);

  /// The app's on-disk database, opened on a background isolate.
  static RelayDatabase open(File file) =>
      RelayDatabase(NativeDatabase.createInBackground(file));

  var _commitDepth = 0;
  final _afterCommit = <Future<void> Function()>{};

  /// A transaction whose [afterCommit] work runs once the OUTERMOST one
  /// started through here has committed (never inside it, never after a
  /// rollback). Nest freely: only the outermost level flushes.
  Future<T> committing<T>(Future<T> Function() body) async {
    _commitDepth++;
    final T out;
    try {
      out = await transaction(body);
    } catch (_) {
      if (_commitDepth == 1) _afterCommit.clear();
      rethrow;
    } finally {
      _commitDepth--;
    }
    if (_commitDepth == 0) await _runAfterCommit();
    return out;
  }

  /// Runs [work] now when no [committing] transaction is open, else once the
  /// outermost one commits. Registering the same function twice runs it once.
  Future<void> afterCommit(Future<void> Function() work) async {
    if (_commitDepth > 0) {
      _afterCommit.add(work);
      return;
    }
    await work();
  }

  Future<void> _runAfterCommit() async {
    while (_afterCommit.isNotEmpty) {
      final work = _afterCommit.first;
      _afterCommit.remove(work);
      await work();
    }
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(channelMembers, channelMembers.state);
        await m.addColumn(channelMembers, channelMembers.inviterDeviceId);
        await m.addColumn(channelMembers, channelMembers.myApproval);
        await m.addColumn(channelMembers, channelMembers.theirApproval);
        await m.addColumn(channelMembers, channelMembers.personName);
        await m.addColumn(channelMembers, channelMembers.deviceName);
        // Existing members all come from private channels, paired on both
        // sides, so each has approved the other.
        await customStatement(
          "UPDATE channel_members SET state = 'member', "
          "my_approval = 'approved', their_approval = 'approved'",
        );
      }
    },
  );

  /// Incoming, readable, and not yet read by [by]: `seenAt` for the person,
  /// `agentReadAt` for the agent. Locked messages and event rows never count
  /// as unread.
  Expression<bool> _unreadBy(Reader by) =>
      messages.direction.equals('in') &
      messages.kind.equals('event').not() &
      messages.status.equals('locked').not() &
      (by == Reader.agent
          ? messages.agentReadAt.isNull()
          : messages.seenAt.isNull());

  /// The channel timeline, ordered by `hlc` then `fromDeviceId`. Drafts
  /// (`hlc` null) are excluded. With [unreadBy], only messages that reader
  /// has not read yet.
  Future<List<Message>> channelMessages(String channelId, {Reader? unreadBy}) {
    final q = select(messages)
      ..where((m) => m.channelId.equals(channelId) & m.hlc.isNotNull())
      ..orderBy([
        (m) => OrderingTerm.asc(m.hlc),
        (m) => OrderingTerm.asc(m.fromDeviceId),
      ]);
    if (unreadBy != null) q.where((_) => _unreadBy(unreadBy));
    return q.get();
  }

  /// Per channel id, messages [by] has not read yet. Channels with none are
  /// absent.
  Future<Map<String, int>> unreadCounts({required Reader by}) async {
    final count = messages.id.count();
    final q = selectOnly(messages)
      ..addColumns([messages.channelId, count])
      ..where(messages.hlc.isNotNull() & _unreadBy(by))
      ..groupBy([messages.channelId]);
    return {
      for (final row in await q.get())
        row.read(messages.channelId)!: row.read(count)!,
    };
  }

  /// Per incoming sender in the channel: (max seq − min seq + 1) − count of
  /// distinct seqs, so counting starts at the sender's first stored message.
  /// Event rows are ignored. Only senders with at least one missing message
  /// are returned, ordered by device id.
  Future<List<({String fromDeviceId, int missing})>> gaps(
    String channelId,
  ) async {
    final missing =
        messages.seq.max() -
        messages.seq.min() +
        const Constant<int>(1) -
        messages.seq.count(distinct: true);
    final q = selectOnly(messages)
      ..addColumns([messages.fromDeviceId, missing])
      ..where(
        messages.channelId.equals(channelId) &
            messages.direction.equals('in') &
            messages.kind.equals('event').not() &
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

  /// Inserts [m], or fills an existing row with the same id when that row is
  /// still a `locked` placeholder of the same channel and sender (body, context, reply and status). A
  /// readable row is never overwritten. Returns true when it wrote.
  Future<bool> insertOrUnlock(MessagesCompanion m) async {
    if (await insertIncomingIfNew(m)) return true;
    final filled =
        await (update(messages)..where(
              (x) =>
                  x.id.equals(m.id.value) &
                  x.status.equals('locked') &
                  x.channelId.equals(m.channelId.value) &
                  x.fromDeviceId.equals(m.fromDeviceId.value) &
                  x.direction.equals('in'),
            ))
            .write(
              MessagesCompanion(
                body: m.body,
                contextJson: m.contextJson,
                replyTo: m.replyTo,
                status: m.status,
              ),
            );
    return filled > 0;
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
