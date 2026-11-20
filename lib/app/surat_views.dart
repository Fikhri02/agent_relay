import '../data/relay_database.dart';
import '../surat/event_line.dart';
import '../surat/surat_projection.dart';
import '../surat/surat_service.dart' show PendingItem;
import '../ui/channels/message_view.dart';
import '../ui/surat/pending_panel.dart';

/// The pieces of a surat the screens show, built from its member rows and a
/// namer (`memberNamer`). Pure, so the controller stays small.
abstract final class SuratViews {
  /// The readable line of an event row; never the stored JSON.
  static String eventText(Message m, String Function(String) nameOf) {
    final event = SuratProjection.decode(m.body);
    if (event == null) return 'Surat update';
    return eventLine(event, from: m.fromDeviceId, nameOf: nameOf);
  }

  /// Same rule as the local API's `lockedReason`: their approval of me is
  /// missing, else mine of them.
  static LockedReason lockedReason(
    Iterable<ChannelMember> rows,
    String sender,
  ) {
    final row = rows.where((m) => m.deviceId == sender).firstOrNull;
    return row?.theirApproval == 'approved'
        ? LockedReason.youHaveNotApprovedThem
        : LockedReason.theyHaveNotApprovedYou;
  }

  /// Current members for the status line: me first ("You"), then the others
  /// by name.
  static List<String> members(
    Iterable<ChannelMember> rows,
    String Function(String) nameOf,
    String meDeviceId,
  ) {
    final current = rows.where((m) => m.state == 'member');
    final others = [
      for (final m in current)
        if (m.deviceId != meDeviceId) nameOf(m.deviceId),
    ]..sort();
    return [
      if (current.any((m) => m.deviceId == meDeviceId)) nameOf(meDeviceId),
      ...others,
    ];
  }

  /// "Surat ended — {a} is the last member", naming me by my person name
  /// ("You is" does not read). Null when no member is left.
  static String? endedText(
    Iterable<ChannelMember> rows,
    String Function(String) nameOf, {
    required String meDeviceId,
    required String myName,
  }) {
    final left = rows.where((m) => m.state == 'member').toList();
    if (left.length != 1) return null;
    final last = left.single.deviceId;
    return endedLine(last == meDeviceId ? myName : nameOf(last));
  }

  static PendingView pending(
    PendingItem p,
    Iterable<ChannelMember> rows,
    String Function(String) nameOf,
  ) {
    final inviter = rows
        .where((m) => m.deviceId == p.deviceId)
        .firstOrNull
        ?.inviterDeviceId;
    return PendingView(
      id: p.id,
      suratId: p.suratId,
      kind: p.kind == 'invite' ? PendingKind.invite : PendingKind.newcomer,
      suratName: p.suratName,
      inviter: inviter == null ? p.inviterName : nameOf(inviter),
      newcomer: nameOf(p.deviceId),
      declined: p.declined,
    );
  }
}
