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

/// Records a vouched member as a `surat_contact` pinned to the card's
/// fingerprint. A `paired` row is never touched; an existing contact whose
/// keys or fingerprint changed gets the new values (re-vouch).
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
      personName: Value(card.personName),
      deviceName: Value(card.deviceName),
      signPub: Value(Uint8List.fromList(card.signPub)),
      boxPub: Value(Uint8List.fromList(card.boxPub)),
      certFingerprint: Value(card.certFingerprint),
      trust: const Value(trustSuratContact),
      lastAddress: card.address == null
          ? const Value.absent()
          : Value(card.address),
      lastPort: card.port == null ? const Value.absent() : Value(card.port),
    ),
  );
}

/// Deletes `surat_contact` peers that share no open surat with me. A contact
/// with a delivery still queued (the leave or last event that ended our
/// shared surat) is kept until a later call, so that event can reach it.
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
    if (waiting.isEmpty && !await sharesSurat(db, myDeviceId, c.deviceId)) {
      await (db.delete(
        db.peers,
      )..where((p) => p.deviceId.equals(c.deviceId))).go();
    }
  }
}
