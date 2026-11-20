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
    this.history = false,
  });

  final String id;
  final String channelId;
  final String kind;
  final String from;
  final int sentAt;
  final String hlc;
  final int seq;
  final String? replyTo;

  /// Null for a locked placeholder (a message sent before the recipient
  /// joined; only its header is shared).
  final SealedEnvelope? sealed;

  /// True when this is a backfill of earlier history, not live traffic.
  final bool history;

  /// Binds the cleartext header to the ciphertext: any change fails to open.
  /// Messages keep the Phase 1 string so 1.0.x peers still open them; events
  /// add their kind.
  List<int> get aad => utf8.encode(
    kind == 'message'
        ? '$id|$channelId|$from|$hlc|$seq'
        : '$id|$channelId|$kind|$from|$hlc|$seq',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'kind': kind,
    'from': from,
    'sentAt': sentAt,
    'hlc': hlc,
    'seq': seq,
    if (replyTo != null) 'replyTo': replyTo,
    if (history) 'history': true,
    'sealed': sealed?.toJson(),
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
    history: j['history'] as bool? ?? false,
    sealed: j['sealed'] == null
        ? null
        : SealedEnvelope.fromJson((j['sealed'] as Map).cast<String, dynamic>()),
  );
}
