import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../crypto/identity_keys.dart';
import '../data/relay_database.dart';
import '../identity/local_identity.dart';
import '../ordering/hlc.dart';
import '../peer/peer_client.dart';
import 'comparison_code.dart';
import 'pairing_window.dart';
import '../peer/trust.dart';

typedef PendingPair = ({
  String deviceId,
  String personName,
  String deviceName,
  String code,
});

sealed class PairingEvent {
  const PairingEvent();
}

class PairingOpened extends PairingEvent {
  const PairingOpened(this.closesAt);
  final DateTime closesAt;
}

class PairingCodeShown extends PairingEvent {
  const PairingCodeShown(this.pending);
  final PendingPair pending;
}

class PairingSucceeded extends PairingEvent {
  const PairingSucceeded(this.deviceId, this.personName);
  final String deviceId;
  final String personName;
}

class PairingExpired extends PairingEvent {
  const PairingExpired();
}

class PairingFailed extends PairingEvent {
  const PairingFailed(this.deviceId, this.reason);
  final String deviceId;
  final String reason;
}

class PeerUnpaired extends PairingEvent {
  const PeerUnpaired(this.deviceId);
  final String deviceId;
}

class PairingRejected implements Exception {
  const PairingRejected(this.reason);
  final String reason;
  @override
  String toString() => 'pairing refused: $reason';
}

class _Pending {
  _Pending({
    required this.info,
    required this.fingerprint,
    required this.host,
    required this.port,
    required this.myNonce,
    required this.createdAt,
    this.theirNonce,
    this.theirCommit,
  });
  final Map<String, dynamic> info;
  final String fingerprint; // the other Mac's certificate, pinned on success
  final String host;
  final int port;
  final List<int> myNonce;
  final DateTime createdAt;
  List<int>? theirNonce;
  final String? theirCommit;
  String? code; // set once both nonces are known
  bool localConfirmed = false;
  bool remoteConfirmed = false;

  String get deviceId => info['deviceId'] as String;
  PendingPair get view => (
    deviceId: deviceId,
    personName: info['personName'] as String,
    deviceName: info['deviceName'] as String,
    code: code!,
  );
}

