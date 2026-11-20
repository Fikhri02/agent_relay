import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../crypto/sealed_box.dart';
import '../data/relay_database.dart';
import '../ordering/hlc.dart';
import '../peer/trust.dart';
import 'envelope.dart';

export '../data/relay_database.dart' show Reader;

const maxBodyBytes = 32768;
const lateAfterMs = 120000;

/// Delivery-id prefix of a history re-share: `history:{messageId}:{to}`.
const historyPrefix = 'history:';

class BodyTooLarge implements Exception {
  const BodyTooLarge(this.bytes);
  final int bytes;
  @override
  String toString() => 'message is $bytes bytes; the limit is $maxBodyBytes';
}

class ChannelClosed implements Exception {
  const ChannelClosed();
}

class UnknownChannel implements Exception {
  const UnknownChannel();
}

/// A delivery into a private channel from a sender that is no longer paired.
/// Answered as 401: the sender reads it as "they unpaired". A delivery into
/// a closed channel is [ChannelClosed] instead (409).
class UntrustedSender implements Exception {
  const UntrustedSender();
}

class NotAMember implements Exception {
  const NotAMember();
}

/// An envelope this Mac refuses: malformed, or stamped too far ahead.
class BadEnvelope implements Exception {
  const BadEnvelope(this.reason);
  final String reason;
  @override
  String toString() => 'bad envelope: $reason';
}

/// How far ahead of this Mac's clock a peer's stamp may be.
const maxFutureSkewMs = 60000;
const draftLifetimeMs = 60 * 60 * 1000;

typedef ReceiveResult = ({bool duplicate, Message message});

typedef Receipt = ({
  String deviceId,
  String personName,
  int? deliveredAt,
  int? seenAt,
  int? agentReadAt,
});

