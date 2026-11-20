import 'dart:convert';

import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/request_signer.dart';
import 'package:agent_relay/crypto/sealed_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identity keys', () {
    test('device id is stable and 32 hex chars', () async {
      final k = await IdentityKeys.generate();
      final id = deviceIdFor(k.signPub, k.boxPub);
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      final s = await k.seeds();
      final k2 = await IdentityKeys.fromSeeds(
        signSeed: s.signSeed,
        boxSeed: s.boxSeed,
      );
      expect(deviceIdFor(k2.signPub, k2.boxPub), id);
    });

    test('two generated identities differ', () async {
      final a = await IdentityKeys.generate();
      final b = await IdentityKeys.generate();
      expect(
        deviceIdFor(a.signPub, a.boxPub),
        isNot(deviceIdFor(b.signPub, b.boxPub)),
      );
    });
  });

  group('sealed box', () {
    test('seal then open round-trips; wrong key or aad fails', () async {
      final bob = await IdentityKeys.generate();
      final eve = await IdentityKeys.generate();
      final e = await seal(
        utf8.encode('hello'),
        recipientBoxPub: bob.boxPub,
        aad: utf8.encode('m1'),
      );
      expect(
        utf8.decode(
          await open(e, recipientBox: bob.box, aad: utf8.encode('m1')),
        ),
        'hello',
      );
      await expectLater(
        open(e, recipientBox: eve.box, aad: utf8.encode('m1')),
        throwsA(isA<SealOpenException>()),
      );
      await expectLater(
        open(e, recipientBox: bob.box, aad: utf8.encode('m2')),
        throwsA(isA<SealOpenException>()),
      );
    });

    test('two seals of the same text differ', () async {
      final bob = await IdentityKeys.generate();
      final e1 = await seal(
        utf8.encode('same'),
        recipientBoxPub: bob.boxPub,
        aad: const [],
      );
      final e2 = await seal(
        utf8.encode('same'),
        recipientBoxPub: bob.boxPub,
        aad: const [],
      );
      expect(e1.ct, isNot(e2.ct));
      expect(e1.eph, isNot(e2.eph));
    });

    test('envelope survives a JSON round trip', () async {
      final bob = await IdentityKeys.generate();
      final e = await seal(
        utf8.encode('x'),
        recipientBoxPub: bob.boxPub,
        aad: const [],
      );
      final back = SealedEnvelope.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
      );
      expect(
        utf8.decode(await open(back, recipientBox: bob.box, aad: const [])),
        'x',
      );
    });

    test('tampered ciphertext fails to open', () async {
      final bob = await IdentityKeys.generate();
      final e = await seal(
        utf8.encode('hello'),
        recipientBoxPub: bob.boxPub,
        aad: const [],
      );
      final bytes = base64.decode(e.ct)..[0] ^= 1;
      final bad = SealedEnvelope(
        eph: e.eph,
        nonce: e.nonce,
        ct: base64.encode(bytes),
        mac: e.mac,
      );
      await expectLater(
        open(bad, recipientBox: bob.box, aad: const []),
        throwsA(isA<SealOpenException>()),
      );
    });
  });

  group('request signing', () {
    test('signing string format', () {
      expect(
        signingString(
          method: 'POST',
          path: '/x',
          timestampMs: 5,
          body: const [],
        ),
        'POST\n/x\n5\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('signature verifies and rejects tampering', () async {
      final k = await IdentityKeys.generate();
      final s = signingString(
        method: 'POST',
        path: '/relay/deliver',
        timestampMs: 1,
        body: utf8.encode('{}'),
      );
      final sig = await signRequest(k.signing, s);
      expect(await verifyRequest(k.signPub, s, sig), isTrue);
      final s2 = signingString(
        method: 'POST',
        path: '/relay/deliver',
        timestampMs: 1,
        body: utf8.encode('{"x":1}'),
      );
      expect(await verifyRequest(k.signPub, s2, sig), isFalse);
    });

    test('garbage signature is false, not a throw', () async {
      final k = await IdentityKeys.generate();
      expect(await verifyRequest(k.signPub, 'x', 'not-base64!!'), isFalse);
    });
  });
}