/// Mac-to-Mac pairing: hello (unpinned) → both show the comparison code →
/// each person confirms → each side tells the other → both store the peer and
/// the private channel.
class PairingService {
  PairingService({
    required this.db,
    required this.me,
    required this.client,
    required this.window,
    required this.clock,
    required this.myPort,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    window.events.listen(_events.add);
  }

  final RelayDatabase db;
  final LocalIdentity me;
  final PeerClient client;
  final PairingWindow window;
  final HlcClock clock;
  final int Function() myPort;
  final DateTime Function() _now;
  final _pending = <String, _Pending>{};
  final _events = StreamController<PairingEvent>.broadcast();

  Stream<PairingEvent> get events => _events.stream;

  Map<String, dynamic> get _myInfo => {
    'deviceId': me.deviceId,
    'personName': me.personName,
    'deviceName': me.deviceName,
    'signPub': base64.encode(me.keys.signPub),
    'boxPub': base64.encode(me.keys.boxPub),
    'certFingerprint': me.certFingerprint,
    'port': myPort(),
  };

  void openWindow() => window.open();

  List<int> _keysOf(Map<String, dynamic> info) => [
    ...base64.decode(info['signPub'] as String),
    ...base64.decode(info['boxPub'] as String),
  ];

  String _codeFor(_Pending p) => comparisonCode(
    fpA: me.certFingerprint,
    fpB: p.fingerprint,
    keysA: [...me.keys.signPub, ...me.keys.boxPub],
    keysB: _keysOf(p.info),
    nonceA: p.myNonce,
    nonceB: p.theirNonce!,
  );

  /// Initiator side: hello with a commitment, then reveal the nonce.
  Future<PendingPair> connect(PeerTarget t) async {
    final myNonce = newNonce();
    final res = await client.post(
      (host: t.host, port: t.port, pinnedFingerprint: null),
      '/pair/hello',
      {..._myInfo, 'commit': commitmentOf(myNonce)},
    );
    if (res.status != 200) {
      throw PairingRejected(
        res.json['error'] as String? ?? 'status ${res.status}',
      );
    }
    final info = res.json;
    if (deviceIdFor(
          base64.decode(info['signPub'] as String),
          base64.decode(info['boxPub'] as String),
        ) !=
        info['deviceId']) {
      throw const PairingRejected('device id does not match its keys');
    }
    final p = _Pending(
      info: info,
      fingerprint: res.presentedFingerprint!,
      host: t.host,
      port: t.port,
      myNonce: myNonce,
      theirNonce: base64.decode(info['nonce'] as String),
      createdAt: _now(),
    );
    final reveal = await client.post(
      (host: t.host, port: t.port, pinnedFingerprint: p.fingerprint),
      '/pair/reveal',
      {
        'deviceId': me.deviceId,
        'signPub': base64.encode(me.keys.signPub),
        'nonce': base64.encode(myNonce),
      },
    );
    if (reveal.status != 200) {
      throw PairingRejected(
        reveal.json['error'] as String? ?? 'status ${reveal.status}',
      );
    }
    p.code = _codeFor(p);
    _pending[p.deviceId] = p;
    _events.add(PairingCodeShown(p.view));
    return p.view;
  }

  /// Responder side of `/pair/hello`: (status, body). 403 when the window is
  /// closed, 409 when another pairing was already in progress (both are then
  /// abandoned: two Macs at once is how an attacker would slip in).
  Future<(int, Map<String, dynamic>)> handleHello(
    Map<String, dynamic> body,
    String remoteHost,
  ) async {
    if (!window.isOpen) {
      return (403, <String, dynamic>{'error': 'pairing_closed'});
    }
    final List<int> signPub, boxPub;
    final String fp, commit;
    final int port;
    try {
      signPub = base64.decode(body['signPub'] as String);
      boxPub = base64.decode(body['boxPub'] as String);
      fp = body['certFingerprint'] as String;
      commit = body['commit'] as String;
      port = body['port'] as int;
      body['personName'] as String;
      body['deviceName'] as String;
    } on Object {
      return (400, <String, dynamic>{'error': 'bad_hello'});
    }
    if (deviceIdFor(signPub, boxPub) != body['deviceId']) {
      return (400, <String, dynamic>{'error': 'bad_hello'});
    }
    final live = _pending.keys.where((id) => _live(id) != null).toList();
    if (live.isNotEmpty) {
      for (final id in live) {
        _pending.remove(id);
        _events.add(
          PairingFailed(
            id,
            'Another Mac tried to pair at the same time. Start again.',
          ),
        );
      }
      return (409, <String, dynamic>{'error': 'pairing_busy'});
    }
    final p = _Pending(
      info: body,
      fingerprint: fp,
      host: remoteHost,
      port: port,
      myNonce: newNonce(),
      theirCommit: commit,
      createdAt: _now(),
    );
    _pending[p.deviceId] = p;
    return (
      200,
      <String, dynamic>{..._myInfo, 'nonce': base64.encode(p.myNonce)},
    );
  }

  /// `/pair/reveal`: the initiator's nonce, checked against its commitment.
  /// Only now is the code shown here.
  Future<bool> handleReveal(
    String deviceId,
    List<int> signPub,
    List<int> nonce,
  ) async {
    final p = _live(deviceId);
    if (p == null || p.theirCommit == null || p.code != null) return false;
    if (base64.encode(signPub) != p.info['signPub']) return false;
    if (commitmentOf(nonce) != p.theirCommit) {
      _pending.remove(deviceId);
      _events.add(
        PairingFailed(deviceId, 'Pairing check failed. Start again.'),
      );
      return false;
    }
    p.theirNonce = nonce;
    p.code = _codeFor(p);
    _events.add(PairingCodeShown(p.view));
    return true;
  }

  /// This person says the codes match.
  Future<void> confirm(String deviceId) async {
    final p = _live(deviceId);
    if (p == null || p.code == null) {
      throw const PairingRejected('no pairing in progress');
    }
    p.localConfirmed = true;
    try {
      final res = await client.post(
        (host: p.host, port: p.port, pinnedFingerprint: p.fingerprint),
        '/pair/confirm',
        {'deviceId': me.deviceId, 'signPub': base64.encode(me.keys.signPub)},
      );
      if (res.status != 200) {
        throw PairingRejected(
          res.json['error'] as String? ?? 'status ${res.status}',
        );
      }
    } on Object catch (e) {
      _pending.remove(deviceId);
      _events.add(PairingFailed(deviceId, '$e'));
      if (e is PairingRejected) rethrow;
      throw PairingRejected('$e');
    }
    await _maybeComplete(p);
  }

  /// `/pair/confirm` from the other Mac. False when there is no such pairing
  /// or the signing key differs from the one given in hello.
  Future<bool> handleConfirm(String deviceId, List<int> signPub) async {
    final p = _live(deviceId);
    if (p == null || p.code == null) return false;
    if (base64.encode(signPub) != p.info['signPub']) return false;
    p.remoteConfirmed = true;
    await _maybeComplete(p);
    return true;
  }

  void cancel(String deviceId) => _pending.remove(deviceId);

  _Pending? _live(String deviceId) {
    final p = _pending[deviceId];
    if (p == null) return null;
    if (_now().difference(p.createdAt) > window.length) {
      _pending.remove(deviceId);
      return null;
    }
    return p;
  }

  Future<void> _maybeComplete(_Pending p) async {
    if (!p.localConfirmed || !p.remoteConfirmed) return;
    _pending.remove(p.deviceId);
    final nowMs = _now().millisecondsSinceEpoch;
    final channelId = privateChannelId(me.deviceId, p.deviceId);
    final joined = clock.tick().encode();
    await db.transaction(() async {
      await db
          .into(db.peers)
          .insertOnConflictUpdate(
            PeersCompanion.insert(
              deviceId: p.deviceId,
              personName: p.info['personName'] as String,
              deviceName: p.info['deviceName'] as String,
              signPub: Uint8List.fromList(
                base64.decode(p.info['signPub'] as String),
              ),
              boxPub: Uint8List.fromList(
                base64.decode(p.info['boxPub'] as String),
              ),
              certFingerprint: p.fingerprint,
              trust: 'paired',
              lastAddress: Value(p.host),
              lastPort: Value(p.port),
              lastSeenAt: Value(nowMs),
              pairedAt: nowMs,
            ),
          );
      await db
          .into(db.channels)
          .insertOnConflictUpdate(
            ChannelsCompanion.insert(
              id: channelId,
              kind: 'private',
              createdAt: nowMs,
              closedAt: const Value(null),
            ),
          );
      for (final id in [me.deviceId, p.deviceId]) {
        await db
            .into(db.channelMembers)
            .insertOnConflictUpdate(
              ChannelMembersCompanion.insert(
                channelId: channelId,
                deviceId: id,
                joinedHlc: joined,
              ),
            );
      }
    });
    _events.add(PairingSucceeded(p.deviceId, p.info['personName'] as String));
  }

  /// Unpair: close the private channel here and tell the other Mac once.
  Future<void> unpair(String deviceId) async {
    final peer = await (db.select(
      db.peers,
    )..where((x) => x.deviceId.equals(deviceId))).getSingleOrNull();
    await markUnpaired(deviceId);
    if (peer?.lastAddress == null || peer?.lastPort == null) return;
    try {
      await client.post(
        (
          host: peer!.lastAddress!,
          port: peer.lastPort!,
          pinnedFingerprint: peer.certFingerprint,
        ),
        '/pair/unpair',
        {},
      );
    } on Object {
      // Best effort: the other Mac learns from a 401 on its next request.
    }
  }

  /// Local side of an unpair (ours, or one the other Mac told us about).
  Future<void> markUnpaired(String deviceId) async {
    final nowMs = _now().millisecondsSinceEpoch;
    final keep = await sharesSurat(db, me.deviceId, deviceId);
    await (db.update(
      db.peers,
    )..where((x) => x.deviceId.equals(deviceId))).write(
      PeersCompanion(trust: Value(keep ? trustSuratContact : 'unpaired')),
    );
    await (db.update(db.channels)
          ..where((c) => c.id.equals(privateChannelId(me.deviceId, deviceId))))
        .write(ChannelsCompanion(closedAt: Value(nowMs)));
    _events.add(PeerUnpaired(deviceId));
  }
}
