import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/identity/local_identity.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/pairing/pairing_service.dart';
import 'package:agent_relay/pairing/pairing_window.dart';
import 'package:agent_relay/peer/peer_client.dart';
import 'package:agent_relay/peer/peer_server.dart';
import 'package:agent_relay/peer/server_bootstrap.dart';

import 'fixtures.dart';

/// A pairing-capable instance on 127.0.0.1 with its own data dir, for tests.
class TestNode {
  TestNode._(
    this.dir,
    this.me,
    this.db,
    this.server,
    this.pairing,
    this.client,
    this.window,
  );

  final Directory dir;
  final LocalIdentity me;
  final RelayDatabase db;
  final ServerBootstrap server;
  final PairingService pairing;
  final PeerClient client;
  final PairingWindow window;

  int get port => server.boundPort;
  PeerTarget get target =>
      (host: '127.0.0.1', port: port, pinnedFingerprint: null);

  static Future<TestNode> start(
    String name, {
    DateTime Function()? clock,
  }) async {
    final dir = await tempDir(name);
    final config = AppConfig(
      dataDir: dir,
      peerPort: 0,
      localPort: 0,
      keychainPrefix: name,
    );
    final me = await LocalIdentity.create(
      config,
      InMemorySecretStore(),
      personName: name,
      deviceName: '$name Mac',
    );
    final db = memoryDb();
    final window = PairingWindow(clock: clock);
    final server = ServerBootstrap(
      certPath: me.certPath,
      keyPath: me.keyPath,
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    late PairingService pairing;
    final client = PeerClient(me, relayPort: 0);
    pairing = PairingService(
      db: db,
      me: me,
      client: client,
      window: window,
      clock: HlcClock(nowMs: () => DateTime.now().millisecondsSinceEpoch),
      myPort: () => server.boundPort,
    );
    await server.start(
      handler: PeerServer(db: db, pairing: pairing).handler,
    );
    return TestNode._(dir, me, db, server, pairing, client, window);
  }

  Future<void> stop() async {
    await server.stop();
    await db.close();
    await dir.delete(recursive: true);
  }
}
