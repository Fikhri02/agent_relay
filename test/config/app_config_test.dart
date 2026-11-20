import 'package:agent_relay/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults', () {
    final c = AppConfig.fromEnvironment({}, homeDir: '/Users/x');
    expect(c.dataDir.path, '/Users/x/Library/Application Support/AgentRelay');
    expect(c.peerPort, 8790);
    expect(c.localPort, 8791);
    expect(c.keychainPrefix, 'agent-relay');
  });

  test('env overrides give a separate keychain prefix', () {
    final c = AppConfig.fromEnvironment({
      'AGENT_RELAY_HOME': '/tmp/r2',
      'AGENT_RELAY_PEER_PORT': '8792',
      'AGENT_RELAY_LOCAL_PORT': '8793',
    }, homeDir: '/Users/x');
    expect(c.dataDir.path, '/tmp/r2');
    expect(c.peerPort, 8792);
    expect(c.localPort, 8793);
    expect(c.keychainPrefix, startsWith('agent-relay-'));
    expect(c.keychainPrefix, isNot('agent-relay'));
  });
}
