import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/messaging/relay_routes.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:agent_relay/surat/surat_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../support/fixtures.dart';
import '../support/surat_side.dart';

void main() {
  late RelayDatabase db;
  late MessageService svc;
  late Peer stranger;

  setUp(() async {
    db = memoryDb();
    final me = await IdentityKeys.generate();
    svc = MessageService(
      db: db,
      myDeviceId: deviceIdFor(me.signPub, me.boxPub),
      myBox: me.box,
      clock: HlcClock(nowMs: () => 1),
    );
    final other = await IdentityKeys.generate();
    await insertPeer(db, other);
    stranger = await db.select(db.peers).getSingle();
  });
  tearDown(() => db.close());

  Request post(String path, Object body) =>
      Request('POST', Uri.parse('https://mac$path'), body: jsonEncode(body));

  test('deliver from a non-member is 403 not_a_member', () async {
    final routes = relayRoutes(svc);
    final res = await routes['/relay/deliver']!(
      post('/relay/deliver', {
        'id': 'm1',
        'channelId': 'nope',
        'kind': 'message',
        'from': stranger.deviceId,
        'sentAt': 1,
        'hlc': '0000000000001-00000',
        'seq': 1,
        'sealed': {'eph': '', 'nonce': '', 'ct': '', 'mac': ''},
      }),
      stranger,
    );
    expect(res.statusCode, 403);
    expect(jsonDecode(await res.readAsString()), {'error': 'not_a_member'});
  });

  test("a contact's delivery into the closed private channel is refused with 401 untrusted", () async {
    await (db.update(db.peers))
        .write(const PeersCompanion(trust: Value('surat_contact')));
    final contact = await db.select(db.peers).getSingle();
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            id: 'p1',
            kind: 'private',
            createdAt: 1,
            closedAt: const Value(5),
          ),
        );
    for (final id in [svc.myDeviceId, contact.deviceId]) {
      await db
          .into(db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: 'p1',
              deviceId: id,
              joinedHlc: '0000000000000-00000',
            ),
          );
    }
    final res = await relayRoutes(svc)['/relay/deliver']!(
      post('/relay/deliver', {
        'id': 'm1',
        'channelId': 'p1',
        'kind': 'message',
        'from': contact.deviceId,
        'sentAt': 1,
        'hlc': '0000000000001-00000',
        'seq': 1,
        'sealed': {'eph': '', 'nonce': '', 'ct': '', 'mac': ''},
      }),
      contact,
    );
    expect(res.statusCode, 401);
    expect(jsonDecode(await res.readAsString()), {'error': 'untrusted'});
  });

  test(
    'a contact cannot deliver into an open private channel either',
    () async {
      await (db.update(db.peers))
          .write(const PeersCompanion(trust: Value('surat_contact')));
      final contact = await db.select(db.peers).getSingle();
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(id: 'p2', kind: 'private', createdAt: 1),
          );
      final res = await relayRoutes(svc)['/relay/deliver']!(
        post('/relay/deliver', {
          'id': 'm2',
          'channelId': 'p2',
          'kind': 'message',
          'from': contact.deviceId,
          'sentAt': 1,
          'hlc': '0000000000001-00000',
          'seq': 1,
          'sealed': {'eph': '', 'nonce': '', 'ct': '', 'mac': ''},
        }),
        contact,
      );
      expect(res.statusCode, 401);
    },
  );

  test('malformed deliver body is 400', () async {
    final res = await relayRoutes(svc)['/relay/deliver']!(
      post('/relay/deliver', {'x': 1}),
      stranger,
    );
    expect(res.statusCode, 400);
  });

  test('/relay/deliver returns 400 on a BadEnvelope instead of 500', () async {
    final channel = 'p1';
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(id: channel, kind: 'private', createdAt: 1),
        );
    for (final id in [svc.myDeviceId, stranger.deviceId]) {
      await db
          .into(db.channelMembers)
          .insert(
            ChannelMembersCompanion.insert(
              channelId: channel,
              deviceId: id,
              joinedHlc: '0000000000000-00000',
            ),
          );
    }
    final res = await relayRoutes(svc)['/relay/deliver']!(
      post('/relay/deliver', {
        'id': 'm1',
        'channelId': channel,
        'kind': 'message',
        'from': stranger.deviceId,
        'sentAt': 1,
        'hlc': 'not-a-stamp',
        'seq': 1,
        'sealed': {'eph': '', 'nonce': '', 'ct': '', 'mac': ''},
      }),
      stranger,
    );
    expect(res.statusCode, 400);
    expect(jsonDecode(await res.readAsString()), {'error': 'bad_envelope'});
  });

  test('/relay/deliver takes no event envelopes', () async {
    final res = await relayRoutes(svc)['/relay/deliver']!(
      post('/relay/deliver', {
        'id': 'e1',
        'channelId': 'nope',
        'kind': 'event',
        'from': stranger.deviceId,
        'sentAt': 1,
        'hlc': '0000000000001-00000',
        'seq': 0,
        'sealed': {'eph': '', 'nonce': '', 'ct': '', 'mac': ''},
      }),
      stranger,
    );
    expect(res.statusCode, 400);
    expect(jsonDecode(await res.readAsString()), {'error': 'bad_envelope'});
  });

  test('receipt for an unknown message is 404', () async {
    final res = await relayRoutes(svc)['/relay/receipt']!(
      post('/relay/receipt', {'messageId': 'm', 'kind': 'seen', 'at': 1}),
      stranger,
    );
    expect(res.statusCode, 404);
  });

  group('/relay/event', () {
    late Side alice, bob, dave;
    late String suratId, createId;

    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    setUp(() async {
      now = 1700000000000;
      alice = await Side.make('Alice');
      bob = await Side.make('Bob');
      dave = await Side.make('Dave');
      await alice.pair(bob);
      await bob.pair(alice);
      await bob.pair(dave);
      createId = await alice.surat.draftCreate('Trip', [bob.id]);
      await alice.messages.approve(createId);
      suratId = (await alice.message(createId)).channelId;
    });
    tearDown(() async {
      for (final s in [alice, bob, dave]) {
        await s.db.close();
      }
    });

    Future<(int, String)> call(Side from, Map<String, dynamic> payload) async {
      final res = await relayRoutes(bob.messages, surat: bob.surat)[eventPath]!(
        post(eventPath, payload),
        await bob.peerOf(from),
      );
      return (res.statusCode, await res.readAsString());
    }

    test('an event is 200 received, then 200 duplicate', () async {
      final q = await alice.queuedFor(bob, createId);
      expect(await call(alice, q.env.toJson()), (
        200,
        jsonEncode({'received': true, 'duplicate': false}),
      ));
      expect(await call(alice, q.env.toJson()), (
        200,
        jsonEncode({'received': true, 'duplicate': true}),
      ));
      expect((await bob.member(suratId, bob.id))!.state, 'invited');
    });

    test('an event from outside the surat is 403 not_a_member', () async {
      await call(alice, (await alice.queuedFor(bob, createId)).env.toJson());
      final env = await dave.sealFor(
        bob,
        suratId,
        const RenameEvent('x'),
        id: 'd1',
        hlc: Hlc(now, 1).encode(),
      );
      expect(await call(dave, env.toJson()), (
        403,
        jsonEncode({'error': 'not_a_member'}),
      ));
    });

    test(
      'a malformed body or a message envelope is 400 bad_envelope',
      () async {
        expect(await call(alice, {'x': 1}), (
          400,
          jsonEncode({'error': 'bad_envelope'}),
        ));
        final env = (await alice.queuedFor(bob, createId)).env.toJson()
          ..['kind'] = 'message';
        expect(await call(alice, env), (
          400,
          jsonEncode({'error': 'bad_envelope'}),
        ));
        expect(await bob.channel(suratId), isNull);
      },
    );
  });
}
