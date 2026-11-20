import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/relay_database.dart';
import '../messaging/message_service.dart';
import '../node/notifier.dart';
import '../node/relay_node.dart';
import '../pairing/pairing_service.dart';
import '../ui/channels/channel_summary.dart';
import '../ui/channels/channels_screen.dart' show outboxSelectionId;
import '../ui/channels/message_view.dart';
import '../ui/outbox/outbox_screen.dart';
import '../ui/pairing/pairing_screen.dart' as ui;

const _reachableWithinMs = 120000;

String _firstLine(String? s) => (s ?? '').split('\n').first.trim();

/// Turns the node's state into what the screens show, and sends the
/// notifications: new messages, approvals (Send / Discard) and pairing codes.
class AppController extends ChangeNotifier {
  AppController(this.node, this.notifier, {required this.windowVisible});

  final RelayNode node;
  final Notifier notifier;

  /// Whether the window is on screen: an open channel then counts as seen.
  final bool Function() windowVisible;

  List<ChannelSummary>? channels;
  Map<String, ChannelPeer> peers = {};
  String? selectedId;
  List<MessageView>? messages;
  List<GapView> gaps = [];
  List<DraftView>? drafts;
  int awaitingApproval = 0;
  ui.PairingCodePrompt? pairingCode;
  String? _pairingDeviceId;
  final discovered = <String, ui.DiscoveredMac>{};

  final _subs = <StreamSubscription<Object?>>[];
  final _askedApproval = <String>{};
  Map<String, String> _channelNames = {};

  RelayDatabase get _db => node.db;

  Future<void> init() async {
    _subs
      ..add(node.messages.incoming.listen(_onIncoming))
      ..add(node.messages.changes.listen(_onChange))
      ..add(node.pairing.events.listen(_onPairing));
    final d = node.discovery;
    if (d != null) {
      _subs.add(
        d.found.listen((mac) {
          discovered[mac.deviceId] = ui.DiscoveredMac(
            id: mac.deviceId,
            personName: mac.name,
            deviceName: mac.name,
            address: '${mac.host}:${mac.port}',
          );
          notifyListeners();
        }),
      );
    }
    for (final draft in await _db.drafts()) {
      await _askApproval(draft);
    }
    await refresh();
  }

  Future<void> refresh() async {
    final me = node.identity!.deviceId;
    final unread = await _db.unreadCounts();
    final peerRows = {
      for (final p in await _db.select(_db.peers).get()) p.deviceId: p,
    };
    final list = <ChannelSummary>[];
    final peerMap = <String, ChannelPeer>{};
    final names = <String, String>{};
    for (final c in await _db.select(_db.channels).get()) {
      final members = await (_db.select(
        _db.channelMembers,
      )..where((m) => m.channelId.equals(c.id))).get();
      final other = members
          .map((m) => peerRows[m.deviceId])
          .whereType<Peer>()
          .where((p) => p.deviceId != me)
          .firstOrNull;
      final name = c.name ?? other?.personName ?? 'Unknown';
      names[c.id] = name;
      list.add((
        id: c.id,
        name: name,
        unread: unread[c.id] ?? 0,
        closed: c.closedAt != null,
      ));
      if (c.kind == 'private' && other != null) {
        peerMap[c.id] = (
          deviceName: other.deviceName,
          status: _statusOf(other),
        );
      }
    }
    channels = list;
    peers = peerMap;
    _channelNames = names;
    final pending = await _db.drafts();
    awaitingApproval = pending.length;
    drafts = [
      for (final m in pending)
        DraftView(
          id: m.id,
          channelName: names[m.channelId] ?? 'Unknown',
          body: m.body ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(m.createdAt),
          context: MessageContext.fromJson(m.contextJson),
        ),
    ];
    if (selectedId != null && selectedId != outboxSelectionId) {
      await _loadMessages(selectedId!, markRead: false);
    }
    notifyListeners();
  }

  PeerStatus _statusOf(Peer p) {
    if (p.trust == 'mismatch') return const PeerIdentityChanged();
    if (p.clockSkewMs != null) return PeerClockSkew(p.clockSkewMs!);
    final seen = p.lastSeenAt;
    final now = DateTime.now().millisecondsSinceEpoch;
    return seen != null && now - seen <= _reachableWithinMs
        ? const PeerOnline()
        : const PeerOffline();
  }

  Future<void> select(String id) async {
    selectedId = id;
    if (id != outboxSelectionId) await _loadMessages(id, markRead: true);
    await refresh();
  }

