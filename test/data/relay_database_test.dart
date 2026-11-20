import 'dart:io';

import 'package:agent_relay/data/relay_database.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RelayDatabase db;

  setUp(() => db = RelayDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  MessagesCompanion message({
    required String id,
    String channel = 'ch',
    String from = 'x',
    String? hlc,
    int? seq,
    String direction = 'in',
    String status = 'unread',
    int createdAt = 1000,
    int? seenAt,
    int? agentReadAt,
  }) => MessagesCompanion.insert(
    id: id,
    channelId: channel,
    kind: 'message',
    fromDeviceId: from,
    sentAt: createdAt,
    hlc: Value(hlc),
    seq: Value(seq),
    body: const Value('hi'),
    direction: direction,
    status: status,
    createdAt: createdAt,
    seenAt: Value(seenAt),
    agentReadAt: Value(agentReadAt),
  );

  Future<void> insert({
    required String id,
    String channel = 'ch',
    String from = 'x',
    String? hlc = '0000000001000-00000',
    int? seq,
    String direction = 'in',
    String status = 'unread',
    int createdAt = 1000,
    int? seenAt,
    int? agentReadAt,
  }) => db
      .into(db.messages)
      .insert(
        message(
          id: id,
          channel: channel,
          from: from,
          hlc: hlc,
          seq: seq,
          direction: direction,
          status: status,
          createdAt: createdAt,
          seenAt: seenAt,
          agentReadAt: agentReadAt,
        ),
      );

  Future<void> delivery({
    required String messageId,
    String to = 'peer',
    String status = 'queued',
    required int nextAttemptAt,
  }) => db
      .into(db.deliveries)
      .insert(
        DeliveriesCompanion.insert(
          messageId: messageId,
          recipientDeviceId: to,
          envelopeJson: '{}',
          status: status,
          nextAttemptAt: nextAttemptAt,
          createdAt: 0,
        ),
      );

  group('channelMessages', () {
    test('sort by hlc then device id, regardless of insert order', () async {
      await insert(id: 'b', hlc: '0000000002000-00000', from: 'aa');
      await insert(id: 'a', hlc: '0000000001000-00000', from: 'zz');
      await insert(id: 'c', hlc: '0000000002000-00000', from: '00');
      expect((await db.channelMessages('ch')).map((m) => m.id), [
        'a',
        'c',
        'b',
      ]);
    });

    test('drafts (hlc null) are not in the channel timeline', () async {
      await insert(
        id: 'draft',
        hlc: null,
        direction: 'out',
        status: 'awaiting_approval',
      );
      await insert(id: 'sent', direction: 'out', status: 'sent', seq: 1);
      expect((await db.channelMessages('ch')).map((m) => m.id), ['sent']);
    });

    test('only returns the requested channel', () async {
      await insert(id: 'a');
      await insert(id: 'b', channel: 'other');
      expect((await db.channelMessages('ch')).map((m) => m.id), ['a']);
    });

    group('unreadBy', () {
      // a: nobody read it · b: the person saw it in the app · c: the agent
      // read it · d: both · e: locked · f: our own outgoing message.
      setUp(() async {
        await insert(id: 'a', hlc: '0000000001000-00000');
        await insert(
          id: 'b',
          hlc: '0000000002000-00000',
          status: 'read',
          seenAt: 5,
        );
        await insert(
          id: 'c',
          hlc: '0000000003000-00000',
          status: 'read',
          agentReadAt: 5,
        );
        await insert(
          id: 'd',
          hlc: '0000000004000-00000',
          status: 'read',
          seenAt: 5,
          agentReadAt: 6,
        );
        await insert(id: 'e', hlc: '0000000005000-00000', status: 'locked');
        await insert(
          id: 'f',
          hlc: '0000000006000-00000',
          direction: 'out',
          status: 'sent',
        );
      });

      Future<List<String>> ids(Reader by) async => (await db.channelMessages(
        'ch',
        unreadBy: by,
      )).map((m) => m.id).toList();

      test('agent: still unread after the person saw it in the app', () async {
        expect(await ids(Reader.agent), ['a', 'b']);
      });

      test('person: still unread after the agent read it', () async {
        expect(await ids(Reader.person), ['a', 'c']);
      });

      test('null returns the whole timeline', () async {
        expect((await db.channelMessages('ch')).length, 6);
      });
    });
  });

  test('event rows never count as unread for either reader', () async {
    await insert(id: 'm');
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'ev',
            channelId: 'ch',
            kind: 'event',
            fromDeviceId: 'x',
            sentAt: 1,
            hlc: const Value('0000000002000-00000'),
            body: const Value('{"type":"leave"}'),
            direction: 'in',
            status: 'unread',
            createdAt: 1,
          ),
        );
    for (final by in Reader.values) {
      expect(await db.unreadCounts(by: by), {'ch': 1});
      expect((await db.channelMessages('ch', unreadBy: by)).map((m) => m.id), [
        'm',
      ]);
    }
    expect((await db.channelMessages('ch')).map((m) => m.id), ['m', 'ev']);
  });

  test('unreadCounts counts per reader, per channel', () async {
    await insert(id: 'a');
    await insert(id: 'b', status: 'read', seenAt: 5);
    await insert(id: 'c', status: 'read', seenAt: 5, agentReadAt: 6);
    await insert(id: 'd', channel: 'ch2', status: 'read', agentReadAt: 5);
    await insert(id: 'e', channel: 'ch3', status: 'locked');
    await insert(id: 'f', channel: 'ch4', direction: 'out', status: 'sent');
    await insert(id: 'g', channel: 'ch5', hlc: null);
    expect(await db.unreadCounts(by: Reader.agent), {'ch': 2});
    expect(await db.unreadCounts(by: Reader.person), {'ch': 1, 'ch2': 1});
  });

  test('gaps reports missing sequence numbers per incoming sender', () async {
    // seq 1,2,4 from 'x' -> missing 1
    await insert(id: 'x1', from: 'x', seq: 1);
    await insert(id: 'x2', from: 'x', seq: 2);
    await insert(id: 'x4', from: 'x', seq: 4);
    // 'y' complete -> not reported
    await insert(id: 'y1', from: 'y', seq: 1);
    await insert(id: 'y2', from: 'y', seq: 2);
    // own outgoing messages are never gaps
    await insert(id: 'me1', from: 'me', seq: 1, direction: 'out');
    await insert(id: 'me3', from: 'me', seq: 3, direction: 'out');
    // other channel ignored
    await insert(id: 'o5', channel: 'other', from: 'x', seq: 5);
    expect(await db.gaps('ch'), [(fromDeviceId: 'x', missing: 1)]);
  });

  test('insertIncomingIfNew is idempotent', () async {
    final m1 = message(id: 'm1', hlc: '0000000001000-00000', seq: 1);
    expect(await db.insertIncomingIfNew(m1), isTrue);
    expect(await db.insertIncomingIfNew(m1), isFalse);
    expect((await db.channelMessages('ch')).length, 1);
  });

  test('nextSeq starts at 1 and counts per sender per channel', () async {
    expect(await db.nextSeq('ch', 'me'), 1);
    await insert(id: 'a', from: 'me', seq: 1, direction: 'out', status: 'sent');
    await insert(id: 'b', from: 'me', seq: 2, direction: 'out', status: 'sent');
    // draft without a seq does not count
    await insert(
      id: 'd',
      from: 'me',
      hlc: null,
      direction: 'out',
      status: 'awaiting_approval',
    );
    await insert(id: 'c', from: 'peer', seq: 7);
    await insert(id: 'e', channel: 'other', from: 'me', seq: 9);
    expect(await db.nextSeq('ch', 'me'), 3);
    expect(await db.nextSeq('ch', 'peer'), 8);
    expect(await db.nextSeq('other', 'me'), 10);
    expect(await db.nextSeq('other', 'peer'), 1);
  });

  test(
    'dueDeliveries returns queued deliveries whose nextAttemptAt has come',
    () async {
      await delivery(messageId: 'past', nextAttemptAt: 500);
      await delivery(messageId: 'now', nextAttemptAt: 1000);
      await delivery(messageId: 'future', nextAttemptAt: 1001);
      await delivery(messageId: 'done', status: 'delivered', nextAttemptAt: 0);
      await delivery(messageId: 'gone', status: 'dropped', nextAttemptAt: 0);
      expect((await db.dueDeliveries(1000)).map((d) => d.messageId), [
        'past',
        'now',
      ]);
    },
  );

  test('drafts returns outgoing messages awaiting approval', () async {
    await insert(
      id: 'd1',
      hlc: null,
      direction: 'out',
      status: 'awaiting_approval',
      createdAt: 2000,
    );
    await insert(
      id: 'd0',
      hlc: null,
      direction: 'out',
      status: 'awaiting_approval',
      createdAt: 1000,
    );
    await insert(id: 'q', direction: 'out', status: 'queued', seq: 1);
    await insert(id: 'x', hlc: null, direction: 'out', status: 'discarded');
    await insert(id: 'in', status: 'unread');
    expect((await db.drafts()).map((m) => m.id), ['d0', 'd1']);
  });

  test('peer keys round-trip as blobs', () async {
    await db
        .into(db.peers)
        .insert(
          PeersCompanion.insert(
            deviceId: 'dev',
            personName: 'Amir',
            deviceName: 'Amir MBP',
            signPub: Uint8List.fromList([1, 2, 3]),
            boxPub: Uint8List.fromList([4, 5, 6]),
            certFingerprint: 'fp',
            trust: 'paired',
            pairedAt: 1,
          ),
        );
    final peer = await db.select(db.peers).getSingle();
    expect(peer.signPub, [1, 2, 3]);
    expect(peer.boxPub, [4, 5, 6]);
    expect(peer.lastSeenAt, isNull);
  });

  test('gaps start at a sender\'s first stored seq', () async {
    await insert(id: 'x41', from: 'x', seq: 41);
    await insert(id: 'x42', from: 'x', seq: 42);
    await insert(id: 'x44', from: 'x', seq: 44);
    expect(await db.gaps('ch'), [(fromDeviceId: 'x', missing: 1)]);
  });

  test('gaps ignore event rows', () async {
    await insert(id: 'x1', from: 'x', seq: 1);
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'ev9',
            channelId: 'ch',
            kind: 'event',
            fromDeviceId: 'x',
            sentAt: 1,
            hlc: const Value('0000000001000-00000'),
            seq: const Value(9),
            direction: 'in',
            status: 'read',
            createdAt: 1,
          ),
        );
    expect(await db.gaps('ch'), isEmpty);
  });

  test('insertOrUnlock fills a locked placeholder and never overwrites a '
      'readable row', () async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'm1',
            channelId: 'ch',
            kind: 'message',
            fromDeviceId: 'x',
            sentAt: 1,
            direction: 'in',
            status: 'locked',
            createdAt: 1,
          ),
        );
    MessagesCompanion fill(String body) => MessagesCompanion.insert(
      id: 'm1',
      channelId: 'ch',
      kind: 'message',
      fromDeviceId: 'x',
      sentAt: 1,
      body: Value(body),
      direction: 'in',
      status: 'unread',
      createdAt: 2,
    );
    expect(await db.insertOrUnlock(fill('hi')), isTrue);
    var row = await (db.select(
      db.messages,
    )..where((m) => m.id.equals('m1'))).getSingle();
    expect(row.body, 'hi');
    expect(row.status, 'unread');
    expect(await db.insertOrUnlock(fill('other')), isFalse);
    row = await (db.select(
      db.messages,
    )..where((m) => m.id.equals('m1'))).getSingle();
    expect(row.body, 'hi');
    // a brand-new id is inserted
    expect(
      await db.insertOrUnlock(fill('new').copyWith(id: const Value('m2'))),
      isTrue,
    );
  });

  test('insertOrUnlock leaves a locked row of another sender or channel '
      'untouched', () async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'm1',
            channelId: 'ch',
            kind: 'message',
            fromDeviceId: 'x',
            sentAt: 1,
            direction: 'in',
            status: 'locked',
            createdAt: 1,
          ),
        );
    MessagesCompanion fill({String ch = 'ch', String from = 'x'}) =>
        MessagesCompanion.insert(
          id: 'm1',
          channelId: ch,
          kind: 'message',
          fromDeviceId: from,
          sentAt: 1,
          body: const Value('forged'),
          direction: 'in',
          status: 'unread',
          createdAt: 2,
        );
    expect(await db.insertOrUnlock(fill(from: 'y')), isFalse);
    expect(await db.insertOrUnlock(fill(ch: 'other')), isFalse);
    final row = await (db.select(
      db.messages,
    )..where((m) => m.id.equals('m1'))).getSingle();
    expect(row.status, 'locked');
    expect(row.body, isNull);
    expect(row.fromDeviceId, 'x');
  });

  test('migration v1 to v2 keeps rows and marks private members mutually '
      'approved', () async {
    final dir = await Directory.systemTemp.createTemp('agent_relay_mig');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/relay.sqlite');
    final raw = sql.sqlite3.open(file.path);
    raw.execute('''
CREATE TABLE channels (
  id TEXT NOT NULL, kind TEXT NOT NULL, name TEXT NULL,
  created_at INTEGER NOT NULL, closed_at INTEGER NULL,
  creator_device_id TEXT NULL, PRIMARY KEY (id));
CREATE TABLE channel_members (
  channel_id TEXT NOT NULL, device_id TEXT NOT NULL,
  joined_hlc TEXT NOT NULL, left_hlc TEXT NULL,
  PRIMARY KEY (channel_id, device_id));
CREATE TABLE peers (
  device_id TEXT NOT NULL, person_name TEXT NOT NULL,
  device_name TEXT NOT NULL, sign_pub BLOB NOT NULL, box_pub BLOB NOT NULL,
  cert_fingerprint TEXT NOT NULL, trust TEXT NOT NULL,
  last_address TEXT NULL, last_port INTEGER NULL, last_seen_at INTEGER NULL,
  clock_skew_ms INTEGER NULL, paired_at INTEGER NOT NULL,
  PRIMARY KEY (device_id));
CREATE TABLE messages (
  id TEXT NOT NULL, channel_id TEXT NOT NULL, kind TEXT NOT NULL,
  from_device_id TEXT NOT NULL, sent_at INTEGER NOT NULL, hlc TEXT NULL,
  seq INTEGER NULL, body TEXT NULL, context_json TEXT NULL,
  reply_to TEXT NULL, direction TEXT NOT NULL, status TEXT NOT NULL,
  arrived_late INTEGER NOT NULL DEFAULT 0
    CHECK (arrived_late IN (0, 1)),
  created_at INTEGER NOT NULL, received_at INTEGER NULL,
  seen_at INTEGER NULL, agent_read_at INTEGER NULL, PRIMARY KEY (id));
CREATE INDEX messages_channel_hlc ON messages (channel_id, hlc);
CREATE TABLE deliveries (
  message_id TEXT NOT NULL, recipient_device_id TEXT NOT NULL,
  envelope_json TEXT NOT NULL, status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL, last_error TEXT NULL,
  delivered_at INTEGER NULL, seen_at INTEGER NULL,
  agent_read_at INTEGER NULL, PRIMARY KEY (message_id, recipient_device_id));
INSERT INTO channels (id, kind, created_at) VALUES ('c1', 'private', 1);
INSERT INTO channel_members (channel_id, device_id, joined_hlc)
  VALUES ('c1', 'd1', '0000000001000-00000');
PRAGMA user_version = 1;
''');
    raw.close();

    final migrated = RelayDatabase(NativeDatabase(file));
    addTearDown(migrated.close);
    final row = await migrated.select(migrated.channelMembers).getSingle();
    expect(row.deviceId, 'd1');
    expect(row.state, 'member');
    expect(row.myApproval, 'approved');
    expect(row.theirApproval, 'approved');
    expect(row.inviterDeviceId, isNull);
    expect(row.personName, isNull);
  });

  test(
    'a rollback does not drop after-commit work another flow queued',
    () async {
      final ran = <String>[];
      Future<void> work() async => ran.add('work');
      // Two flows overlap: the first commits while the second is still open,
      // so its work waits for the outermost level; the second then rolls back.
      final first = db.committing(() async => db.afterCommit(work));
      final second = db.committing<void>(() async => throw StateError('no'));
      await first;
      await expectLater(second, throwsStateError);
      expect(ran, ['work']);
    },
  );
}
