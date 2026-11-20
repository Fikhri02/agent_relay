import 'dart:convert';

import 'package:drift/drift.dart';

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
import 'surat_state.dart';

typedef Projected = ({SuratState state, List<SuratChange> changes});
typedef Received = ({bool duplicate, List<SuratChange> changes});

/// Decides whether a membership event from a peer may enter a surat's log,
/// stores it and reprojects the surat. Everything an event writes (channel,
/// contacts, its row, the projection) commits together or not at all.
class SuratReceiver {
  SuratReceiver({
    required this.db,
    required this.me,
    required this.keys,
    required this.clock,
    required int Function() nowMs,
    required this._project,
  }) : _now = nowMs;

  final RelayDatabase db;
  final LocalIdentity me;
  final IdentityKeys keys;
  final HlcClock clock;
  final int Function() _now;

  /// Projects a surat inside the caller's transaction.
  final Future<Projected> Function(String suratId) _project;

  /// Throws [BadEnvelope] for anything malformed, unopenable or carrying a
  /// card that fails its check; [NotAMember] when [from] may not write this
  /// event here. A create or invite naming me, while I'm not in the surat,
  /// is taken only from a paired peer. Any other event must come from a
  /// device seated (member or invited) in the surat before or after it is
  /// stored, and only while I am seated in it too.
  Future<Received> receive(Envelope e, {required Peer from}) async {
    if (e.kind != 'event') throw const BadEnvelope('not an event');
    if (e.from != from.deviceId) throw const NotAMember();
    if (e.seq != 0) throw const BadEnvelope('an event has seq 0');
    final stamp = _stamp(e.hlc);
    final event = await _open(e);
    final result = await db.transaction(() async {
      final existing = await (db.select(
        db.messages,
      )..where((m) => m.id.equals(e.id))).getSingleOrNull();
      if (existing != null) {
        if (existing.kind != 'event' ||
            existing.channelId != e.channelId ||
            existing.fromDeviceId != e.from) {
          throw const BadEnvelope('id already in use');
        }
        return (duplicate: true, changes: const <SuratChange>[]);
      }
      final channel = await (db.select(
        db.channels,
      )..where((c) => c.id.equals(e.channelId))).getSingleOrNull();
      if (channel != null && channel.kind != 'surat') {
        throw const NotAMember();
      }
      final seated = channel != null && await _seated(e.channelId, me.deviceId);
      if (!seated && _namesMe(event)) {
        return _join(e, event, from, channel);
      }
      if (!seated) throw const NotAMember();
      return _apply(e, event, from);
    });
    clock.observe(stamp);
    return result;
  }

