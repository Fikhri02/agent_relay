import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/peer/trust.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

Future<void> surat(
  RelayDatabase db,
  String id,
  Map<String, String> states, {
  int? closedAt,
}) async {
  await db
      .into(db.channels)
      .insert(
        ChannelsCompanion.insert(
          id: id,
          kind: 'surat',
          createdAt: 1,
          closedAt: Value(closedAt),
        ),
      );
  for (final e in states.entries) {
    await db
        .into(db.channelMembers)
        .insert(
          ChannelMembersCompanion.insert(
            channelId: id,
            deviceId: e.key,
            joinedHlc: '0000000000000-00000',
            state: Value(e.value),
          ),
        );
  }
}

MemberCard cardOf(IdentityKeys k, {String fp = 'fp1', String name = 'Tommy'}) =>
    MemberCard(
      deviceId: deviceIdFor(k.signPub, k.boxPub),
      personName: name,
      deviceName: "$name's Mac",
      signPub: k.signPub,
      boxPub: k.boxPub,
      certFingerprint: fp,
      address: '10.0.0.7',
      port: 8790,
    );

void main() {
  late RelayDatabase db;
  late IdentityKeys tommy;
  late String tommyId;
  const me = 'me-device';

  setUp(() async {
    db = memoryDb();
    tommy = await IdentityKeys.generate();
    tommyId = deviceIdFor(tommy.signPub, tommy.boxPub);
  });
  tearDown(() => db.close());

  Future<Peer> peer() => db.select(db.peers).getSingle();

  test('canTalk is true for paired and surat_contact only', () async {
    final k = await IdentityKeys.generate();
    for (final t in ['paired', 'surat_contact', 'mismatch', 'unpaired']) {
      await db.delete(db.peers).go();
      await insertPeer(db, k, trust: t);
      expect(canTalk(await peer()), t == 'paired' || t == 'surat_contact');
    }
  });

  test(
    'sharesSurat needs an open surat with both as member or invited',
    () async {
      expect(await sharesSurat(db, me, tommyId), isFalse);
      await surat(db, 's1', {me: 'member', tommyId: 'left'});
      expect(await sharesSurat(db, me, tommyId), isFalse);
      await surat(db, 's2', {me: 'member', tommyId: 'member'}, closedAt: 5);
      expect(await sharesSurat(db, me, tommyId), isFalse);
      await surat(db, 's3', {me: 'invited', tommyId: 'member'});
      expect(await sharesSurat(db, me, tommyId), isTrue);
    },
  );

  test('addOrRefreshContact inserts a contact from the card', () async {
    await addOrRefreshContact(db, cardOf(tommy), nowMs: 99);
    final p = await peer();
    expect(p.trust, trustSuratContact);
    expect(p.certFingerprint, 'fp1');
    expect(p.lastAddress, '10.0.0.7');
    expect(p.lastPort, 8790);
    expect(p.pairedAt, 99);
  });

  test('addOrRefreshContact never downgrades paired', () async {
    await insertPeer(db, tommy, fingerprint: 'orig', name: 'Orig');
    await addOrRefreshContact(db, cardOf(tommy, fp: 'other'), nowMs: 99);
    final p = await peer();
    expect(p.trust, 'paired');
    expect(p.certFingerprint, 'orig');
    expect(p.personName, 'Orig');
    expect(p.pairedAt, 1);
  });

  test('a changed key or fingerprint re-vouches the contact', () async {
    await addOrRefreshContact(db, cardOf(tommy), nowMs: 1);
    await addOrRefreshContact(db, cardOf(tommy, fp: 'fp2'), nowMs: 2);
    final p = await peer();
    expect(p.trust, trustSuratContact);
    expect(p.certFingerprint, 'fp2');
    expect(p.pairedAt, 1);
  });

  test(
    'forgetLoneContacts removes only contacts with no shared surat',
    () async {
      final other = await IdentityKeys.generate();
      final otherId = deviceIdFor(other.signPub, other.boxPub);
      final paired = await IdentityKeys.generate();
      await addOrRefreshContact(db, cardOf(tommy), nowMs: 1);
      await addOrRefreshContact(db, cardOf(other, name: 'Other'), nowMs: 1);
      await insertPeer(db, paired);
      await surat(db, 's1', {me: 'member', tommyId: 'member'});
      await forgetLoneContacts(db, me);
      final ids = (await db.select(db.peers).get()).map((p) => p.deviceId);
      expect(ids, contains(tommyId));
      expect(ids, isNot(contains(otherId)));
      expect(ids, contains(deviceIdFor(paired.signPub, paired.boxPub)));
    },
  );

  test('a lone contact with a queued delivery is kept until it goes', () async {
    await addOrRefreshContact(db, cardOf(tommy), nowMs: 1);
    await db
        .into(db.deliveries)
        .insert(
          DeliveriesCompanion.insert(
            messageId: 'leave-1',
            recipientDeviceId: tommyId,
            envelopeJson: '{}',
            status: 'queued',
            nextAttemptAt: 1,
            createdAt: 1,
          ),
        );
    await forgetLoneContacts(db, me);
    expect(await db.select(db.peers).get(), hasLength(1));
    await db
        .update(db.deliveries)
        .write(const DeliveriesCompanion(status: Value('delivered')));
    await forgetLoneContacts(db, me);
    expect(await db.select(db.peers).get(), isEmpty);
  });
}
