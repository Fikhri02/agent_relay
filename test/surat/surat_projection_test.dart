import 'package:agent_relay/crypto/vouch.dart';
import 'package:agent_relay/ordering/hlc.dart';
import 'package:agent_relay/surat/surat_event.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../support/surat_side.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test(
    'a new member is named from the card of the invite that seated it',
    () async {
      now = 1700000000000;
      final alice = await Side.make('Alice');
      final bob = await Side.make('Bob');
      final eve = await Side.make('Eve');
      addTearDown(() async {
        await alice.db.close();
        await bob.db.close();
        await eve.db.close();
      });
      await alice.pair(bob);
      final draft = await alice.surat.draftCreate('Trip', [bob.id]);
      await alice.messages.approve(draft);
      final suratId = (await alice.message(draft)).channelId;
      now += 1000;
      final accepted = Hlc(now, 0).encode();
      await alice.storeIncoming(
        suratId,
        from: bob,
        hlc: accepted,
        event: const AcceptEvent(),
      );
      MemberCard named(String name) => MemberCard(
        deviceId: eve.id,
        personName: name,
        deviceName: '$name Mac',
        signPub: eve.keys.signPub,
        boxPub: eve.keys.boxPub,
        certFingerprint: 'fp-Eve',
      );
      // Bob's real invite for Eve comes first; Mallory, not a member, sends a
      // later invite for the same device under another name.
      now += 1000;
      await alice.storeIncoming(
        suratId,
        from: bob,
        hlc: Hlc(now, 0).encode(),
        event: InviteEvent(newcomer: named('Eve'), vouch: 'v', snapshot: null),
      );
      now += 1000;
      await alice.storeIncoming(
        suratId,
        from: eve,
        hlc: Hlc(now, 0).encode(),
        event: InviteEvent(
          newcomer: named('Mallory'),
          vouch: 'v',
          snapshot: null,
        ),
      );
      await alice.surat.rebuild(suratId);

      final row = (await alice.member(suratId, eve.id))!;
      expect(row.state, 'invited');
      expect(row.personName, 'Eve');
    },
  );
}
