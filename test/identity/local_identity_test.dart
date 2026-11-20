import 'dart:io';

import 'package:agent_relay/config/app_config.dart';
import 'package:agent_relay/identity/local_identity.dart';
import 'package:agent_relay/identity/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await tempDir('identity'));
  tearDown(() => dir.delete(recursive: true));

  AppConfig config(String prefix) => AppConfig(
    dataDir: dir,
    peerPort: 1,
    localPort: 2,
    keychainPrefix: prefix,
  );

  test('load returns null before setup', () async {
    expect(
      await LocalIdentity.load(config('p'), InMemorySecretStore()),
      isNull,
    );
  });

  test('identity created once and reloaded with same device id', () async {
    final secrets = InMemorySecretStore();
    final created = await LocalIdentity.create(
      config('p'),
      secrets,
      personName: 'Irfan',
      deviceName: 'MacBook Pro',
    );
    final loaded = await LocalIdentity.load(config('p'), secrets);
    expect(loaded!.deviceId, created.deviceId);
    expect(loaded.personName, 'Irfan');
    expect(loaded.deviceName, 'MacBook Pro');
    expect(loaded.certFingerprint, created.certFingerprint);
    expect(created.certFingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(File(loaded.certPath).existsSync(), isTrue);
  });

  test('separate secret prefixes give separate identities', () async {
    final secrets = InMemorySecretStore();
    await LocalIdentity.create(
      config('a'),
      secrets,
      personName: 'Irfan',
      deviceName: 'A',
    );
    expect(await LocalIdentity.load(config('b'), secrets), isNull);
    expect(secrets.keys, everyElement(startsWith('a.')));
  });
}
