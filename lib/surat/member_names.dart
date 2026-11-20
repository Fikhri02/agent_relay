import '../data/relay_database.dart';

/// Device id to display name inside one surat: [me] for my own device, the
/// person name otherwise, plus " ({device})" where two members of the surat
/// share a person name (a member is a device). Member rows win over peers.
String Function(String deviceId) memberNamer(
  Iterable<ChannelMember> rows,
  Map<String, Peer> peers, {
  required String meDeviceId,
  String me = 'You',
}) {
  final person = <String, String>{};
  final device = <String, String>{};
  for (final m in rows) {
    final p = peers[m.deviceId];
    person[m.deviceId] = m.personName ?? p?.personName ?? 'Unknown';
    device[m.deviceId] = m.deviceName ?? p?.deviceName ?? '';
  }
  final counts = <String, int>{};
  for (final n in person.values) {
    counts[n] = (counts[n] ?? 0) + 1;
  }
  return (id) {
    if (id == meDeviceId) return me;
    final n = person[id] ?? peers[id]?.personName ?? 'Unknown';
    return (counts[n] ?? 0) > 1 && (device[id] ?? '').isNotEmpty
        ? '$n (${device[id]})'
        : n;
  };
}
