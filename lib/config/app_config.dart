import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Where this instance keeps its data and which ports it serves. Env vars let
/// several instances run on one Mac (`tool/run_two.sh`).
class AppConfig {
  const AppConfig({
    required this.dataDir,
    required this.peerPort,
    required this.localPort,
    required this.keychainPrefix,
  });

  static const defaultPeerPort = 8790;
  static const defaultLocalPort = 8791;
  static const baseKeychainPrefix = 'agent-relay';

  final Directory dataDir;
  final int peerPort;
  final int localPort;
  final String keychainPrefix;

  static AppConfig fromEnvironment(
    Map<String, String> env, {
    required String homeDir,
  }) {
    final home = env['AGENT_RELAY_HOME'];
    final dataDir = home != null && home.isNotEmpty
        ? Directory(home)
        : Directory('$homeDir/Library/Application Support/AgentRelay');
    final prefix = home != null && home.isNotEmpty
        ? '$baseKeychainPrefix-${sha256.convert(utf8.encode(home)).toString().substring(0, 8)}'
        : baseKeychainPrefix;
    return AppConfig(
      dataDir: dataDir,
      peerPort:
          int.tryParse(env['AGENT_RELAY_PEER_PORT'] ?? '') ?? defaultPeerPort,
      localPort:
          int.tryParse(env['AGENT_RELAY_LOCAL_PORT'] ?? '') ?? defaultLocalPort,
      keychainPrefix: prefix,
    );
  }
}
