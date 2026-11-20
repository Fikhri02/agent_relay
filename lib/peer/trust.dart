import 'package:drift/drift.dart';

import '../crypto/vouch.dart';
import '../data/relay_database.dart';

const trustPaired = 'paired';
const trustSuratContact = 'surat_contact';

/// True when this peer may send and receive: paired, or a surat contact.
/// A contact is only ever accepted for surats both Macs are in.
bool canTalk(Peer p) => p.trust == trustPaired || p.trust == trustSuratContact;

/// Whether some open surat has both me and [deviceId] as `member` or `invited`.
Future<bool> sharesSurat(
  RelayDatabase db,
  String myDeviceId,
  String deviceId,
) async {
  final mine = db.alias(db.channelMembers, 'mine');
  final theirs = db.alias(db.channelMembers, 'theirs');
  final q =
      db.select(db.channels).join([
          innerJoin(mine, mine.channelId.equalsExp(db.channels.id)),
          innerJoin(theirs, theirs.channelId.equalsExp(db.channels.id)),
        ])
        ..where(
          db.channels.kind.equals('surat') &
              db.channels.closedAt.isNull() &
              mine.deviceId.equals(myDeviceId) &
              mine.state.isIn(const ['member', 'invited']) &
              theirs.deviceId.equals(deviceId) &
              theirs.state.isIn(const ['member', 'invited']),
        )
        ..limit(1);
  return (await q.get()).isNotEmpty;
}

/// Records a carried member card as a `surat_contact` pinned to the card's
/// fingerprint. Only a device with no row yet takes the card's identity: an
/// existing row keeps its keys, fingerprint and names (a card is the
/// sender's word, not the device's), and gains the card's address and port
/// only where it has none. A `paired` row is never touched.
Future<void> addOrRefreshContact(
  RelayDatabase db,
  MemberCard card, {
  required int nowMs,
}) async {
  final existing = await (db.select(
    db.peers,
  )..where((p) => p.deviceId.equals(card.deviceId))).getSingleOrNull();
  if (existing != null && existing.trust == trustPaired) return;
  if (existing == null) {
    await db
        .into(db.peers)
        .insert(
          PeersCompanion.insert(
            deviceId: card.deviceId,
            personName: card.personName,
            deviceName: card.deviceName,
            signPub: Uint8List.fromList(card.signPub),
            boxPub: Uint8List.fromList(card.boxPub),
            certFingerprint: card.certFingerprint,
            trust: trustSuratContact,
            lastAddress: Value(card.address),
            lastPort: Value(card.port),
            pairedAt: nowMs,
          ),
        );
    return;
  }
  await (db.update(
    db.peers,
  )..where((p) => p.deviceId.equals(card.deviceId))).write(
    PeersCompanion(
      trust: const Value(trustSuratContact),
      lastAddress: existing.lastAddress == null && card.address != null
          ? Value(card.address)
          : const Value.absent(),
      lastPort: existing.lastPort == null && card.port != null
          ? Value(card.port)
          : const Value.absent(),
    ),
  );
}

/// Deletes `surat_contact` peers that share no open surat with me. A contact
/// with a delivery still queued (the leave or last event that ended our
/// shared surat) is kept until a later call, so that event can reach it. A
/// former paired peer (one with a private channel here) goes back to
/// `unpaired` instead, so that closed channel keeps its name.
Future<void> forgetLoneContacts(RelayDatabase db, String myDeviceId) async {
  final contacts = await (db.select(
    db.peers,
  )..where((p) => p.trust.equals(trustSuratContact))).get();
  for (final c in contacts) {
    final waiting =
        await (db.select(db.deliveries)
              ..where(
                (d) =>
                    d.recipientDeviceId.equals(c.deviceId) &
                    d.status.equals('queued'),
              )
              ..limit(1))
            .get();
    if (waiting.isNotEmpty || await sharesSurat(db, myDeviceId, c.deviceId)) {
      continue;
    }
    final private =
        await (db.select(db.channels).join([
                innerJoin(
                  db.channelMembers,
                  db.channelMembers.channelId.equalsExp(db.channels.id),
                ),
              ])
              ..where(
                db.channels.kind.equals('private') &
                    db.channelMembers.deviceId.equals(c.deviceId),
              )
              ..limit(1))
            .get();
    if (private.isNotEmpty) {
      await (db.update(db.peers)..where((p) => p.deviceId.equals(c.deviceId)))
          .write(const PeersCompanion(trust: Value('unpaired')));
    } else {
      await (db.delete(
        db.peers,
      )..where((p) => p.deviceId.equals(c.deviceId))).go();
    }
  }
}
