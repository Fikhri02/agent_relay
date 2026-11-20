import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../crypto/identity_keys.dart';
import '../crypto/sealed_box.dart';
import '../crypto/vouch.dart';
import '../data/relay_database.dart';
import '../identity/local_identity.dart';
import '../messaging/envelope.dart';
import '../messaging/message_service.dart';
import '../ordering/hlc.dart';
import '../peer/trust.dart';
import 'surat_change.dart';
import 'surat_event.dart';
import 'surat_projection.dart';
import 'surat_receiver.dart';
import 'surat_state.dart';

export 'surat_change.dart';

/// The peer route membership events travel on.
const eventPath = '/relay/event';

/// Drafts membership changes, publishes approved ones as sealed events to
/// every member and invitee, and keeps `ChannelMembers` as a projection of the
/// stored event log.
class SuratService {
  SuratService({
    required this.db,
    required this.messages,
    required this.keys,
    required this.me,
    required this.clock,
    int Function()? nowMs,
    this.myPort,
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final RelayDatabase db;
  final MessageService messages;
  final IdentityKeys keys;
  final LocalIdentity me;
  final HlcClock clock;

  /// This Mac's peer port, put in my card for a newcomer.
  final int Function()? myPort;
  final int Function() _now;
  final _changes = StreamController<SuratChange>.broadcast();
  late final _projection = SuratProjection(
    db: db,
    me: me,
    keys: keys,
    nowMs: _now,
    myPort: myPort,
  );
  late final _receiver = SuratReceiver(
    db: db,
    me: me,
    keys: keys,
    clock: clock,
    nowMs: _now,
    project: _projectInTransaction,
  );

  Stream<SuratChange> get changes => _changes.stream;

  /// Creates the surat with me as its only member and drafts its creation.
  /// Returns the draft id; the surat id is the draft's channel id.
  Future<String> draftCreate(String name, List<String> inviteeDeviceIds) async {
    final title = name.trim();
    if (title.isEmpty) throw ArgumentError.value(name, 'name', 'is empty');
    final ids = inviteeDeviceIds.toSet()..remove(me.deviceId);
    if (ids.isEmpty) {
      throw ArgumentError.value(inviteeDeviceIds, 'inviteeDeviceIds', 'none');
    }
    if (ids.length >= suratSeatCap) throw const TooManyMembers();
    final cards = [for (final id in ids) await _pairedCard(id)];
    final suratId = const Uuid().v4();
    final event = CreateEvent(
      name: title,
      invitees: cards,
      vouches: {
        for (final c in cards)
          c.deviceId: await vouch(keys.signing, suratId, c),
      },
    );
    final now = _now();
    return _draft(
      suratId,
      event,
      before: () async {
        await db
            .into(db.channels)
            .insert(
              ChannelsCompanion.insert(
                id: suratId,
                kind: 'surat',
                name: Value(title),
                createdAt: now,
                creatorDeviceId: Value(me.deviceId),
              ),
            );
        await db
            .into(db.channelMembers)
            .insert(
              ChannelMembersCompanion.insert(
                channelId: suratId,
                deviceId: me.deviceId,
                joinedHlc: unpublishedHlc,
                personName: Value(me.personName),
                deviceName: Value(me.deviceName),
              ),
            );
      },
    );
  }

  Future<String> draftInvite(String suratId, String deviceId) async {
    final rows = await _asMember(suratId);
    bool seated(ChannelMember m) => m.state == 'member' || m.state == 'invited';
    if (rows.any((m) => m.deviceId == deviceId && seated(m))) {
      throw const NotAllowed('already in this surat');
    }
    if (rows.where(seated).length >= suratSeatCap) throw const TooManyMembers();
    final card = await _pairedCard(deviceId);
    return _draft(
      suratId,
      InviteEvent(
        newcomer: card,
        vouch: await vouch(keys.signing, suratId, card),
        snapshot: null,
      ),
    );
  }

  Future<String> draftLeave(String suratId) async {
    await _asMember(suratId);
    return _draft(suratId, const LeaveEvent());
  }

  Future<String> draftRename(String suratId, String name) async {
    final title = name.trim();
    if (title.isEmpty) throw ArgumentError.value(name, 'name', 'is empty');
    await _asMember(suratId);
    if ((await _projection.load(suratId)).state.renamer != me.deviceId) {
      throw const NotAllowed('only the renamer renames');
    }
    return _draft(suratId, RenameEvent(title));
  }

  /// Stamps [draft], seals it for every other member and invitee I can talk
  /// to on [eventPath], and applies it through [rebuild]. The newcomer's copy
  /// of an invite carries the surat's snapshot; every other copy, and my row,
  /// carry none. Events use seq 0 so message seqs stay contiguous. An ended
  /// surat takes no more events ([ChannelClosed]).
  Future<void> publish(Message draft) => db.transaction(() async {
    final event = SuratProjection.decode(draft.body);
    if (event == null) throw StateError('draft ${draft.id} is no surat event');
    final suratId = draft.channelId;
    if ((await _projection.load(suratId)).channel.closedAt != null) {
      throw const ChannelClosed();
    }
    final snapshot = event is InviteEvent
        ? await _projection.snapshot(suratId)
        : null;
    final now = _now();
    final hlc = clock.tick().encode();
    Future<void> write(MessagesCompanion c) =>
        (db.update(db.messages)..where((m) => m.id.equals(draft.id))).write(c);
    await write(
      MessagesCompanion(
        hlc: Value(hlc),
        seq: const Value(0),
        sentAt: Value(now),
      ),
    );
    final state = (await _projection.load(suratId)).state;
    final peers = {
      for (final p in await db.select(db.peers).get())
        if (canTalk(p)) p.deviceId: p,
    };
    final to = [
      for (final e in state.members.entries)
        if (e.key != me.deviceId &&
            (e.value.state == MemberState.member ||
                e.value.state == MemberState.invited) &&
            peers.containsKey(e.key))
          peers[e.key]!,
    ]..sort((a, b) => a.deviceId.compareTo(b.deviceId));
    Envelope envelope(SealedEnvelope? sealed) => Envelope(
      id: draft.id,
      channelId: suratId,
      kind: 'event',
      from: me.deviceId,
      sentAt: now,
      hlc: hlc,
      seq: 0,
      sealed: sealed,
    );
    final aad = envelope(null).aad;
    for (final peer in to) {
      final copy =
          event is InviteEvent && event.newcomer.deviceId == peer.deviceId
          ? InviteEvent(
              newcomer: event.newcomer,
              vouch: event.vouch,
              snapshot: snapshot,
            )
          : event;
      final sealed = await seal(
        utf8.encode(jsonEncode(copy.toJson())),
        recipientBoxPub: peer.boxPub,
        aad: aad,
      );
      await db
          .into(db.deliveries)
          .insert(
            DeliveriesCompanion.insert(
              messageId: draft.id,
              recipientDeviceId: peer.deviceId,
              envelopeJson: jsonEncode({
                'path': eventPath,
                'payload': envelope(sealed).toJson(),
              }),
              status: 'queued',
              nextAttemptAt: now,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await write(
      MessagesCompanion(status: Value(to.isEmpty ? 'sent' : 'queued')),
    );
    await rebuild(suratId);
  });

  /// A discarded or expired `CreateEvent` draft takes its never-published
  /// surat with it. Other drafts leave nothing to undo.
  Future<void> dropDraft(Message draft) async {
    if (draft.kind != 'event' || draft.hlc != null) return;
    if (SuratProjection.decode(draft.body) is! CreateEvent) return;
    final suratId = draft.channelId;
    await db.transaction(() async {
      final published =
          await (db.select(db.messages)
                ..where((m) => m.channelId.equals(suratId) & m.hlc.isNotNull())
                ..limit(1))
              .get();
      if (published.isNotEmpty) return;
      await (db.delete(
        db.channelMembers,
      )..where((m) => m.channelId.equals(suratId))).go();
      await (db.delete(db.channels)..where((c) => c.id.equals(suratId))).go();
    });
  }

  /// Replays every stored event of the surat (from the snapshot I was sent,
  /// when there is one) and writes the result into `ChannelMembers` and
  /// `Channels`. Running it twice changes nothing the second time.
  Future<SuratState> rebuild(String suratId) async {
    final result = await db.transaction(() => _projectInTransaction(suratId));
    result.changes.forEach(_changes.add);
    return result.state;
  }

  /// A membership event from [from] on [eventPath]: checked, stored once and
  /// applied through the projection (see [SuratReceiver.receive]). Throws
  /// [BadEnvelope] or [NotAMember] and stores nothing when refused.
  Future<({bool duplicate})> receiveEvent(
    Envelope e, {
    required Peer from,
  }) async {
    final r = await _receiver.receive(e, from: from);
    r.changes.forEach(_changes.add);
    return (duplicate: r.duplicate);
  }

  Future<Projected> _projectInTransaction(String suratId) async {
    final result = await _projection.project(suratId);
    if (result.state.members.isNotEmpty) {
      await forgetLoneContacts(db, me.deviceId);
    }
    return result;
  }

  Future<MemberCard> _pairedCard(String deviceId) async {
    final p = await (db.select(
      db.peers,
    )..where((p) => p.deviceId.equals(deviceId))).getSingleOrNull();
    if (p == null || p.trust != trustPaired) throw UnknownPeer(deviceId);
    return SuratProjection.cardOf(p);
  }

  /// The surat's member rows, once it is open and I am a member in it.
  Future<List<ChannelMember>> _asMember(String suratId) async {
    final channel = await (db.select(
      db.channels,
    )..where((c) => c.id.equals(suratId))).getSingleOrNull();
    if (channel == null || channel.kind != 'surat') {
      throw const UnknownChannel();
    }
    if (channel.closedAt != null) throw const ChannelClosed();
    final rows = await (db.select(
      db.channelMembers,
    )..where((m) => m.channelId.equals(suratId))).get();
    final mine = rows.where((m) => m.deviceId == me.deviceId).firstOrNull;
    if (mine?.state != 'member') throw const NotAMember();
    if (mine!.joinedHlc == unpublishedHlc) {
      throw const NotAllowed('the surat is not created yet');
    }
    return rows;
  }

  Future<String> _draft(
    String suratId,
    SuratEvent event, {
    Future<void> Function()? before,
  }) async {
    final id = const Uuid().v4();
    final now = _now();
    await db.transaction(() async {
      await before?.call();
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
              status: 'awaiting_approval',
              createdAt: now,
            ),
          );
    });
    messages.announce(
      await (db.select(db.messages)..where((m) => m.id.equals(id))).getSingle(),
    );
    return id;
  }
}