  Future<void> _loadMessages(String channelId, {required bool markRead}) async {
    final me = node.identity!;
    final peerRows = {
      for (final p in await _db.select(_db.peers).get()) p.deviceId: p,
    };
    final rows = markRead && windowVisible()
        ? await node.messages.read(channelId, by: Reader.person)
        : await _db.channelMessages(channelId);
    final views = <MessageView>[];
    for (final m in rows) {
      final mine = m.direction == 'out';
      final base = MessageView.fromRow(
        m,
        senderName: mine
            ? 'You'
            : peerRows[m.fromDeviceId]?.personName ?? 'Unknown',
      );
      if (!mine) {
        views.add(base);
        continue;
      }
      DateTime? t(int? ms) =>
          ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      views.add(
        MessageView(
          id: base.id,
          senderName: base.senderName,
          sentAt: base.sentAt,
          body: base.body,
          context: base.context,
          arrivedLate: base.arrivedLate,
          locked: base.locked,
          mine: true,
          receipts: [
            for (final r in await node.messages.receiptsFor(m.id))
              (
                personName: r.personName,
                deliveredAt: t(r.deliveredAt),
                seenAt: t(r.seenAt),
                agentReadAt: t(r.agentReadAt),
              ),
          ],
        ),
      );
    }
    messages = views;
    gaps = [
      for (final g in await _db.gaps(channelId))
        (
          personName:
              peerRows[g.fromDeviceId]?.personName ??
              (g.fromDeviceId == me.deviceId ? me.personName : 'Unknown'),
          missing: g.missing,
        ),
    ];
  }

  Future<void> _onIncoming(Message m) async {
    await refresh();
    final peer = await (_db.select(
      _db.peers,
    )..where((p) => p.deviceId.equals(m.fromDeviceId))).getSingleOrNull();
    final person = peer?.personName ?? 'Someone';
    final channel = _channelNames[m.channelId] ?? person;
    final title = channel == person ? person : '$channel · $person';
    final body = m.status == 'locked' ? 'Locked message' : _firstLine(m.body);
    await notifier.show(
      NotificationText(m.arrivedLate ? '$title · arrived late' : title, body),
      onClick: () => unawaited(select(m.channelId)),
    );
    if (selectedId == m.channelId && windowVisible()) {
      await select(m.channelId);
    }
  }

  Future<void> _onChange(Message m) async {
    if (m.direction == 'out' && m.status == 'awaiting_approval') {
      await _askApproval(m);
    } else if (_askedApproval.remove(m.id)) {
      await notifier.remove(m.id);
    }
    await refresh();
  }

  Future<void> _askApproval(Message m) async {
    if (!_askedApproval.add(m.id)) return;
    if (_channelNames.isEmpty) await refresh();
    final to = _channelNames[m.channelId] ?? 'teammate';
    await notifier.show(
      NotificationText('Send to $to?', _firstLine(m.body)),
      tag: m.id,
      actions: const ['Send', 'Discard'],
      onAction: (i) => unawaited(i == 0 ? approve(m.id) : discard(m.id)),
      onClick: () => unawaited(select(outboxSelectionId)),
    );
  }

  Future<void> approve(String id) async {
    await node.messages.approve(id);
  }

  Future<void> discard(String id) async {
    await node.messages.discard(id);
  }

  Future<void> _onPairing(PairingEvent e) async {
    switch (e) {
      case PairingCodeShown(:final pending):
        _pairingDeviceId = pending.deviceId;
        pairingCode = ui.PairingCodePrompt(
          code: pending.code,
          personName: pending.personName,
          deviceName: pending.deviceName,
        );
        await notifier.show(
          NotificationText(
            'Pairing code ${pending.code}',
            'Check that ${pending.personName}\'s screen shows the same code.',
          ),
        );
      case PairingSucceeded():
      case PairingFailed():
      case PairingExpired():
        pairingCode = null;
        _pairingDeviceId = null;
        await refresh();
      case PeerUnpaired():
      case PairingOpened():
        await refresh();
    }
    notifyListeners();
  }

  Future<void> confirmPairing() async {
    final id = _pairingDeviceId;
    if (id != null) await node.pairing.confirm(id);
  }

  void cancelPairing() {
    final id = _pairingDeviceId;
    if (id != null) node.pairing.cancel(id);
    pairingCode = null;
    _pairingDeviceId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
