import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:drift/drift.dart';

import '../data/relay_database.dart';
import '../peer/trust.dart';

typedef DiscoveredMac = ({String deviceId, String name, String host, int port});

const serviceType = '_agentrelay._tcp';

/// The Bonjour name, so the pairing list can tell Macs apart.
String advertisedName(String personName, String deviceName) =>
    '$personName ($deviceName)';

/// Splits [advertisedName] back into (person, device); the whole name is
/// both when it has no device part.
(String, String) splitAdvertisedName(String name) {
  final m = RegExp(r'^(.*) \((.*)\)$').firstMatch(name);
  return m == null ? (name, name) : (m.group(1)!, m.group(2)!);
}

/// Advertises this Mac and browses for others. A known peer found on the
/// network gets its address refreshed and its queue woken; every other Mac is
/// offered to the pairing screen.
class DiscoveryService {
  DiscoveryService({
    required this.db,
    required this.myDeviceId,
    required this.port,
    required this.onPeerSeen,
    this.name = 'Agent Relay',
  });

  final RelayDatabase db;
  final String myDeviceId;
  final int port;
  final String name;
  final Future<void> Function(String deviceId) onPeerSeen;
  final _found = StreamController<DiscoveredMac>.broadcast();
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  Stream<DiscoveredMac> get found => _found.stream;

  Future<void> start() async {
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: name,
        type: serviceType,
        port: port,
        attributes: {'deviceId': myDeviceId},
      ),
    );
    await _broadcast!.ready;
    await _broadcast!.start();

    final discovery = BonsoirDiscovery(type: serviceType);
    _discovery = discovery;
    await discovery.ready;
    _sub = discovery.eventStream?.listen((event) async {
      final service = event.service;
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound &&
          service != null) {
        await service.resolve(discovery.serviceResolver);
      }
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved &&
          service is ResolvedBonsoirService &&
          service.host != null) {
        final id = service.attributes['deviceId'];
        if (id == null) return;
        await handleResolved((
          deviceId: id,
          name: service.name,
          host: service.host!,
          port: service.port,
        ));
      }
    });
    await discovery.start();
  }

  /// One resolved advertisement (public for tests).
  Future<void> handleResolved(DiscoveredMac mac) async {
    if (mac.deviceId == myDeviceId) return;
    final peer = await (db.select(
      db.peers,
    )..where((p) => p.deviceId.equals(mac.deviceId))).getSingleOrNull();
    if (peer != null && canTalk(peer)) {
      await (db.update(
        db.peers,
      )..where((p) => p.deviceId.equals(mac.deviceId))).write(
        PeersCompanion(lastAddress: Value(mac.host), lastPort: Value(mac.port)),
      );
      await onPeerSeen(mac.deviceId);
    }
    _found.add(mac);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    if (_discovery != null && !_discovery!.isStopped) await _discovery!.stop();
    await _broadcast?.stop();
  }
}
