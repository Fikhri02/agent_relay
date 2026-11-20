// Adapted from gallery_bridge apps/macos/lib/app/login_item.dart
import 'package:flutter/services.dart';

/// "Launch at Login" through SMAppService (macOS 13+), via a channel in
/// MainFlutterWindow.swift.
class LoginItem {
  const LoginItem([
    this._channel = const MethodChannel('agentrelay/login_item'),
  ]);

  final MethodChannel _channel;

  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on PlatformException {
      // Report what macOS now says.
    } on MissingPluginException {
      return false;
    }
    return isEnabled();
  }
}
