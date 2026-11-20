import 'dart:convert';

import '../crypto/sealed_box.dart';

/// The body of `POST /relay/deliver`: one message sealed for one recipient.
class Envelope {
  const Envelope({
    required this.id,
    required this.channelId,
    required this.kind,
    required this.from,
    required this.sentAt,
    required this.hlc,
    required this.seq,
    required this.sealed,
    this.replyTo,
  });

  final String id;
  final String channelId;
  final String kind;
  final String from;
  final int sentAt;
  final String hlc;
  final int seq;
  final String? replyTo;
  final SealedEnvelope sealed;

  /// Binds the cleartext header to the ciphertext: any change fails to open.
  List<int> get aad => utf8.encode('$id|$channelId|$from|$hlc|$seq');

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'kind': kind,
    'from': from,
    'sentAt': sentAt,
    'hlc': hlc,
    'seq': seq,
    if (replyTo != null) 'replyTo': replyTo,
    'sealed': sealed.toJson(),
  };

  factory Envelope.fromJson(Map<String, dynamic> j) => Envelope(
    id: j['id'] as String,
    channelId: j['channelId'] as String,
    kind: j['kind'] as String,
    from: j['from'] as String,
    sentAt: j['sentAt'] as int,
    hlc: j['hlc'] as String,
    seq: j['seq'] as int,
    replyTo: j['replyTo'] as String?,
    sealed: SealedEnvelope.fromJson(
      (j['sealed'] as Map).cast<String, dynamic>(),
    ),
  );
}
