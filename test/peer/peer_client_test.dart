import 'dart:convert';
import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/identity/local_identity.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/peer/peer_client.dart';
import 'package:agent_relay/peer/server_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../support/fixtures.dart';

void main() {
  late Directory dir;
  late LocalIdentity me;
  late ServerBootstrap server;
  late String serverFp;
  Map<String, String>? lastHeaders;

  setUpAll(() async {
    dir = await tempDir('client');
    me = await LocalIdentity.create(
      AppConfig(
        dataDir: Directory('${dir.path}/me'),
        peerPort: 1,
        localPort: 2,
        keychainPrefix: 'me',
      ),
      InMemorySecretStore(),
      personName: 'Irfan',
      deviceName: 'A',
    );
    final cert = await realCert(Directory('${dir.path}/srv'));
    serverFp = cert.fingerprint;
    server = ServerBootstrap(
      certPath: cert.certPath,
      keyPath: cert.keyPath,
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    await server.start(
      handler: (req) {
        lastHeaders = req.headers;
        if (req.url.path == 'old') return Response.notFound('Route not found');
        if (req.url.path == 'skew') {
          return Response(
            401,
            body: jsonEncode({
              'error': 'clock_skew',
              'serverTimeMs': 1000000 + 45000,
            }),
          );
        }
        return Response.ok(
          jsonEncode({'echo': req.url.path}),
          headers: {'content-type': 'application/json'},
        );
      },
    );
  });
  tearDownAll(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  PeerTarget target({String? pin}) =>
      (host: '127.0.0.1', port: server.boundPort, pinnedFingerprint: pin);

  test(
    'unpinned post returns the presented fingerprint and signs the request',
    () async {
      final c = PeerClient(me, relayPort: 8790, nowMs: () => 1000000);
      final res = await c.post(target(), '/pair/hello', {'a': 1});
      expect(res.status, 200);
      expect(res.json, {'echo': 'pair/hello'});
      expect(res.presentedFingerprint, serverFp);
      expect(lastHeaders!['x-device-id'], me.deviceId);
      expect(lastHeaders!['x-timestamp'], '1000000');
      expect(lastHeaders!['x-relay-port'], '8790');
      expect(lastHeaders!['x-signature'], isNotEmpty);
    },
  );

  test('pinned to the right fingerprint succeeds', () async {
    final c = PeerClient(me, relayPort: 8790);
    expect((await c.get(target(pin: serverFp), '/x')).status, 200);
  });

  test(
    'pinned client throws PeerIdentityMismatch on a different cert',
    () async {
      final c = PeerClient(me, relayPort: 8790);
      await expectLater(
        c.get(target(pin: 'ab' * 32), '/x'),
        throwsA(isA<PeerIdentityMismatch>()),
      );
    },
  );

  test('client maps clock_skew 401 to PeerClockSkew with skew', () async {
    final c = PeerClient(me, relayPort: 8790, nowMs: () => 1000000);
    await expectLater(
      c.post(target(pin: serverFp), '/skew', {}),
      throwsA(isA<PeerClockSkew>().having((e) => e.skewMs, 'skewMs', 45000)),
    );
  });

  test('a plain-text body (an older build\'s 404) is answered as {}, '
      'not as unreachable', () async {
    final c = PeerClient(me, relayPort: 8790);
    final res = await c.post(target(pin: serverFp), '/old', {});
    expect(res.status, 404);
    expect(res.json, isEmpty);
  });

  test('nothing listening throws PeerUnreachable', () async {
    final c = PeerClient(
      me,
      relayPort: 8790,
      timeout: const Duration(seconds: 2),
    );
    await expectLater(
      c.get((host: '127.0.0.1', port: 1, pinnedFingerprint: null), '/x'),
      throwsA(isA<PeerUnreachable>()),
    );
  });
}
