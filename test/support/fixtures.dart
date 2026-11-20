import 'dart:io';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/data/relay_database.dart';
import 'package:agent_relay/identity/tls_cert_manager.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

RelayDatabase memoryDb() => RelayDatabase(NativeDatabase.memory());

Future<Directory> tempDir(String name) =>
    Directory.systemTemp.createTemp('agent_relay_$name');

/// A real self-signed certificate (openssl), like the app makes.
Future<CertResult> realCert(Directory dir) async {
  await dir.create(recursive: true);
  return TlsCertManager.generateCert(dir.path);
}

Future<void> insertPeer(
  RelayDatabase db,
  IdentityKeys keys, {
  String trust = 'paired',
  String fingerprint = 'fp',
  String name = 'Xavier',
}) => db
    .into(db.peers)
    .insert(
      PeersCompanion.insert(
        deviceId: deviceIdFor(keys.signPub, keys.boxPub),
        personName: name,
        deviceName: "$name's Mac",
        signPub: Uint8List.fromList(keys.signPub),
        boxPub: Uint8List.fromList(keys.boxPub),
        certFingerprint: fingerprint,
        trust: trust,
        pairedAt: 1,
      ),
    );
