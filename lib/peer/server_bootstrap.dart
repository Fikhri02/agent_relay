// Adapted from gallery_bridge apps/macos/lib/core/server/server_bootstrap.dart
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class ServerBootstrap {
  ServerBootstrap({
    required this.certPath,
    required this.keyPath,
    required this.port,
    InternetAddress? address,
  }) : address = address ?? InternetAddress.anyIPv4;

  final String certPath;
  final String keyPath;
  final int port;
  final InternetAddress address;
  HttpServer? _server;

  int get boundPort => _server?.port ?? 0;
  bool get isRunning => _server != null;

  Future<void> start({required Handler handler}) async {
    final context = SecurityContext()
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);
    _server = await shelf_io.serve(
      handler,
      address,
      port,
      securityContext: context,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
