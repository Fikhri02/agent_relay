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
import 'surat_event.dart';
import 'surat_state.dart';

/// The peer route membership events travel on.
const eventPath = '/relay/event';

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

/// What a [SuratService.rebuild] changed that the person should hear about.
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

const _zeroHlc = '0000000000000-00000';

typedef _Loaded = ({
  Channel channel,
  List<LoggedEvent> log,
  SuratState state,
  String? snapshotHlc,
});

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
                joinedHlc: _zeroHlc,
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
    if ((await _load(suratId)).state.renamer != me.deviceId) {
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
    final event = _decode(draft.body);
    if (event == null) throw StateError('draft ${draft.id} is no surat event');
    final suratId = draft.channelId;
    if ((await _load(suratId)).channel.closedAt != null) {
      throw const ChannelClosed();
    }
    final snapshot = event is InviteEvent ? await _snapshot(suratId) : null;
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
    final state = (await _load(suratId)).state;
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
    if (_decode(draft.body) is! CreateEvent) return;
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
    final told = <SuratChange>[];
    final state = await db.transaction(() async {
      final loaded = await _load(suratId);
      final state = loaded.state;
      if (state.members.isEmpty) return state; // no create or snapshot yet
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
                    m.joinedHlc ??
                    seatedAt[id] ??
                    loaded.snapshotHlc ??
                    _zeroHlc,
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
      told.addAll(_diff(suratId, channel, prev, state));
      await forgetLoneContacts(db, mine);
      return state;
    });
    told.forEach(_changes.add);
    return state;
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
  Future<_Loaded> _load(String suratId) async {
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
            if (_decode(r.body) case final e?)
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
  Future<SuratSnapshot> _snapshot(String suratId) async {
    final loaded = await _load(suratId);
    final s = loaded.state;
    final cards = _eventCards(loaded.log);
    for (final p in await db.select(db.peers).get()) {
      cards[p.deviceId] = _card(p);
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

  Future<MemberCard> _pairedCard(String deviceId) async {
    final p = await (db.select(
      db.peers,
    )..where((p) => p.deviceId.equals(deviceId))).getSingleOrNull();
    if (p == null || p.trust != trustPaired) throw UnknownPeer(deviceId);
    return _card(p);
  }

  static MemberCard _card(Peer p) => MemberCard(
    deviceId: p.deviceId,
    personName: p.personName,
    deviceName: p.deviceName,
    signPub: p.signPub,
    boxPub: p.boxPub,
    certFingerprint: p.certFingerprint,
    address: p.lastAddress,
    port: p.lastPort,
  );

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

  static SuratEvent? _decode(String? body) {
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
