import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;

import '../config/app_config.dart';
import '../data/relay_database.dart';
import '../discovery/discovery_service.dart';
import '../identity/local_identity.dart';
import '../identity/secret_store.dart';
import '../local_api/local_server.dart';
import '../messaging/delivery_worker.dart';
import '../messaging/message_service.dart';
import '../messaging/relay_routes.dart';
import '../ordering/hlc.dart';
import '../pairing/pairing_service.dart';
import '../pairing/pairing_window.dart';
import '../peer/peer_client.dart';
import '../peer/peer_server.dart';
import '../peer/server_bootstrap.dart';
import '../surat/surat_service.dart';
import 'notifier.dart';

/// One running Agent Relay: database, identity, peer server, local API,
/// delivery worker and discovery. Services exist once [identity] is set,
/// either loaded at start or created by [setup].
class RelayNode {
  RelayNode._(
    this.config,
    this.db,
    this._secrets,
    this.notifier,
    this._discoveryOn,
    this._bindAddress,
    this._workerTick,
  );

  final AppConfig config;
  final RelayDatabase db;
  final SecretStore _secrets;
  final Notifier notifier;
  final bool _discoveryOn;
  final InternetAddress _bindAddress;
  final Duration? _workerTick;

  LocalIdentity? identity;
  late PairingService pairing;
  late MessageService messages;
  late SuratService surat;
  late DeliveryWorker worker;
  late LocalServer local;
  late ServerBootstrap _peerServer;
  DiscoveryService? discovery;
  final _ready = Completer<void>();

  /// Completes once the services are up (after load or [setup]).
  Future<void> get ready => _ready.future;
  int get peerPort => _peerServer.boundPort;

  static Future<RelayNode> start(
    AppConfig config, {
    SecretStore secrets = const KeychainSecretStore(),
    Notifier? notifier,
    bool discovery = true,
    InternetAddress? bindAddress,
    Duration? workerTick = const Duration(seconds: 5),
  }) async {
    await config.dataDir.create(recursive: true);
    final db = RelayDatabase.open(File('${config.dataDir.path}/relay.sqlite'));
    final node = RelayNode._(
      config,
      db,
      secrets,
      notifier ?? RecordingNotifier(),
      discovery,
      bindAddress ?? InternetAddress.anyIPv4,
      workerTick,
    );
    final existing = await LocalIdentity.load(config, secrets);
    if (existing != null) await node._bringUp(existing);
    return node;
  }

  /// First run: create this Mac's identity, then start the services.
  Future<void> setup({
    required String personName,
    required String deviceName,
  }) async {
    if (identity != null) return;
    final created = await LocalIdentity.create(
      config,
      _secrets,
      personName: personName,
      deviceName: deviceName,
    );
    await _bringUp(created);
  }

  Future<void> _bringUp(LocalIdentity me) async {
    identity = me;
    final latest =
        await (db.select(db.messages)
              ..where((m) => m.hlc.isNotNull())
              ..orderBy([(m) => OrderingTerm.desc(m.hlc)])
              ..limit(1))
            .getSingleOrNull();
    final clock = HlcClock(
      nowMs: () => DateTime.now().millisecondsSinceEpoch,
      last: latest == null ? null : Hlc.decode(latest.hlc!),
    );

    _peerServer = ServerBootstrap(
      certPath: me.certPath,
      keyPath: me.keyPath,
      port: config.peerPort,
      address: _bindAddress,
    );
    final client = PeerClient(me, relayPort: config.peerPort);
    pairing = PairingService(
      db: db,
      me: me,
      client: client,
      window: PairingWindow(),
      clock: clock,
      myPort: () => peerPort,
    );
    messages = MessageService(
      db: db,
      myDeviceId: me.deviceId,
      myBox: me.keys.box,
      clock: clock,
    );
    surat = SuratService(
      db: db,
      messages: messages,
      keys: me.keys,
      me: me,
      clock: clock,
      myPort: () => peerPort,
    );
    messages
      ..publishEvent = surat.publish
      ..dropEvent = surat.dropDraft;
    worker = DeliveryWorker(
      db: db,
      transport: client,
      messages: messages,
      notifier: notifier,
      onUnpaired: pairing.markUnpaired,
      onDraftsExpired: (expired) async {
        for (final d in expired) {
          await surat.dropDraft(d);
        }
      },
      keepAlive: const Duration(seconds: 60),
    );
    await _peerServer.start(
      handler: PeerServer(
        db: db,
        pairing: pairing,
        paired: relayRoutes(messages, surat: surat),
        onPeerSeen: (id) => unawaited(worker.peerSeen(id)),
      ).handler,
    );
    client.relayPort = peerPort;

    local = LocalServer(
      config: config,
      db: db,
      messages: messages,
      me: (
        deviceId: me.deviceId,
        personName: me.personName,
        deviceName: me.deviceName,
      ),
      deliverNow: worker.runOnce,
    );
    await local.start();
    if (_workerTick != null) worker.start(tick: _workerTick);
    if (_discoveryOn) {
      discovery = DiscoveryService(
        db: db,
        myDeviceId: me.deviceId,
        port: peerPort,
        onPeerSeen: worker.peerSeen,
        name: advertisedName(me.personName, me.deviceName),
      );
      await discovery!.start();
    }
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<void> stop() async {
    if (identity != null) {
      await worker.stop();
      await discovery?.stop();
      await local.stop();
      await _peerServer.stop();
    }
    await db.close();
  }
}
