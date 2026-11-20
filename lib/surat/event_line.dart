import 'surat_event.dart';

/// The readable line for one membership event, e.g. "Sam invited Lia".
///
/// [from] is the event's sender and [nameOf] turns a device id into the name
/// shown for it ("You" for my own device, "{person} ({device})" where two
/// members share a person name). [suratName] overrides the name inside a
/// create event (the surat's current name).
String eventLine(
  SuratEvent e, {
  required String from,
  required String Function(String deviceId) nameOf,
  String? suratName,
}) {
  final a = nameOf(from);
  return switch (e) {
    CreateEvent() => '$a created ${suratName ?? e.name}',
    InviteEvent() => '$a invited ${nameOf(e.newcomer.deviceId)}',
    AcceptEvent() => '$a joined',
    DeclineInviteEvent() => '$a declined the invite',
    ApproveEvent() => '$a approved ${nameOf(e.deviceId)}',
    DeclineEvent() => '$a declined ${nameOf(e.deviceId)}',
    LeaveEvent() => '$a left',
    RenameEvent() => '$a renamed the surat to ${e.name}',
  };
}

/// The line the last member sees when the surat ends.
String endedLine(String lastMember) =>
    'Surat ended — $lastMember is the last member';
