import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'identity_keys.dart';
import 'request_signer.dart';

/// A device's identity as other surat members hold it: who it is and how to
/// reach and seal to it. Keys travel as standard base64.
class MemberCard {
  const MemberCard({
    required this.deviceId,
    required this.personName,
    required this.deviceName,
    required this.signPub,
    required this.boxPub,
    required this.certFingerprint,
    this.address,
    this.port,
    this.joinedHlc,
  });

  final String deviceId;
  final String personName;
  final String deviceName;
  final List<int> signPub;
  final List<int> boxPub;
  final String certFingerprint;
  final String? address;
  final int? port;
  final String? joinedHlc;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'personName': personName,
    'deviceName': deviceName,
    'signPub': base64Encode(signPub),
    'boxPub': base64Encode(boxPub),
    'certFingerprint': certFingerprint,
    'address': address,
    'port': port,
    'joinedHlc': joinedHlc,
  };

  /// Throws [FormatException] when a required field is missing or mistyped.
  static MemberCard fromJson(Map json) {
    try {
      return MemberCard(
        deviceId: json['deviceId'] as String,
        personName: json['personName'] as String,
        deviceName: json['deviceName'] as String,
        signPub: base64Decode(json['signPub'] as String),
        boxPub: base64Decode(json['boxPub'] as String),
        certFingerprint: json['certFingerprint'] as String,
        address: json['address'] as String?,
        port: json['port'] as int?,
        joinedHlc: json['joinedHlc'] as String?,
      );
    } on TypeError {
      throw const FormatException('bad member card');
    }
  }
}

String _vouchString(String suratId, MemberCard card) =>
    'surat-vouch|$suratId|${card.deviceId}|${base64Encode(card.signPub)}'
    '|${base64Encode(card.boxPub)}|${card.certFingerprint}';

/// The inviter signs "this card belongs to this device" for one surat.
Future<String> vouch(
  SimpleKeyPair inviterSigning,
  String suratId,
  MemberCard card,
) => signRequest(inviterSigning, _vouchString(suratId, card));

Future<bool> checkVouch(
  List<int> inviterSignPub,
  String suratId,
  MemberCard card,
  String sig,
) async {
  if (deviceIdFor(card.signPub, card.boxPub) != card.deviceId) return false;
  return verifyRequest(inviterSignPub, _vouchString(suratId, card), sig);
}
