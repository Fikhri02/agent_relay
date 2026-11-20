import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/discovery/discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  late RelayDatabase db;
  late String peerId;
  final seen = <String>[];

  setUp(() async {
    db = memoryDb();
    seen.clear();
    final k = await IdentityKeys.generate();
    peerId = deviceIdFor(k.signPub, k.boxPub);
    await insertPeer(db, k);
  });
  tearDown(() => db.close());

  test(
    'a resolved known peer updates its address and wakes its queue',
    () async {
      final d = DiscoveryService(
        db: db,
        myDeviceId: 'me',
        port: 8790,
        onPeerSeen: (id) async => seen.add(id),
      );
      final found = d.found.first;
      await d.handleResolved((
        deviceId: peerId,
        name: 'Xavier',
        host: 'xmbp.local',
        port: 8792,
      ));
      final p = await db.select(db.peers).getSingle();
      expect(p.lastAddress, 'xmbp.local');
      expect(p.lastPort, 8792);
      expect(seen, [peerId]);
      expect((await found).deviceId, peerId);
    },
  );

  test('an unknown Mac is announced for pairing but changes nothing', () async {
    final d = DiscoveryService(
      db: db,
      myDeviceId: 'me',
      port: 8790,
      onPeerSeen: (id) async => seen.add(id),
    );
    final found = d.found.first;
    await d.handleResolved((
      deviceId: 'stranger',
      name: 'Tommy',
      host: 't.local',
      port: 8790,
    ));
    expect((await found).name, 'Tommy');
    expect(seen, isEmpty);
    expect((await db.select(db.peers).getSingle()).lastAddress, isNull);
  });

  test('its own advertisement is ignored', () async {
    final d = DiscoveryService(
      db: db,
      myDeviceId: 'me',
      port: 8790,
      onPeerSeen: (id) async => seen.add(id),
    );
    var count = 0;
    d.found.listen((_) => count++);
    await d.handleResolved((
      deviceId: 'me',
      name: 'Irfan',
      host: 'i.local',
      port: 8790,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(count, 0);
  });

  test('advertised name tells Macs apart', () {
    expect(
      advertisedName('Xavier', "Xavier's MacBook Pro"),
      "Xavier (Xavier's MacBook Pro)",
    );
  });

  test('advertised name splits back into person and device', () {
    expect(splitAdvertisedName("Xavier (Xavier's MacBook Pro)"), (
      'Xavier',
      "Xavier's MacBook Pro",
    ));
    expect(splitAdvertisedName('Agent Relay'), ('Agent Relay', 'Agent Relay'));
  });
}
