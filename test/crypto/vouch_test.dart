import 'package:agent_relay/crypto/identity_keys.dart';
import 'package:agent_relay/crypto/vouch.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MemberCard> _card(IdentityKeys k, {String? deviceId}) async =>
    MemberCard(
      deviceId: deviceId ?? deviceIdFor(k.signPub, k.boxPub),
      personName: 'Aisha',
      deviceName: 'Aisha MacBook',
      signPub: k.signPub,
      boxPub: k.boxPub,
      certFingerprint: 'ab' * 32,
    );

void main() {
  test('vouch verifies for the card it signed, fails for a changed boxPub or '
      'another surat id', () async {
    final inviter = await IdentityKeys.generate();
    final other = await IdentityKeys.generate();
    final card = await _card(await IdentityKeys.generate());
    final sig = await vouch(inviter.signing, 's1', card);

    expect(await checkVouch(inviter.signPub, 's1', card, sig), isTrue);
    expect(await checkVouch(inviter.signPub, 's2', card, sig), isFalse);
    expect(await checkVouch(other.signPub, 's1', card, sig), isFalse);

    final changed = MemberCard(
      deviceId: card.deviceId,
      personName: card.personName,
      deviceName: card.deviceName,
      signPub: card.signPub,
      boxPub: other.boxPub,
      certFingerprint: card.certFingerprint,
    );
    expect(await checkVouch(inviter.signPub, 's1', changed, sig), isFalse);
  });

  test('checkVouch fails when deviceId does not match the keys', () async {
    final inviter = await IdentityKeys.generate();
    final card = await _card(await IdentityKeys.generate(), deviceId: 'f' * 32);
    final sig = await vouch(inviter.signing, 's1', card);
    expect(await checkVouch(inviter.signPub, 's1', card, sig), isFalse);
  });

  test('MemberCard round-trips through JSON with base64 keys', () async {
    final card = await _card(await IdentityKeys.generate());
    final json = card.toJson();
    expect(json['signPub'], isA<String>());
    final back = MemberCard.fromJson(json);
    expect(back.signPub, card.signPub);
    expect(back.boxPub, card.boxPub);
    expect(back.toJson(), json);
  });
}