  /// I'm the newcomer: open (or reopen) the surat from the create or the
  /// snapshot, with every carried card checked first.
  Future<Received> _join(
    Envelope e,
    SuratEvent event,
    Peer from,
    Channel? channel,
  ) async {
    if (from.trust != trustPaired) throw const NotAMember();
    final suratId = e.channelId;
    final String name, creator;
    final List<MemberCard> cards;
    switch (event) {
      case CreateEvent():
        await _checkVouched(suratId, from, event.invitees, event.vouches);
        name = event.name;
        creator = from.deviceId;
        cards = event.invitees;
      case InviteEvent(:final snapshot?):
        await _checkVouched(
          suratId,
          from,
          [event.newcomer],
          {event.newcomer.deviceId: event.vouch},
        );
        // Trusted on the paired inviter's word, but each card must be the
        // keys it names.
        cards = [...snapshot.members, ...snapshot.invited];
        for (final c in cards) {
          if (deviceIdFor(c.signPub, c.boxPub) != c.deviceId) {
            throw const BadEnvelope('a snapshot card does not match its keys');
          }
        }
        name = snapshot.name;
        creator = snapshot.creatorDeviceId;
      default:
        throw const BadEnvelope('an invite for me carries the surat');
    }
    if (channel == null) {
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              id: suratId,
              kind: 'surat',
              name: Value(name),
              createdAt: _now(),
              creatorDeviceId: Value(creator),
            ),
          );
    }
    await _store(e, event);
    final projected = await _project(suratId);
    if (projected.state.members[me.deviceId]?.state != MemberState.invited) {
      throw const NotAMember(); // it didn't seat me: not a real invite
    }
    await _addContacts(cards, projected.state);
    return (duplicate: false, changes: projected.changes);
  }

  /// I'm in the surat: [from] must be seated in it, before or after the
  /// event (a leave or decline_invite unseats its sender).
  Future<Received> _apply(Envelope e, SuratEvent event, Peer from) async {
    final suratId = e.channelId;
    final wasSeated = await _seated(suratId, from.deviceId);
    var stored = event;
    var cards = const <MemberCard>[];
    switch (event) {
      case CreateEvent(:final invitees, :final vouches):
        await _checkVouched(suratId, from, invitees, vouches);
        cards = invitees;
      case InviteEvent(:final newcomer, :final vouch, :final snapshot):
        await _checkVouched(
          suratId,
          from,
          [newcomer],
          {newcomer.deviceId: vouch},
        );
        if (snapshot != null) {
          if (newcomer.deviceId != me.deviceId) {
            throw const BadEnvelope('a snapshot is only for the newcomer');
          }
          // Already in: a snapshot would restart my log from it.
          stored = InviteEvent(
            newcomer: newcomer,
            vouch: vouch,
            snapshot: null,
          );
        }
        cards = [newcomer];
      default:
        break;
    }
    await _store(e, stored);
    final projected = await _project(suratId);
    final now = projected.state.members[from.deviceId]?.state;
    if (!wasSeated && now != MemberState.member && now != MemberState.invited) {
      throw const NotAMember(); // rolls back the row and the projection
    }
    await _addContacts(cards, projected.state);
    return (duplicate: false, changes: projected.changes);
  }

  bool _namesMe(SuratEvent event) => switch (event) {
    CreateEvent(:final invitees) => invitees.any(
      (c) => c.deviceId == me.deviceId,
    ),
    InviteEvent(:final newcomer) => newcomer.deviceId == me.deviceId,
    _ => false,
  };

  Future<bool> _seated(String suratId, String deviceId) async {
    final row =
        await (db.select(db.channelMembers)..where(
              (m) => m.channelId.equals(suratId) & m.deviceId.equals(deviceId),
            ))
            .getSingleOrNull();
    return row?.state == 'member' || row?.state == 'invited';
  }

  /// Every card needs [from]'s vouch for this surat.
  Future<void> _checkVouched(
    String suratId,
    Peer from,
    List<MemberCard> cards,
    Map<String, String> vouches,
  ) async {
    for (final c in cards) {
      final sig = vouches[c.deviceId];
      if (sig == null || !await checkVouch(from.signPub, suratId, c, sig)) {
        throw const BadEnvelope('a card without a valid vouch');
      }
    }
  }

  /// Contacts for the carried cards of devices the event leaves seated
  /// (member or invited) in [state]; never my own card.
  Future<void> _addContacts(List<MemberCard> cards, SuratState state) async {
    for (final c in cards) {
      final seat = state.members[c.deviceId]?.state;
      if (c.deviceId == me.deviceId ||
          (seat != MemberState.member && seat != MemberState.invited)) {
        continue;
      }
      await addOrRefreshContact(db, c, nowMs: _now());
    }
  }

  Future<void> _store(Envelope e, SuratEvent event) {
    final now = _now();
    return db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: e.id,
            channelId: e.channelId,
            kind: 'event',
            fromDeviceId: e.from,
            sentAt: e.sentAt,
            hlc: Value(e.hlc),
            seq: const Value(0),
            body: Value(jsonEncode(event.toJson())),
            direction: 'in',
            status: 'read',
            arrivedLate: Value(now - e.sentAt > lateAfterMs),
            createdAt: now,
            receivedAt: Value(now),
          ),
        );
  }

  Hlc _stamp(String hlc) {
    final Hlc stamp;
    try {
      stamp = Hlc.decode(hlc);
    } on Object {
      throw const BadEnvelope('malformed hlc');
    }
    if (stamp.wallMs > _now() + maxFutureSkewMs) {
      throw const BadEnvelope('stamped too far in the future');
    }
    return stamp;
  }

  Future<SuratEvent> _open(Envelope e) async {
    final sealed = e.sealed;
    if (sealed == null) throw const BadEnvelope('an event is always sealed');
    try {
      final plain = await open(sealed, recipientBox: keys.box, aad: e.aad);
      return SuratEvent.fromJson(jsonDecode(utf8.decode(plain)) as Map);
    } on Object {
      throw const BadEnvelope('the event does not open');
    }
  }
}
