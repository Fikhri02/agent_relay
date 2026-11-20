import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/relay_database.dart';
import '../node/notifier.dart';
import '../peer/peer_client.dart';
import 'message_service.dart';

const draftLifetimeMs = 60 * 60 * 1000;
const queueLifetimeMs = 7 * 24 * 60 * 60 * 1000;
const _backoffMs = [5000, 30000, 120000, 300000];

/// Sends queued deliveries (messages and receipts), retries with backoff,
/// drops what is older than 7 days and expires unapproved drafts after 1 hour.
class DeliveryWorker {
  DeliveryWorker({
    required this.db,
    required this.transport,
    required this.messages,
    required this.notifier,
    required this.onUnpaired,
    int Function()? nowMs,
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final RelayDatabase db;
  final PeerTransport transport;
  final MessageService messages;
  final Notifier notifier;

  /// The other Mac answered `untrusted`: it unpaired while we were away.
  final Future<void> Function(String deviceId) onUnpaired;
  final int Function() _now;
  final _skewNoticeSent = <String>{};
  Timer? _timer;
  bool _running = false;

  void start({Duration tick = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => runOnce());
  }

  void stop() => _timer?.cancel();

  /// A peer was just seen (mDNS or an inbound request): retry it now.
  Future<void> peerSeen(String deviceId) async {
    await (db.update(db.deliveries)..where(
          (d) =>
              d.recipientDeviceId.equals(deviceId) & d.status.equals('queued'),
        ))
        .write(DeliveriesCompanion(nextAttemptAt: Value(_now())));
    if (_timer != null) unawaited(runOnce());
  }

  Future<void> runOnce() async {
    if (_running) return;
    _running = true;
    try {
      await _expireDrafts();
      final peers = {
        for (final p in await db.select(db.peers).get()) p.deviceId: p,
      };
      for (final d in await db.dueDeliveries(_now())) {
        final peer = peers[d.recipientDeviceId];
        if (peer == null || peer.trust != 'paired') continue;
        await _attempt(d, peer);
        // A peer may change state (unpaired, mismatch) mid-run.
        peers[peer.deviceId] = await (db.select(
          db.peers,
        )..where((p) => p.deviceId.equals(peer.deviceId))).getSingle();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _expireDrafts() async {
    final cutoff = _now() - draftLifetimeMs;
    await (db.update(db.messages)..where(
          (m) =>
              m.direction.equals('out') &
              m.status.equals('awaiting_approval') &
              m.createdAt.isSmallerThanValue(cutoff),
        ))
        .write(const MessagesCompanion(status: Value('expired')));
  }

  Future<void> _attempt(Delivery d, Peer peer) async {
    final now = _now();
    final isReceipt = d.messageId.startsWith('receipt:');
    if (now - d.createdAt > queueLifetimeMs) {
      await _set(d, status: 'dropped', error: 'older than 7 days');
      if (!isReceipt) {
        await notifier.show(
          NotificationText(
            "Couldn't deliver to ${peer.personName}",
            'The message waited 7 days for their Mac and was dropped.',
          ),
        );
      }
      return;
    }
    if (peer.lastAddress == null || peer.lastPort == null) {
      await _retry(d, 'no known address');
      return;
    }
    final env = jsonDecode(d.envelopeJson) as Map<String, dynamic>;
    try {
      final res = await transport.post(
        (
          host: peer.lastAddress!,
          port: peer.lastPort!,
          pinnedFingerprint: peer.certFingerprint,
        ),
        env['path'] as String,
        (env['payload'] as Map).cast<String, dynamic>(),
      );
      if (res.status == 200) {
        await messages.markDelivered(d.messageId, d.recipientDeviceId);
        if (peer.clockSkewMs != null) {
          await _peer(peer, const PeersCompanion(clockSkewMs: Value(null)));
          _skewNoticeSent.remove(peer.deviceId);
        }
      } else if (res.status == 401 && res.json['error'] == 'untrusted') {
        await (db.update(db.deliveries)..where(
              (x) =>
                  x.recipientDeviceId.equals(peer.deviceId) &
                  x.status.equals('queued'),
            ))
            .write(
              const DeliveriesCompanion(
                status: Value('dropped'),
                lastError: Value('unpaired'),
              ),
            );
        await onUnpaired(peer.deviceId);
        await notifier.show(
          NotificationText(
            '${peer.personName} unpaired',
            'Their Mac no longer accepts messages from this one.',
          ),
        );
      } else if (res.status >= 400 && res.status < 500) {
        await _set(
          d,
          status: 'dropped',
          error: 'refused ${res.status} ${res.json['error']}',
        );
      } else {
        await _retry(d, 'status ${res.status}');
      }
    } on PeerClockSkew catch (e) {
      await _peer(peer, PeersCompanion(clockSkewMs: Value(e.skewMs)));
      await _retry(d, '$e');
      if (_skewNoticeSent.add(peer.deviceId)) {
        await notifier.show(
          NotificationText(
            "Can't reach ${peer.personName}",
            'Clocks differ by ${(e.skewMs.abs() / 1000).round()} s. Set both Macs to set time automatically.',
          ),
        );
      }
    } on PeerIdentityMismatch {
      await _peer(peer, const PeersCompanion(trust: Value('mismatch')));
      await _retry(d, 'identity changed');
      await notifier.show(
        NotificationText(
          '${peer.personName}\'s Mac changed',
          "Its identity changed — pair again before sending more.",
        ),
      );
    } on PeerUnreachable catch (e) {
      await _retry(d, '$e');
    }
  }

  Future<void> _retry(Delivery d, String error) async {
    final attempts = d.attempts + 1;
    final wait = _backoffMs[(attempts - 1).clamp(0, _backoffMs.length - 1)];
    await (db.update(db.deliveries)..where(
          (x) =>
              x.messageId.equals(d.messageId) &
              x.recipientDeviceId.equals(d.recipientDeviceId),
        ))
        .write(
          DeliveriesCompanion(
            attempts: Value(attempts),
            nextAttemptAt: Value(_now() + wait),
            lastError: Value(error),
          ),
        );
  }

  Future<void> _set(Delivery d, {required String status, String? error}) =>
      (db.update(db.deliveries)..where(
            (x) =>
                x.messageId.equals(d.messageId) &
                x.recipientDeviceId.equals(d.recipientDeviceId),
          ))
          .write(
            DeliveriesCompanion(status: Value(status), lastError: Value(error)),
          );

  Future<void> _peer(Peer p, PeersCompanion c) => (db.update(
    db.peers,
  )..where((x) => x.deviceId.equals(p.deviceId))).write(c);
}
