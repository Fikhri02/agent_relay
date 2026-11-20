import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../crypto/sealed_box.dart';
import '../data/relay_database.dart';
import '../ordering/hlc.dart';
import 'envelope.dart';

export '../data/relay_database.dart' show Reader;

const maxBodyBytes = 32768;
const lateAfterMs = 120000;

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

/// A delivery this Mac won't take from this peer: the channel is closed, or
/// it is private and the sender is no longer paired. Answered as 401.
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
  /// call sends. A draft older than 1 hour expires instead.
  Future<Message> approve(String messageId) async {
    final changed = await db.transaction(() async {
      final m = await _get(messageId);
      if (m.status != 'awaiting_approval') return false;
      final now = _now();
      if (now - m.createdAt > draftLifetimeMs) {
        await (db.update(db.messages)..where((x) => x.id.equals(m.id))).write(
          const MessagesCompanion(status: Value('expired')),
        );
        return true;
      }
      final hlc = clock.tick().encode();
      final seq = await db.nextSeq(m.channelId, myDeviceId);
      final recipients = await _pairedRecipients(m.channelId);
      final plain = utf8.encode(
        jsonEncode({
          'body': m.body,
          if (m.contextJson != null) 'context': jsonDecode(m.contextJson!),
        }),
      );
      for (final peer in recipients) {
        Envelope env(SealedEnvelope sealed) => Envelope(
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
        final aad = env(
          const SealedEnvelope(eph: '', nonce: '', ct: '', mac: ''),
        ).aad;
        final sealed = await seal(
          plain,
          recipientBoxPub: peer.boxPub,
          aad: aad,
        );
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
    final out = await _get(messageId);
    if (changed) _changes.add(out);
    return out;
  }

  Future<void> discard(String messageId) async {
    final m = await _get(messageId);
    if (m.status != 'awaiting_approval') return;
    await (db.update(db.messages)..where((x) => x.id.equals(messageId))).write(
      const MessagesCompanion(status: Value('discarded')),
    );
    _changes.add(await _get(messageId));
  }

  Future<List<Peer>> _pairedRecipients(String channelId) async {
    final q =
        db.select(db.channelMembers).join([
          innerJoin(
            db.peers,
            db.peers.deviceId.equalsExp(db.channelMembers.deviceId),
          ),
        ])..where(
          db.channelMembers.channelId.equals(channelId) &
              db.channelMembers.leftHlc.isNull() &
              db.peers.trust.equals('paired'),
        );
    return [for (final row in await q.get()) row.readTable(db.peers)];
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
    if (e.from != from.deviceId) throw const NotAMember();
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(e.channelId))).getSingleOrNull();
    if (channel != null &&
        (channel.closedAt != null ||
            (channel.kind == 'private' && from.trust != 'paired'))) {
      throw const UntrustedSender();
    }
    final members =
        await (db.select(db.channelMembers)..where(
              (m) => m.channelId.equals(e.channelId) & m.leftHlc.isNull(),
            ))
            .get();
    final ids = members.map((m) => m.deviceId).toSet();
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
    final inserted = await db.insertIncomingIfNew(
      MessagesCompanion.insert(
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
      ),
    );
    final m = await _get(e.id);
    if (inserted) _incoming.add(m);
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
    for (final m in list.where((m) => m.direction == 'in')) {
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
      if (already == null && m.status != 'locked') {
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
    if (m == null) return; // a receipt, not a message
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
