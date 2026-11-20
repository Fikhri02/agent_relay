import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;

import '../../data/relay_database.dart';

/// Where the sender was working: shown as the memo's Ref line.
class MessageContext {
  const MessageContext({this.repo, this.branch, this.commit});

  final String? repo;
  final String? branch;
  final String? commit;

  /// Parses the stored `contextJson`; null when absent, invalid or empty.
  static MessageContext? fromJson(String? json) {
    if (json == null) return null;
    try {
      final map = jsonDecode(json);
      if (map is! Map) return null;
      String? s(String k) {
        final v = map[k];
        return v == null || '$v'.isEmpty ? null : '$v';
      }

      final ctx = MessageContext(
        repo: s('repo'),
        branch: s('branch'),
        commit: s('commit'),
      );
      return ctx.line == null ? null : ctx;
    } on FormatException {
      return null;
    }
  }

  /// `repo · branch · commit`, skipping missing parts.
  String? get line {
    final parts = [repo, branch, commit].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// What happened to my message at one recipient's Mac.
typedef ReceiptView = ({
  String personName,
  DateTime? deliveredAt,
  DateTime? seenAt,
  DateTime? agentReadAt,
});

/// A message as the screens show it.
class MessageView {
  const MessageView({
    required this.id,
    required this.senderName,
    required this.sentAt,
    this.senderId = '',
    String? initial,
    this.body,
    this.context,
    this.arrivedLate = false,
    this.locked = false,
    this.mine = false,
    this.receipts = const [],
  }) : _initial = initial; // ignore: prefer_initializing_formals, named params can't be private

  static String _initialOf(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  /// From a stored row. [senderName] is resolved by the caller ("You" for
  /// outgoing messages, the peer's person name otherwise).
  /// [myName] gives my own memos my initial rather than the "Y" of "You".
  factory MessageView.fromRow(
    Message row, {
    required String senderName,
    String? myName,
  }) => MessageView(
    id: row.id,
    senderName: senderName,
    senderId: row.fromDeviceId,
    initial: row.direction == 'out' && myName != null
        ? _initialOf(myName)
        : null,
    sentAt: DateTime.fromMillisecondsSinceEpoch(row.sentAt),
    body: row.body,
    context: MessageContext.fromJson(row.contextJson),
    arrivedLate: row.arrivedLate,
    locked: row.status == 'locked',
    mine: row.direction == 'out',
  );

  final String id;
  final String senderName;

  /// The sender's device id: picks their colour. Empty when unknown.
  final String senderId;

  /// The letter on the sender's disc.
  String get initial => _initial ?? _initialOf(senderName);
  final String? _initial;
  final DateTime sentAt;
  final String? body;
  final MessageContext? context;
  final bool arrivedLate;
  final bool locked;
  final bool mine;

  /// One per recipient, for my own messages.
  final List<ReceiptView> receipts;
}
