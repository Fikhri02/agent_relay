import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/relay_database.dart';
import '../discovery/discovery_service.dart' show splitAdvertisedName;
import '../node/notifier.dart';
import '../node/relay_node.dart';
import '../pairing/pairing_service.dart';
import '../peer/trust.dart' show trustPaired;
import '../surat/member_names.dart';
import '../surat/surat_service.dart';
import '../ui/channels/channel_summary.dart';
import '../ui/channels/channels_screen.dart' show outboxSelectionId;
import '../ui/channels/message_view.dart';
import '../ui/outbox/outbox_screen.dart';
import '../ui/pairing/pairing_screen.dart' as ui;
import '../ui/surat/new_surat_dialog.dart' show PeerChoice;
import '../ui/surat/pending_panel.dart';
import 'surat_views.dart';

const _reachableWithinMs = 120000;

String _firstLine(String? s) => (s ?? '').split('\n').first.trim();

/// Turns the node's state into what the screens show, and sends the
/// notifications: new messages, approvals (Send / Discard), pairing codes and
/// surat changes (invites, newcomers, renames, endings).
class AppController extends ChangeNotifier {
  AppController(this.node, this.notifier, {required this.windowVisible});

  final RelayNode node;
  final Notifier notifier;

  /// Whether the window is on screen: an open channel then counts as seen.
  final bool Function() windowVisible;

  /// Private channels. Null while loading.
  List<ChannelSummary>? channels;

  /// Surat I'm in or invited to (published ones only).
  List<ChannelSummary> surat = [];

  /// Surat id → current member names for the status line.
  Map<String, List<String>> suratMembers = {};

  /// Invites and newcomers waiting for my answer.
  List<PendingView> pending = [];

  /// Paired people a new surat can invite.
  List<PeerChoice> pairedPeers = [];
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
  final _askedPending = <String>{};
  Map<String, String> _channelNames = {};
  Map<String, String Function(String)> _namers = {};

  RelayDatabase get _db => node.db;

