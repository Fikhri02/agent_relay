import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../crypto/request_signer.dart';
import '../identity/local_identity.dart';
import '../identity/tls_cert_manager.dart';

typedef PeerTarget = ({String host, int port, String? pinnedFingerprint});
typedef PeerResponse = ({
  int status,
  Map<String, dynamic> json,
  String? presentedFingerprint,
});

class PeerUnreachable implements Exception {
  const PeerUnreachable(this.cause);
  final Object cause;
  @override
  String toString() => 'peer unreachable: $cause';
}

class PeerIdentityMismatch implements Exception {
  const PeerIdentityMismatch(this.presented);
  final String presented;
  @override
  String toString() => 'peer certificate changed ($presented)';
}

class PeerClockSkew implements Exception {
  const PeerClockSkew(this.skewMs);

  /// Peer's clock minus ours.
  final int skewMs;
  @override
  String toString() => 'clocks differ by ${skewMs ~/ 1000} s';
}

/// What the delivery worker needs from the network (faked in tests).
abstract class PeerTransport {
  Future<PeerResponse> post(
    PeerTarget t,
    String path,
    Map<String, dynamic> body,
  );
}

/// Signed HTTPS calls to another Mac. With a pinned fingerprint, any other
/// certificate is refused; without one (pairing only) the presented one is
/// returned for the comparison code.
class PeerClient implements PeerTransport {
  PeerClient(
    this.me, {
    required this.relayPort,
    int Function()? nowMs,
    this.timeout = const Duration(seconds: 10),
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final LocalIdentity me;

  /// The port this Mac's peer server listens on, sent as `x-relay-port`.
  /// Set after binding when the configured port is 0.
  int relayPort;
  final Duration timeout;
  final int Function() _now;

  @override
  Future<PeerResponse> post(
    PeerTarget t,
    String path,
    Map<String, dynamic> body,
  ) => _send('POST', t, path, utf8.encode(jsonEncode(body)));

  Future<PeerResponse> get(PeerTarget t, String path) =>
      _send('GET', t, path, const []);

  Future<PeerResponse> _send(
    String method,
    PeerTarget t,
    String path,
    List<int> body,
  ) async {
    String? presented;
    var mismatch = false;
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, host, port) {
        presented = TlsCertManager.fingerprintOfDer(cert.der);
        if (t.pinnedFingerprint != null && presented != t.pinnedFingerprint) {
          mismatch = true;
          return false;
        }
        return true;
      };
    try {
      final ts = _now();
      final uri = Uri(scheme: 'https', host: t.host, port: t.port, path: path);
      final sig = await signRequest(
        me.keys.signing,
        signingString(
          method: method,
          path: uri.path,
          timestampMs: ts,
          body: body,
        ),
      );
      final req = await client.openUrl(method, uri).timeout(timeout);
      req.headers
        ..set('x-device-id', me.deviceId)
        ..set('x-timestamp', '$ts')
        ..set('x-signature', sig)
        ..set('x-relay-port', '$relayPort')
        ..contentType = ContentType.json;
      req.add(body);
      final res = await req.close().timeout(timeout);
      final text = await utf8.decodeStream(res).timeout(timeout);
      presented ??= res.certificate == null
          ? null
          : TlsCertManager.fingerprintOfDer(res.certificate!.der);
      final json = _jsonMap(text);
      if (res.statusCode == 401 && json['error'] == 'clock_skew') {
        throw PeerClockSkew((json['serverTimeMs'] as int) - ts);
      }
      return (
        status: res.statusCode,
        json: json,
        presentedFingerprint: presented,
      );
    } on PeerClockSkew {
      rethrow;
    } on Object catch (e) {
      if (mismatch) throw PeerIdentityMismatch(presented ?? '');
      throw PeerUnreachable(e);
    } finally {
      client.close(force: true);
    }
  }

  /// The body as a JSON object; anything else (empty, plain text such as an
  /// older build's "Route not found", a JSON array) is `{}`: the status
  /// still says what happened.
  static Map<String, dynamic> _jsonMap(String text) {
    try {
      final v = jsonDecode(text);
      return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}
