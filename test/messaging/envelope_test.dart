import 'dart:convert';

import 'package:agent_relay/crypto/sealed_box.dart';
import 'package:agent_relay/messaging/envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Envelope make({String kind = 'message', SealedEnvelope? sealed}) => Envelope(
    id: 'm1',
    channelId: 'ch',
    kind: kind,
    from: 'dev',
    sentAt: 5,
    hlc: '0000000001000-00000',
    seq: 3,
    sealed: sealed,
    history: sealed == null,
  );

  test('envelope round-trips a placeholder and the history flag', () {
    final json =
        jsonDecode(jsonEncode(make().toJson())) as Map<String, dynamic>;
    expect(json['history'], isTrue);
    final back = Envelope.fromJson(json);
    expect(back.sealed, isNull);
    expect(back.history, isTrue);
    expect(back.id, 'm1');
    expect(back.seq, 3);
  });

  test('a sealed envelope without the history field reads as not history', () {
    final env = make(
      sealed: const SealedEnvelope(eph: 'a', nonce: 'b', ct: 'c', mac: 'd'),
    );
    final json = env.toJson()..remove('history');
    final back = Envelope.fromJson(json);
    expect(back.history, isFalse);
    expect(back.sealed, isNotNull);
  });

  test('aad of a message stays the Phase 1 string, an event adds its kind', () {
    expect(utf8.decode(make().aad), 'm1|ch|dev|0000000001000-00000|3');
    expect(
      utf8.decode(make(kind: 'event').aad),
      'm1|ch|event|dev|0000000001000-00000|3',
    );
  });
}