/// Drafts, approval, sealing per recipient, receiving, reading and receipts.
/// Network delivery is the [DeliveryWorker]'s job; this only queues.
class MessageService {
  MessageService({
    required this.db,
    required this.myDeviceId,
    required this.myBox,
    required this.clock,
    int Function()? nowMs,
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final RelayDatabase db;
  final String myDeviceId;
  final SimpleKeyPair myBox;
  final HlcClock clock;
  final int Function() _now;
  final _incoming = StreamController<Message>.broadcast();
  final _changes = StreamController<Message>.broadcast();

  Stream<Message> get incoming => _incoming.stream;
  Stream<Message> get changes => _changes.stream;

  /// Publishes an approved `kind == 'event'` draft (the surat service). Set
  /// by the node; [approve] calls it instead of sealing a message.
  Future<void> Function(Message draft)? publishEvent;

  /// Told when an event draft is discarded or expires, so a surat that was
  /// never created can be removed.
  Future<void> Function(Message draft)? dropEvent;

  /// Announces a row written elsewhere (an event draft) on [changes].
  void announce(Message m) => _changes.add(m);

  /// A current member: joined, not left, and (for a message) in a surat
  /// whose create has been published. An event draft passes before that:
  /// the create itself is the event that publishes it.
  static bool _current(ChannelMember? mine, {bool event = false}) =>
      mine != null &&
      mine.state == 'member' &&
      mine.leftHlc == null &&
      (event || mine.joinedHlc != unpublishedHlc);

  Future<Message> _get(String id) =>
      (db.select(db.messages)..where((m) => m.id.equals(id))).getSingle();

  Future<Message> draft({
    required String channelId,
    required String body,
    Map<String, String>? context,
    String? replyTo,
  }) async {
    final bytes = utf8.encode(body).length;
    if (bytes > maxBodyBytes) throw BodyTooLarge(bytes);
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(channelId))).getSingleOrNull();
    if (channel == null) throw const UnknownChannel();
    if (channel.closedAt != null) throw const ChannelClosed();
    final mine =
        await (db.select(db.channelMembers)..where(
              (m) =>
                  m.channelId.equals(channelId) & m.deviceId.equals(myDeviceId),
            ))
            .getSingleOrNull();
    if (!_current(mine)) throw const NotAMember();
    final now = _now();
    final id = const Uuid().v4();
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: id,
            channelId: channelId,
            kind: 'message',
            fromDeviceId: myDeviceId,
            sentAt: now,
            body: Value(body),
            contextJson: Value(context == null ? null : jsonEncode(context)),
            replyTo: Value(replyTo),
            direction: 'out',
            status: 'awaiting_approval',
            createdAt: now,
          ),
        );
    final m = await _get(id);
    _changes.add(m);
    return m;
  }

  /// Seals and queues a draft. Safe to call twice at once: only the first
  /// call sends. A draft older than 1 hour expires instead. A draft that can
  /// no longer go (I left the channel: [NotAMember]; it closed:
  /// [ChannelClosed]) is marked `discarded` and the reason rethrown.
  Future<Message> approve(String messageId) async {
    final bool changed;
    try {
      changed = await db.committing(() async {
        final m = await _get(messageId);
        if (m.status != 'awaiting_approval') return false;
        final mine =
            await (db.select(db.channelMembers)..where(
                  (x) =>
                      x.channelId.equals(m.channelId) &
                      x.deviceId.equals(myDeviceId),
                ))
                .getSingleOrNull();
        if (!_current(mine, event: m.kind == 'event')) {
          throw const NotAMember();
        }
        final channel = await (db.select(
          db.channels,
        )..where((c) => c.id.equals(m.channelId))).getSingle();
        if (channel.closedAt != null) throw const ChannelClosed();
        final now = _now();
        if (now - m.createdAt > draftLifetimeMs) {
          await (db.update(db.messages)..where((x) => x.id.equals(m.id))).write(
            const MessagesCompanion(status: Value('expired')),
          );
          if (m.kind == 'event') await dropEvent?.call(m);
          return true;
        }
        if (m.kind == 'event') {
          final publish = publishEvent;
          if (publish == null) throw StateError('no surat service for events');
          await publish(m);
          return true;
        }
        final hlc = clock.tick().encode();
        final seq = await db.nextSeq(m.channelId, myDeviceId);
        final recipients = await _recipients(m.channelId);
        final plain = utf8.encode(
          jsonEncode({
            'body': m.body,
            if (m.contextJson != null) 'context': jsonDecode(m.contextJson!),
          }),
        );
        for (final r in recipients) {
          final peer = r.peer;
          Envelope env(SealedEnvelope? sealed) => Envelope(
            id: m.id,
            channelId: m.channelId,
            kind: m.kind,
            from: myDeviceId,
            sentAt: now,
            hlc: hlc,
            seq: seq,
            replyTo: m.replyTo,
            sealed: sealed,
          );
          SealedEnvelope? sealed;
          if (r.sealed) {
            final aad = env(
              const SealedEnvelope(eph: '', nonce: '', ct: '', mac: ''),
            ).aad;
            sealed = await seal(plain, recipientBoxPub: peer.boxPub, aad: aad);
          }
          await _queue(
            m.id,
            peer.deviceId,
            '/relay/deliver',
            env(sealed).toJson(),
            now,
          );
        }
        await (db.update(db.messages)..where((x) => x.id.equals(m.id))).write(
          MessagesCompanion(
            status: const Value('queued'),
            hlc: Value(hlc),
            seq: Value(seq),
            sentAt: Value(now),
          ),
        );
        return true;
      });
    } on NotAMember {
      await _refused(messageId);
      rethrow;
    } on ChannelClosed {
      await _refused(messageId);
      rethrow;
    }
    final out = await _get(messageId);
    if (changed) _changes.add(out);
    return out;
  }

  /// Discards a draft whose approval was refused, so it doesn't linger.
  Future<void> _refused(String messageId) async {
    final m = await _get(messageId);
    if (m.status != 'awaiting_approval') return;
    await (db.update(db.messages)..where((x) => x.id.equals(messageId))).write(
      const MessagesCompanion(status: Value('discarded')),
    );
    if (m.kind == 'event') await dropEvent?.call(m);
    _changes.add(await _get(messageId));
  }

  Future<void> discard(String messageId) async {
    final m = await _get(messageId);
    if (m.status != 'awaiting_approval') return;
    await (db.update(db.messages)..where((x) => x.id.equals(messageId))).write(
      const MessagesCompanion(status: Value('discarded')),
    );
    if (m.kind == 'event') await dropEvent?.call(m);
    _changes.add(await _get(messageId));
  }

  /// Who gets a copy. A private channel seals for its paired member. A surat
  /// sends to every current member I can talk to, sealed only when both of us
  /// approved each other; the rest get a placeholder with no ciphertext.
  Future<List<({Peer peer, bool sealed})>> _recipients(String channelId) async {
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(channelId))).getSingle();
    final surat = channel.kind == 'surat';
    final q =
        db.select(db.channelMembers).join([
          innerJoin(
            db.peers,
            db.peers.deviceId.equalsExp(db.channelMembers.deviceId),
          ),
        ])..where(
          db.channelMembers.channelId.equals(channelId) &
              db.channelMembers.leftHlc.isNull(),
        );
    final out = <({Peer peer, bool sealed})>[];
    for (final row in await q.get()) {
      final peer = row.readTable(db.peers);
      final member = row.readTable(db.channelMembers);
      if (!surat) {
        if (peer.trust == 'paired') out.add((peer: peer, sealed: true));
        continue;
      }
      if (member.state != 'member' || !canTalk(peer)) continue;
      out.add((
        peer: peer,
        sealed:
            member.myApproval == 'approved' &&
            member.theirApproval == 'approved',
      ));
    }
    return out;
  }

  /// Re-sends my own past messages of [channelId] to [to], sealed for them,
  /// with their original id, stamp and seq and `history: true`, so a newcomer
  /// (or a member who just approved me) sees them and a locked placeholder
  /// unlocks. Never drafts, discarded or expired rows, never anyone else's
  /// messages, never events. Queued once per message and recipient. Returns
  /// how many were newly queued. The caller guarantees we approve each other.
  Future<int> reshareOwn(String channelId, Peer to) async {
    final rows =
        await (db.select(db.messages)
              ..where(
                (m) =>
                    m.channelId.equals(channelId) &
                    m.direction.equals('out') &
                    m.kind.equals('message') &
                    m.fromDeviceId.equals(myDeviceId) &
                    m.hlc.isNotNull() &
                    m.status.isIn(const ['queued', 'sent']),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.seq)]))
            .get();
    final now = _now();
    var queued = 0;
    for (final m in rows) {
      final id = '$historyPrefix${m.id}:${to.deviceId}';
      final exists =
          await (db.select(db.deliveries)..where(
                (d) =>
                    d.messageId.equals(id) &
                    d.recipientDeviceId.equals(to.deviceId),
              ))
              .getSingleOrNull();
      if (exists != null) {
        if (exists.status != 'dropped') continue;
        // A copy that timed out is given another chance.
        await (db.delete(db.deliveries)..where(
              (d) =>
                  d.messageId.equals(id) &
                  d.recipientDeviceId.equals(to.deviceId),
            ))
            .go();
      }
      Envelope env(SealedEnvelope? sealed) => Envelope(
        id: m.id,
        channelId: m.channelId,
        kind: m.kind,
        from: myDeviceId,
        sentAt: m.sentAt,
        hlc: m.hlc!,
        seq: m.seq!,
        replyTo: m.replyTo,
        history: true,
        sealed: sealed,
      );
      final plain = utf8.encode(
        jsonEncode({
          'body': m.body,
          if (m.contextJson != null) 'context': jsonDecode(m.contextJson!),
        }),
      );
      final aad = env(const SealedEnvelope(eph: '', nonce: '', ct: '', mac: ''))
          .aad;
      final sealed = await seal(plain, recipientBoxPub: to.boxPub, aad: aad);
      await _queue(
        id,
        to.deviceId,
        '/relay/deliver',
        env(sealed).toJson(),
        now,
      );
      queued++;
    }
    return queued;
  }

  Future<void> _queue(
    String messageId,
    String to,
    String path,
    Map<String, dynamic> payload,
    int now,
  ) {
    return db
        .into(db.deliveries)
        .insert(
          DeliveriesCompanion.insert(
            messageId: messageId,
            recipientDeviceId: to,
            envelopeJson: jsonEncode({'path': path, 'payload': payload}),
            status: 'queued',
            nextAttemptAt: now,
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<ReceiveResult> receive(Envelope e, {required Peer from}) async {
    if (e.kind == 'event') throw const BadEnvelope('events go to /relay/event');
    if (e.from != from.deviceId) throw const NotAMember();
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(e.channelId))).getSingleOrNull();
    final rows = await (db.select(
      db.channelMembers,
    )..where((m) => m.channelId.equals(e.channelId))).get();
    // Membership first: a sender never seated here learns nothing about the
    // channel, not even whether it exists or is closed.
    if (channel == null || !rows.any((m) => m.deviceId == from.deviceId)) {
      throw const NotAMember();
    }
    if (channel.kind == 'private' && from.trust != 'paired') {
      throw const UntrustedSender();
    }
    if (channel.closedAt != null) throw const ChannelClosed();
    final ids = {
      for (final m in rows)
        if (m.leftHlc == null &&
            (channel.kind != 'surat' || m.state == 'member'))
          m.deviceId,
    };
    if (!ids.contains(from.deviceId) || !ids.contains(myDeviceId)) {
      throw const NotAMember();
    }
    final now = _now();
    final Hlc stamp;
    try {
      stamp = Hlc.decode(e.hlc);
    } on Object {
      throw const BadEnvelope('malformed hlc');
    }
    if (stamp.wallMs > now + maxFutureSkewMs) {
      throw const BadEnvelope('stamped too far in the future');
    }
    clock.observe(stamp);
    String? body;
    String? contextJson;
    var status = 'unread';
    final sealed = e.sealed;
    try {
      if (sealed == null) throw const BadEnvelope('placeholder');
      final plain = jsonDecode(
        utf8.decode(await open(sealed, recipientBox: myBox, aad: e.aad)),
      ) as Map;
      body = plain['body'] as String?;
      contextJson = plain['context'] == null
          ? null
          : jsonEncode(plain['context']);
    } on Object {
      status = 'locked';
    }
    final row = MessagesCompanion.insert(
      id: e.id,
      channelId: e.channelId,
      kind: e.kind,
      fromDeviceId: e.from,
      sentAt: e.sentAt,
      hlc: Value(e.hlc),
      seq: Value(e.seq),
      body: Value(body),
      contextJson: Value(contextJson),
      replyTo: Value(e.replyTo),
      direction: 'in',
      status: status,
      arrivedLate: Value(now - e.sentAt > lateAfterMs),
      createdAt: now,
      receivedAt: Value(now),
    );
    final inserted = e.history
        ? await db.insertOrUnlock(row)
        : await db.insertIncomingIfNew(row);
    final m = await _get(e.id);
    if (inserted && !e.history) _incoming.add(m);
    return (duplicate: !inserted, message: m);
  }

  /// Ordered messages of a channel; marks the returned ones read by [by] and
  /// queues one receipt per message and reader kind. [unreadOnly] returns only
  /// what [by] has not read yet — the person and the agent are tracked apart.
  Future<List<Message>> read(
    String channelId, {
    bool unreadOnly = false,
    required Reader by,
  }) async {
    final list = await db.channelMessages(
      channelId,
      unreadBy: unreadOnly ? by : null,
    );
    final now = _now();
    // Event rows and locked placeholders are shown but never read: no marks,
    // no receipts. A placeholder that unlocks later is then still unread.
    for (final m in list.where(
      (m) => m.direction == 'in' && m.kind != 'event' && m.status != 'locked',
    )) {
      final already = by == Reader.agent ? m.agentReadAt : m.seenAt;
      await (db.update(db.messages)..where((x) => x.id.equals(m.id))).write(
        MessagesCompanion(
          status: m.status == 'unread'
              ? const Value('read')
              : const Value.absent(),
          agentReadAt: by == Reader.agent && already == null
              ? Value(now)
              : const Value.absent(),
          seenAt: by == Reader.person && already == null
              ? Value(now)
              : const Value.absent(),
        ),
      );
      if (already == null) {
        final kind = by == Reader.agent ? 'agent_read' : 'seen';
        await _queue(
          'receipt:${m.id}:$kind',
          m.fromDeviceId,
          '/relay/receipt',
          {'messageId': m.id, 'kind': kind, 'at': now},
          now,
        );
      }
    }
    return list;
  }

  /// `/relay/receipt` from [from]. False when that peer never got the message.
  Future<bool> handleReceipt(
    Map<String, dynamic> body, {
    required Peer from,
  }) async {
    final messageId = body['messageId'] as String?;
    final kind = body['kind'] as String?;
    final at = body['at'] as int?;
    if (messageId == null || at == null) return false;
    final row =
        await (db.select(db.deliveries)..where(
              (d) =>
                  d.messageId.equals(messageId) &
                  d.recipientDeviceId.equals(from.deviceId),
            ))
            .getSingleOrNull();
    if (row == null) return false;
    if (kind != 'seen' && kind != 'agent_read') return false;
    final update = kind == 'seen'
        ? (row.seenAt == null ? DeliveriesCompanion(seenAt: Value(at)) : null)
        : (row.agentReadAt == null
              ? DeliveriesCompanion(agentReadAt: Value(at))
              : null);
    if (update != null) {
      await (db.update(db.deliveries)..where(
            (d) =>
                d.messageId.equals(messageId) &
                d.recipientDeviceId.equals(from.deviceId),
          ))
          .write(update);
      _changes.add(await _get(messageId));
    }
    return true;
  }

  /// The worker calls this when a recipient's Mac accepted a message.
  Future<void> markDelivered(String messageId, String recipientDeviceId) async {
    final now = _now();
    await (db.update(db.deliveries)..where(
          (d) =>
              d.messageId.equals(messageId) &
              d.recipientDeviceId.equals(recipientDeviceId),
        ))
        .write(
          DeliveriesCompanion(
            status: const Value('delivered'),
            deliveredAt: Value(now),
          ),
        );
    final m = await (db.select(
      db.messages,
    )..where((x) => x.id.equals(messageId))).getSingleOrNull();
    if (m == null) return; // a receipt or a history copy, not a message
    final open =
        await (db.select(db.deliveries)..where(
              (d) => d.messageId.equals(messageId) & d.status.equals('queued'),
            ))
            .get();
    if (open.isEmpty && m.status == 'queued') {
      await (db.update(db.messages)..where((x) => x.id.equals(messageId)))
          .write(const MessagesCompanion(status: Value('sent')));
    }
    _changes.add(await _get(messageId));
  }

  Future<List<Receipt>> receiptsFor(String messageId) async {
    final q = db.select(db.deliveries).join([
      innerJoin(
        db.peers,
        db.peers.deviceId.equalsExp(db.deliveries.recipientDeviceId),
      ),
    ])..where(db.deliveries.messageId.equals(messageId));
    return [
      for (final row in await q.get())
        (
          deviceId: row.readTable(db.peers).deviceId,
          personName: row.readTable(db.peers).personName,
          deliveredAt: row.readTable(db.deliveries).deliveredAt,
          seenAt: row.readTable(db.deliveries).seenAt,
          agentReadAt: row.readTable(db.deliveries).agentReadAt,
        ),
    ];
  }
}
