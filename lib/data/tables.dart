import 'package:drift/drift.dart';

// Enum-like columns are plain text (no CHECK constraints) so Phase 2 can add
// values such as trust `surat_contact` or kind `event` without a table rebuild.
// All timestamps are Unix epoch milliseconds.

/// A Mac this one knows. `trust`: `paired` | `mismatch` | `unpaired`.
class Peers extends Table {
  TextColumn get deviceId => text()();
  TextColumn get personName => text()();
  TextColumn get deviceName => text()();
  BlobColumn get signPub => blob()();
  BlobColumn get boxPub => blob()();
  TextColumn get certFingerprint => text()();
  TextColumn get trust => text()();
  TextColumn get lastAddress => text().nullable()();
  IntColumn get lastPort => integer().nullable()();
  IntColumn get lastSeenAt => integer().nullable()();
  IntColumn get clockSkewMs => integer().nullable()();
  IntColumn get pairedAt => integer()();

  @override
  Set<Column> get primaryKey => {deviceId};
}

/// `kind`: `private` | `surat`. `name` is null for private channels.
class Channels extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get name => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get closedAt => integer().nullable()();
  TextColumn get creatorDeviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChannelMembers extends Table {
  TextColumn get channelId => text()();
  TextColumn get deviceId => text()();
  TextColumn get joinedHlc => text()();
  TextColumn get leftHlc => text().nullable()();

  @override
  Set<Column> get primaryKey => {channelId, deviceId};
}

/// `kind`: `message`. `direction`: `in` | `out`. `status`:
/// `awaiting_approval` | `queued` | `sent` | `discarded` | `expired` |
/// `unread` | `read` | `locked`. `hlc` and `seq` stay null until approved.
@TableIndex(name: 'messages_channel_hlc', columns: {#channelId, #hlc})
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get channelId => text()();
  TextColumn get kind => text()();
  TextColumn get fromDeviceId => text()();
  IntColumn get sentAt => integer()();
  TextColumn get hlc => text().nullable()();
  IntColumn get seq => integer().nullable()();
  TextColumn get body => text().nullable()();
  TextColumn get contextJson => text().nullable()();
  TextColumn get replyTo => text().nullable()();
  TextColumn get direction => text()();
  TextColumn get status => text()();
  BoolColumn get arrivedLate => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get receivedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One sealed envelope per recipient. `status`: `queued` | `delivered` |
/// `dropped`.
class Deliveries extends Table {
  TextColumn get messageId => text()();
  TextColumn get recipientDeviceId => text()();
  TextColumn get envelopeJson => text()();
  TextColumn get status => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer()();
  IntColumn get createdAt => integer()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {messageId, recipientDeviceId};
}
