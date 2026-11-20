import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/messaging/message_service.dart';
import 'package:agent_relay/messaging/relay_routes.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../support/fixtures.dart';

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

  test('malformed deliver body is 400', () async {
    final res = await relayRoutes(svc)['/relay/deliver']!(
      post('/relay/deliver', {'x': 1}),
      stranger,
    );
    expect(res.statusCode, 400);
  });

  test('receipt for an unknown message is 404', () async {
    final res = await relayRoutes(svc)['/relay/receipt']!(
      post('/relay/receipt', {'messageId': 'm', 'kind': 'seen', 'at': 1}),
      stranger,
    );
    expect(res.statusCode, 404);
  });
}
