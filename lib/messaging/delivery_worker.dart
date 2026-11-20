import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/relay_database.dart';
import '../node/notifier.dart';
import '../peer/peer_client.dart';
import 'message_service.dart';
import '../peer/trust.dart';
import '../surat/surat_service.dart' show eventPath;

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
    this.onDraftsExpired,
    this.keepAlive,
    int Function()? nowMs,
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// When set, a paired peer not heard from for this long is pinged, so
  /// "online" stays true for an idle teammate whose Mac is up. Null: off.
  final Duration? keepAlive;
  final _lastPing = <String, int>{};

  final RelayDatabase db;
  final PeerTransport transport;
  final MessageService messages;
  final Notifier notifier;

  /// The other Mac answered `untrusted`: it unpaired while we were away.
  final Future<void> Function(String deviceId) onUnpaired;

  /// The drafts a pass just expired (status already `expired`), so an
  /// unapproved surat creation can remove its surat.
  final Future<void> Function(List<Message> expired)? onDraftsExpired;
  final int Function() _now;
  final _skewNoticeSent = <String>{};
  final _tooOldNoticeSent = <String>{};
  Timer? _timer;
  Future<void>? _current;
  bool _again = false;

  void start({Duration tick = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => runOnce());
  }

  /// Stops the timer and waits out a pass already running, so the database
  /// can be closed after this returns.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    while (_current != null) {
      try {
        await _current;
      } on Object {
        // The pass's own caller sees its error; stopping goes on.
      }
    }
  }

  /// A peer was just seen (mDNS or an inbound request): retry it now.
  Future<void> peerSeen(String deviceId) async {
    await (db.update(db.deliveries)..where(
          (d) =>
              d.recipientDeviceId.equals(deviceId) & d.status.equals('queued'),
        ))
        .write(DeliveriesCompanion(nextAttemptAt: Value(_now())));
    if (_timer != null) unawaited(runOnce());
  }

  /// One pass over due deliveries. A call made while a pass is running
  /// waits for it and then runs one more pass, so nothing is skipped.
  Future<void> runOnce() async {
    if (_current != null) {
      _again = true;
      await _current;
      return;
    }
    do {
      _again = false;
      _current = _pass();
      try {
        await _current;
      } finally {
        _current = null;
      }
    } while (_again);
  }

  Future<void> _pass() async {
    await _expireDrafts();
    final peers = {
      for (final p in await db.select(db.peers).get()) p.deviceId: p,
    };
    _keepAlive(peers.values);
    final unreachable = <String>{};
    for (final due in await db.dueDeliveries(_now())) {
      // An earlier attempt this pass may have dropped or delayed it.
      final d =
          await (db.select(db.deliveries)..where(
                (x) =>
                    x.messageId.equals(due.messageId) &
                    x.recipientDeviceId.equals(due.recipientDeviceId),
              ))
              .getSingle();
      if (d.status != 'queued' || d.nextAttemptAt > _now()) continue;
      if (await _dropIfTooOld(d, peers[d.recipientDeviceId])) continue;
      final peer = peers[d.recipientDeviceId];
      if (peer == null || !canTalk(peer)) continue;
      if (peer.trust != 'paired' && await _isPrivate(d)) {
        // Private channels are for paired peers only; the channel is closed.
        await _set(d, status: 'dropped', error: 'unpaired');
        continue;
      }
      if (unreachable.contains(peer.deviceId)) {
        // Already failed this pass: don't wait out another timeout.
        await _retry(d, 'peer unreachable');
        continue;
      }
      if (!await _attempt(d, peer)) unreachable.add(peer.deviceId);
      // A peer may change state (unpaired, address cleared) mid-run.
      peers[peer.deviceId] = await (db.select(
        db.peers,
      )..where((p) => p.deviceId.equals(peer.deviceId))).getSingle();
    }
  }

  /// Runs before any trust check, so nothing waits forever for a peer that
  /// is unpaired or changed.
  Future<bool> _dropIfTooOld(Delivery d, Peer? peer) async {
    if (_now() - d.createdAt <= queueLifetimeMs) return false;
    await _set(d, status: 'dropped', error: 'older than 7 days');
    if (!d.messageId.startsWith('receipt:') &&
        !d.messageId.startsWith(historyPrefix)) {
      await notifier.show(
        NotificationText(
          "Couldn't deliver to ${peer?.personName ?? 'a teammate'}",
          'The message waited 7 days for their Mac and was dropped.',
        ),
      );
    }
    return true;
  }

  Future<void> _expireDrafts() async {
    final cutoff = _now() - draftLifetimeMs;
    final expired =
        await (db.update(db.messages)..where(
              (m) =>
                  m.direction.equals('out') &
                  m.status.equals('awaiting_approval') &
                  m.createdAt.isSmallerThanValue(cutoff),
            ))
            .writeReturning(const MessagesCompanion(status: Value('expired')));
    if (expired.isNotEmpty) await onDraftsExpired?.call(expired);
  }

  /// Pings idle paired peers, without holding up deliveries.
  void _keepAlive(Iterable<Peer> peers) {
    final every = keepAlive?.inMilliseconds;
    if (every == null) return;
    final now = _now();
    for (final p in peers) {
      if (!canTalk(p) || p.lastAddress == null || p.lastPort == null) {
        continue;
      }
      final seen = p.lastSeenAt;
      if (seen != null && now - seen < every) continue;
      if (now - (_lastPing[p.deviceId] ?? 0) < every) continue;
      _lastPing[p.deviceId] = now;
      unawaited(_ping(p));
    }
  }

  Future<void> _ping(Peer peer) async {
    try {
      await transport.post(
        (
          host: peer.lastAddress!,
          port: peer.lastPort!,
          pinnedFingerprint: peer.certFingerprint,
        ),
        '/relay/ping',
        const {},
      );
      // Any answer over the pinned connection is that Mac — even a 404 from
      // a build without the ping route.
      await _peer(peer, PeersCompanion(lastSeenAt: Value(_now())));
    } on Object {
      // Not reachable now; "online" lapses on its own.
    }
  }

  /// One try. False when the peer could not be reached at all.
  Future<bool> _attempt(Delivery d, Peer peer) async {
    if (peer.lastAddress == null || peer.lastPort == null) {
      await _retry(d, 'no known address');
      return false;
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
      // It answered over the pinned connection: it is up right now.
      await _peer(peer, PeersCompanion(lastSeenAt: Value(_now())));
      if (res.status == 200) {
        await messages.markDelivered(d.messageId, d.recipientDeviceId);
        if (peer.clockSkewMs != null) {
          await _peer(peer, const PeersCompanion(clockSkewMs: Value(null)));
          _skewNoticeSent.remove(peer.deviceId);
        }
      } else if (res.status == 401 && res.json['error'] == 'untrusted') {
        // Still sharing a surat: only the private-channel deliveries go.
        final keepSurat = await sharesSurat(
          db,
          messages.myDeviceId,
          peer.deviceId,
        );
        final queued =
            await (db.select(db.deliveries)..where(
                  (x) =>
                      x.recipientDeviceId.equals(peer.deviceId) &
                      x.status.equals('queued'),
                ))
                .get();
        for (final q in queued) {
          if (!keepSurat || await _isPrivate(q)) {
            await _set(q, status: 'dropped', error: 'unpaired');
          } else {
            await _retry(q, 'untrusted');
          }
        }
        // Only a paired peer is newly unpaired; a contact that answers 401
        // just backs off.
        if (peer.trust == 'paired') {
          await onUnpaired(peer.deviceId);
          await notifier.show(
            NotificationText(
              '${peer.personName} unpaired',
              'Their Mac no longer accepts messages from this one.',
            ),
          );
        }
      } else if (env['path'] == eventPath && res.status == 404) {
        // A 1.0.x build has no event route.
        await _set(d, status: 'dropped', error: 'too old for surat');
        if (_tooOldNoticeSent.add(peer.deviceId)) {
          await notifier.show(
            NotificationText(
              "${peer.personName}'s Agent Relay is too old for surat",
              'ask them to update',
            ),
          );
        }
      } else if (env['path'] == eventPath && res.status == 403) {
        // Events from different senders arrive in any order: an accept can
        // land before the invite that seats its sender. Try again later.
        await _retry(d, 'not_a_member');
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
      // Another Mac answers at this address now (a reused IP or a false
      // advert). The pairing is fine; forget the address until the peer is
      // seen again by mDNS or by its own signed request.
      await _peer(peer, const PeersCompanion(lastAddress: Value(null)));
      await _retry(d, 'a different Mac answered at ${peer.lastAddress}');
      return false;
    } on PeerUnreachable catch (e) {
      await _retry(d, '$e');
      return false;
    }
    return true;
  }

  /// Whether this delivery (a message, or a receipt for one) belongs to a
  /// private channel.
  Future<bool> _isPrivate(Delivery d) async {
    final id =
        d.messageId.startsWith('receipt:') ||
            d.messageId.startsWith(historyPrefix)
        ? d.messageId.split(':')[1]
        : d.messageId;
    final q = db.select(db.channels).join([
      innerJoin(db.messages, db.messages.channelId.equalsExp(db.channels.id)),
    ])..where(db.messages.id.equals(id) & db.channels.kind.equals('private'));
    return (await q.get()).isNotEmpty;
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
