import 'package:agent_relay/data/relay_database.dart';
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

      Future<List<String>> ids(Reader by) async =>
          (await db.channelMessages('ch', unreadBy: by)).map((m) => m.id).toList();

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
}
