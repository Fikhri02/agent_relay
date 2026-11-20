import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/sealed_box.dart';
import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/identity/local_identity.dart';
import 'package:agent_relay/messaging/envelope.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:agent_relay/surat/surat_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

var now = 1700000000000;

/// One Mac: its keys, database, message service and surat service, wired the
/// way the node wires them.
class Side {
  Side(this.name, this.keys, this.db, this.messages, this.surat);
  final String name;
  final IdentityKeys keys;
  final RelayDatabase db;
  final MessageService messages;
  final SuratService surat;
  final changes = <SuratChange>[];
  String get id => deviceIdFor(keys.signPub, keys.boxPub);

  MemberCard get card => MemberCard(
    deviceId: id,
    personName: name,
    deviceName: '$name Mac',
    signPub: keys.signPub,
    boxPub: keys.boxPub,
    certFingerprint: 'fp-$name',
  );

  static Future<Side> make(String name) async {
    final keys = await IdentityKeys.generate();
    final db = memoryDb();
    final id = deviceIdFor(keys.signPub, keys.boxPub);
    final clock = HlcClock(nowMs: () => now);
    final messages = MessageService(
      db: db,
      myDeviceId: id,
      myBox: keys.box,
      clock: clock,
      nowMs: () => now,
    );
    final me = LocalIdentity(
      deviceId: id,
      personName: name,
      deviceName: '$name Mac',
      keys: keys,
      certPath: '',
      keyPath: '',
      certFingerprint: 'fp-$name',
    );
    final surat = SuratService(
      db: db,
      messages: messages,
      keys: keys,
      me: me,
      clock: clock,
      nowMs: () => now,
      myPort: () => 9000,
    );
    messages
      ..publishEvent = surat.publish
      ..dropEvent = surat.dropDraft;
    final side = Side(name, keys, db, messages, surat);
    surat.changes.listen(side.changes.add);
    return side;
  }

  Future<void> pair(Side other) => insertPeer(
    db,
    other.keys,
    name: other.name,
    fingerprint: 'fp-${other.name}',
  );

  Future<List<ChannelMember>> members(String suratId) =>
      (db.select(db.channelMembers)
            ..where((m) => m.channelId.equals(suratId))
            ..orderBy([(m) => OrderingTerm.asc(m.deviceId)]))
          .get();

  Future<ChannelMember?> member(String suratId, String deviceId) =>
      (db.select(db.channelMembers)..where(
            (m) => m.channelId.equals(suratId) & m.deviceId.equals(deviceId),
          ))
          .getSingleOrNull();

  Future<Channel?> channel(String suratId) => (db.select(
    db.channels,
  )..where((c) => c.id.equals(suratId))).getSingleOrNull();

  Future<Message> message(String id) =>
      (db.select(db.messages)..where((m) => m.id.equals(id))).getSingle();

  /// The event queued for [to], opened with [to]'s box key.
  Future<({String path, Envelope env, SuratEvent event})> queuedFor(
    Side to,
    String messageId,
  ) async {
    final row =
        await (db.select(db.deliveries)..where(
              (d) =>
                  d.messageId.equals(messageId) &
                  d.recipientDeviceId.equals(to.id),
            ))
            .getSingle();
    final json = jsonDecode(row.envelopeJson) as Map;
    final env = Envelope.fromJson(
      (json['payload'] as Map).cast<String, dynamic>(),
    );
    final plain = await open(
      env.sealed!,
      recipientBox: to.keys.box,
      aad: env.aad,
    );
    return (
      path: json['path'] as String,
      env: env,
      event: SuratEvent.fromJson(jsonDecode(utf8.decode(plain)) as Map),
    );
  }

  /// Stores an event from another Mac as Task 7 will, without the network.
  Future<void> storeIncoming(
    String suratId, {
    required Side from,
    required String hlc,
    required SuratEvent event,
  }) => db
      .into(db.messages)
      .insert(
        MessagesCompanion.insert(
          id: 'in-$hlc-${from.name}',
          channelId: suratId,
          kind: 'event',
          fromDeviceId: from.id,
          sentAt: now,
          hlc: Value(hlc),
          seq: const Value(0),
          body: Value(jsonEncode(event.toJson())),
          direction: 'in',
          status: 'read',
          createdAt: now,
        ),
      );

  /// My peer row for [other], as the peer server hands it to a route.
  Future<Peer> peerOf(Side other) => (db.select(
    db.peers,
  )..where((p) => p.deviceId.equals(other.id))).getSingle();

  /// [event] from me, sealed for [to] the way a published event travels.
  Future<Envelope> sealFor(
    Side to,
    String suratId,
    SuratEvent event, {
    required String id,
    required String hlc,
  }) async {
    Envelope envelope(SealedEnvelope? sealed) => Envelope(
      id: id,
      channelId: suratId,
      kind: 'event',
      from: this.id,
      sentAt: now,
      hlc: hlc,
      seq: 0,
      sealed: sealed,
    );
    return envelope(
      await seal(
        utf8.encode(jsonEncode(event.toJson())),
        recipientBoxPub: to.keys.boxPub,
        aad: envelope(null).aad,
      ),
    );
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);