  Future<void> init() async {
    _subs
      ..add(node.messages.incoming.listen(_onIncoming))
      ..add(node.messages.changes.listen(_onChange))
      ..add(node.surat.changes.listen(_onSurat))
      ..add(node.pairing.events.listen(_onPairing));
    final d = node.discovery;
    if (d != null) {
      _subs.add(
        d.found.listen((mac) {
          final (person, device) = splitAdvertisedName(mac.name);
          discovered[mac.deviceId] = ui.DiscoveredMac(
            id: mac.deviceId,
            personName: person,
            deviceName: device,
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
    final unread = await _db.unreadCounts(by: Reader.person);
    final peerRows = {
      for (final p in await _db.select(_db.peers).get()) p.deviceId: p,
    };
    final list = <ChannelSummary>[];
    final groups = <ChannelSummary>[];
    final groupMembers = <String, List<String>>{};
    final peerMap = <String, ChannelPeer>{};
    final names = <String, String>{};
    final namers = <String, String Function(String)>{};
    final rowsOf = <String, List<ChannelMember>>{};
    for (final c in await _db.select(_db.channels).get()) {
      final members = await (_db.select(
        _db.channelMembers,
      )..where((m) => m.channelId.equals(c.id))).get();
      if (c.kind == 'surat') {
        names[c.id] = c.name ?? 'Surat';
        rowsOf[c.id] = members;
        final nameOf = namers[c.id] = memberNamer(
          members,
          peerRows,
          meDeviceId: me,
        );
        final mine = members.where((m) => m.deviceId == me).firstOrNull;
        // Not shown: a creation still in the Outbox, or an invite I declined.
        if (mine == null ||
            mine.joinedHlc == unpublishedHlc ||
            mine.state == 'declined') {
          continue;
        }
        groups.add((
          id: c.id,
          name: names[c.id]!,
          unread: unread[c.id] ?? 0,
          closed: c.closedAt != null,
        ));
        groupMembers[c.id] = SuratViews.members(members, nameOf, me);
        continue;
      }
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
    surat = groups;
    suratMembers = groupMembers;
    peers = peerMap;
    _channelNames = names;
    _namers = namers;
    pairedPeers = [
      for (final p in peerRows.values)
        if (p.trust == trustPaired)
          (
            deviceId: p.deviceId,
            personName: p.personName,
            deviceName: p.deviceName,
          ),
    ]..sort((a, b) => a.personName.compareTo(b.personName));
    pending = [
      for (final p in await node.surat.pending())
        SuratViews.pending(
          p,
          rowsOf[p.suratId] ?? const [],
          _nameIn(p.suratId),
        ),
    ];
    final open = {for (final p in pending) p.id};
    for (final tag in _askedPending.where((t) => !open.contains(t)).toList()) {
      _askedPending.remove(tag);
      await notifier.remove(tag);
    }
    final drafts = await _db.drafts();
    awaitingApproval = drafts.length;
    this.drafts = [
      for (final m in drafts)
        DraftView(
          id: m.id,
          channelName: names[m.channelId] ?? 'Unknown',
          body: _bodyOf(m),
          createdAt: DateTime.fromMillisecondsSinceEpoch(m.createdAt),
          context: MessageContext.fromJson(m.contextJson),
        ),
    ];
    if (selectedId != null && selectedId != outboxSelectionId) {
      await _loadMessages(selectedId!, markRead: false);
    }
    notifyListeners();
  }

  /// The namer of a surat as of the last [refresh].
  String Function(String) _nameIn(String suratId) =>
      _namers[suratId] ??
      (id) => id == node.identity!.deviceId ? 'You' : 'Unknown';

  /// What a person sees for a stored row: an event's readable line, never
  /// its JSON; a message's body.
  String _bodyOf(Message m) => m.kind == 'event'
      ? SuratViews.eventText(m, _nameIn(m.channelId))
      : m.body ?? '';

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
    final channel = await (_db.select(
      _db.channels,
    )..where((c) => c.id.equals(channelId))).getSingleOrNull();
    final inSurat = channel?.kind == 'surat';
    final members = inSurat
        ? await (_db.select(
            _db.channelMembers,
          )..where((m) => m.channelId.equals(channelId))).get()
        : const <ChannelMember>[];
    final suratName = memberNamer(members, peerRows, meDeviceId: me.deviceId);
    String nameOf(String deviceId) => inSurat
        ? suratName(deviceId)
        : deviceId == me.deviceId
        ? 'You'
        : peerRows[deviceId]?.personName ?? 'Unknown';
    final rows = markRead && windowVisible()
        ? await node.messages.read(channelId, by: Reader.person)
        : await _db.channelMessages(channelId);
    DateTime? t(int? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    final views = <MessageView>[];
    for (final m in rows) {
      final mine = m.direction == 'out';
      final base = MessageView.fromRow(
        m,
        myName: me.personName,
        senderName: nameOf(m.fromDeviceId),
      );
      final event = m.kind == 'event';
      if (!mine && !event && !(inSurat && base.locked)) {
        views.add(base);
        continue;
      }
      views.add(
        MessageView(
          id: base.id,
          kind: base.kind,
          senderName: base.senderName,
          senderId: base.senderId,
          initial: base.initial,
          sentAt: base.sentAt,
          body: event ? SuratViews.eventText(m, nameOf) : base.body,
          context: base.context,
          arrivedLate: base.arrivedLate,
          locked: base.locked,
          lockedReason: inSurat && base.locked
              ? SuratViews.lockedReason(members, m.fromDeviceId)
              : null,
          mine: mine,
          receipts: [
            if (mine && !event)
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
    final closedAt = channel?.closedAt;
    final ended = inSurat && closedAt != null
        ? SuratViews.endedText(
            members,
            nameOf,
            meDeviceId: me.deviceId,
            myName: me.personName,
          )
        : null;
    if (ended != null) {
      views.add(
        MessageView(
          id: 'ended-$channelId',
          kind: 'event',
          senderName: '',
          sentAt: DateTime.fromMillisecondsSinceEpoch(closedAt!),
          body: ended,
        ),
      );
    }
    messages = views;
    gaps = [
      for (final g in await _db.gaps(channelId))
        (
          personName: inSurat
              ? suratName(g.fromDeviceId)
              : peerRows[g.fromDeviceId]?.personName ??
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
    final person = _namers.containsKey(m.channelId)
        ? _nameIn(m.channelId)(m.fromDeviceId)
        : peer?.personName ?? 'Someone';
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
    if (!_channelNames.containsKey(m.channelId)) await refresh();
    final to = _channelNames[m.channelId] ?? 'teammate';
    await notifier.show(
      NotificationText('Send to $to?', _firstLine(_bodyOf(m))),
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

  /// Drafts a new surat; it then waits for approval like any send.
  Future<void> createSurat(String name, List<String> deviceIds) =>
      node.surat.draftCreate(name, deviceIds);

  /// Answers an invite (accept) or a newcomer (approve). An answer already
  /// given elsewhere, or a surat that ended meanwhile, just refreshes.
  Future<void> decide(String id, {required bool approve}) async {
    try {
      await node.surat.decide(id, approve: approve);
    } on UnknownPending {
      // Answered elsewhere already.
    } on AlreadyApproved {
      // An approval cannot be taken back.
    } on NotAllowed {
      // The surat ended.
    }
    await refresh();
  }

  Future<void> _onSurat(SuratChange c) async {
    await refresh();
    final id = c.suratId;
    final name = _channelNames[id] ?? 'A surat';
    final nameOf = _nameIn(id);
    void open() => unawaited(select(id));
    switch (c) {
      case Invited(:final inviter):
        await _askDecision(
          PendingView(
            id: 'invite:$id:${node.identity!.deviceId}',
            suratId: id,
            kind: PendingKind.invite,
            suratName: name,
            inviter: nameOf(inviter),
          ),
        );
      case NewcomerToApprove(:final newcomer, :final inviter):
        await _askDecision(
          PendingView(
            id: 'newcomer:$id:$newcomer',
            suratId: id,
            kind: PendingKind.newcomer,
            suratName: name,
            inviter: nameOf(inviter),
            newcomer: nameOf(newcomer),
          ),
        );
      case Renamed(name: final now, :final previous):
        if (previous != null && previous != now) {
          await notifier.show(
            NotificationText('$previous is now $now', ''),
            onClick: open,
          );
        }
      case Ended():
        // Only the last member is told; a Mac whose own leave ended it is not.
        final rows = await (_db.select(
          _db.channelMembers,
        )..where((m) => m.channelId.equals(id))).get();
        final mine = rows.where((m) => m.deviceId == node.identity!.deviceId);
        if (mine.firstOrNull?.state == 'member') {
          await notifier.show(
            NotificationText("$name ended — you're the last member", ''),
            onClick: open,
          );
        }
      case MemberLeft():
      case BecameMutual():
        break;
    }
  }

  Future<void> _askDecision(PendingView p) async {
    if (!_askedPending.add(p.id)) return;
    await notifier.show(
      NotificationText(p.line, ''),
      tag: p.id,
      actions: [p.kind == PendingKind.invite ? 'Accept' : 'Approve', 'Decline'],
      onAction: (i) => unawaited(decide(p.id, approve: i == 0)),
      onClick: () => unawaited(select(p.suratId)),
    );
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
