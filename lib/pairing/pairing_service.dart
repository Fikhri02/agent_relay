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
    required this.code,
    required this.createdAt,
  });
  final Map<String, dynamic> info;
  final String fingerprint; // the other Mac's certificate, pinned on success
  final String host;
  final int port;
  final String code;
  final DateTime createdAt;
  bool localConfirmed = false;
  bool remoteConfirmed = false;

  String get deviceId => info['deviceId'] as String;
  PendingPair get view => (
    deviceId: deviceId,
    personName: info['personName'] as String,
    deviceName: info['deviceName'] as String,
    code: code,
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

  String _codeWith(Map<String, dynamic> other, String otherFp) =>
      comparisonCode(
        fpA: me.certFingerprint,
        fpB: otherFp,
        keysA: [...me.keys.signPub, ...me.keys.boxPub],
        keysB: _keysOf(other),
      );

  /// Initiator side: reach the other Mac (its window must be open).
  Future<PendingPair> connect(PeerTarget t) async {
    final res = await client.post(
      (host: t.host, port: t.port, pinnedFingerprint: null),
      '/pair/hello',
      _myInfo,
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
    final fp = res.presentedFingerprint!;
    final p = _Pending(
      info: info,
      fingerprint: fp,
      host: t.host,
      port: t.port,
      code: _codeWith(info, fp),
      createdAt: _now(),
    );
    _pending[p.deviceId] = p;
    _events.add(PairingCodeShown(p.view));
    return p.view;
  }

  /// Responder side of `/pair/hello`. Returns this Mac's info, or null when
  /// the window is closed.
  Future<Map<String, dynamic>?> handleHello(
    Map<String, dynamic> body,
    String remoteHost,
  ) async {
    if (!window.isOpen) return null;
    final keysMatch =
        deviceIdFor(
          base64.decode(body['signPub'] as String),
          base64.decode(body['boxPub'] as String),
        ) ==
        body['deviceId'];
    if (!keysMatch) return null;
    final fp = body['certFingerprint'] as String;
    final p = _Pending(
      info: body,
      fingerprint: fp,
      host: remoteHost,
      port: body['port'] as int,
      code: _codeWith(body, fp),
      createdAt: _now(),
    );
    _pending[p.deviceId] = p;
    _events.add(PairingCodeShown(p.view));
    return _myInfo;
  }

  /// This person says the codes match.
  Future<void> confirm(String deviceId) async {
    final p = _live(deviceId);
    if (p == null) throw const PairingRejected('no pairing in progress');
    p.localConfirmed = true;
    try {
      await client.post(
        (host: p.host, port: p.port, pinnedFingerprint: p.fingerprint),
        '/pair/confirm',
        {'deviceId': me.deviceId, 'signPub': base64.encode(me.keys.signPub)},
      );
    } on Object catch (e) {
      _pending.remove(deviceId);
      _events.add(PairingFailed(deviceId, '$e'));
      rethrow;
    }
    await _maybeComplete(p);
  }

  /// `/pair/confirm` from the other Mac. False when there is no such pairing
  /// or the signing key differs from the one given in hello.
  Future<bool> handleConfirm(String deviceId, List<int> signPub) async {
    final p = _live(deviceId);
    if (p == null) return false;
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
    await (db.update(db.peers)..where((x) => x.deviceId.equals(deviceId)))
        .write(const PeersCompanion(trust: Value('unpaired')));
    await (db.update(db.channels)
          ..where((c) => c.id.equals(privateChannelId(me.deviceId, deviceId))))
        .write(ChannelsCompanion(closedAt: Value(nowMs)));
    _events.add(PeerUnpaired(deviceId));
  }
}
