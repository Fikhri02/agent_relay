import 'dart:convert';
import 'dart:io';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/request_signer.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/peer/peer_auth_middleware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../support/fixtures.dart';

class _Conn implements HttpConnectionInfo {
  @override
  InternetAddress get remoteAddress => InternetAddress('10.0.0.9');
  @override
  int get remotePort => 55555;
  @override
  int get localPort => 8790;
}

const now = 1700000000000;

Future<Request> signed(
  IdentityKeys k, {
  String path = '/relay/deliver',
  String body = '{}',
  int ts = now,
  String? deviceId,
}) async {
  final sig = await signRequest(
    k.signing,
    signingString(
      method: 'POST',
      path: path,
      timestampMs: ts,
      body: utf8.encode(body),
    ),
  );
  return Request(
    'POST',
    Uri.parse('https://mac$path'),
    body: body,
    headers: {
      'x-device-id': deviceId ?? deviceIdFor(k.signPub, k.boxPub),
      'x-timestamp': '$ts',
      'x-signature': sig,
      'x-relay-port': '8792',
    },
    context: {'shelf.io.connection_info': _Conn()},
  );
}

void main() {
  late RelayDatabase db;
  late IdentityKeys xavier;
  final seen = <String>[];
  late Handler handler;

  setUp(() async {
    db = memoryDb();
    xavier = await IdentityKeys.generate();
    seen.clear();
    handler =
        peerAuthMiddleware(
          db: db,
          allowUnpaired: (p) => p.startsWith('/pair/'),
          nowMs: () => now,
          onPeerSeen: seen.add,
        )(
          (req) => Response.ok(
            'ok:${(req.context['peer'] as Peer?)?.personName ?? 'unpaired'}',
          ),
        );
  });
  tearDown(() => db.close());

  test('health needs no signature', () async {
    final res = await handler(Request('GET', Uri.parse('https://mac/health')));
    expect(res.statusCode, 200);
  });

  test('signed request from a paired peer passes and updates lastSeen/address/port', () async {
    await insertPeer(db, xavier);
    final res = await handler(await signed(xavier));
    expect(res.statusCode, 200);
    expect(await res.readAsString(), 'ok:Xavier');
    final p = await db.select(db.peers).getSingle();
    expect(p.lastAddress, '10.0.0.9');
    expect(p.lastPort, 8792);
    expect(p.lastSeenAt, now);
    expect(seen, [p.deviceId]);
  });

  test("a surat contact's signed request reaches a paired route", () async {
    await insertPeer(db, xavier, trust: 'surat_contact');
    final res = await handler(await signed(xavier));
    expect(res.statusCode, 200);
    expect(await res.readAsString(), 'ok:Xavier');
  });

  test("a surat contact's bad signature is denied", () async {
    await insertPeer(db, xavier, trust: 'surat_contact');
    final eve = await IdentityKeys.generate();
    final res = await handler(
      await signed(eve, deviceId: deviceIdFor(xavier.signPub, xavier.boxPub)),
    );
    expect(res.statusCode, 401);
  });

  test('unknown device is rejected 401 untrusted', () async {
    final res = await handler(await signed(xavier));
    expect(res.statusCode, 401);
    expect(jsonDecode(await res.readAsString()), {'error': 'untrusted'});
  });

  test('mismatch-trust peer is rejected', () async {
    await insertPeer(db, xavier, trust: 'mismatch');
    expect((await handler(await signed(xavier))).statusCode, 401);
  });

  test('signature by a different key is rejected', () async {
    await insertPeer(db, xavier);
    final eve = await IdentityKeys.generate();
    final req = await signed(
      eve,
      deviceId: deviceIdFor(xavier.signPub, xavier.boxPub),
    );
    final res = await handler(req);
    expect(res.statusCode, 401);
    expect(jsonDecode(await res.readAsString()), {'error': 'bad_signature'});
  });

  test(
    'signature older than 30 s returns clock_skew with serverTimeMs',
    () async {
      await insertPeer(db, xavier);
      final res = await handler(await signed(xavier, ts: now - 31000));
      expect(res.statusCode, 401);
      expect(jsonDecode(await res.readAsString()), {
        'error': 'clock_skew',
        'serverTimeMs': now,
      });
    },
  );

  test(
    'unpaired pairing path is checked against signPub in the body',
    () async {
      final body = jsonEncode({'signPub': base64.encode(xavier.signPub)});
      final res = await handler(
        await signed(xavier, path: '/pair/hello', body: body),
      );
      expect(res.statusCode, 200);
      expect(await res.readAsString(), 'ok:unpaired');
      final eve = await IdentityKeys.generate();
      final bad = await handler(
        await signed(eve, path: '/pair/hello', body: body),
      );
      expect(bad.statusCode, 401);
    },
  );

  test('unpaired request to a non-pairing path is rejected', () async {
    final body = jsonEncode({'signPub': base64.encode(xavier.signPub)});
    expect((await handler(await signed(xavier, body: body))).statusCode, 401);
  });

  test('a body over 512 KB is refused with 413 before it is read', () async {
    await insertPeer(db, xavier);
    final big = 'x' * (512 * 1024 + 1);
    final res = await handler(await signed(xavier, body: big));
    expect(res.statusCode, 413);
  });
}
