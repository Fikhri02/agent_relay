/// One conversation as the tab strip and the tray menu show it.
typedef ChannelSummary = ({String id, String name, int unread, bool closed});

/// One "waiting for N message(s) from {name}" banner (from the DB `gaps`).
typedef GapView = ({String personName, int missing});

/// The peer behind a private channel, for the stage's status line.
typedef ChannelPeer = ({String deviceName, PeerStatus status});

/// Reachability of a paired Mac.
sealed class PeerStatus {
  const PeerStatus();
}

class PeerOnline extends PeerStatus {
  const PeerOnline();
}

class PeerOffline extends PeerStatus {
  const PeerOffline();
}

/// Its clock differs from ours beyond the signature window.
class PeerClockSkew extends PeerStatus {
  const PeerClockSkew(this.ms);
  final int ms;
}

/// It presented a different identity key than the one pinned at pairing.
class PeerIdentityChanged extends PeerStatus {
  const PeerIdentityChanged();
}

/// Lower-case status words, as the status line shows them after the name.
String peerStatusLabel(PeerStatus status) => switch (status) {
  PeerOnline() => 'online',
  PeerOffline() => 'offline',
  PeerClockSkew(:final ms) => 'clocks differ by ${(ms.abs() / 1000).round()} s',
  PeerIdentityChanged() => 'identity changed — pair again',
};
