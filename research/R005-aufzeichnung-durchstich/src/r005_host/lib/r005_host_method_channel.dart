import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'r005_host_platform_interface.dart';

/// An implementation of [R005HostPlatform] that uses method channels.
class MethodChannelR005Host extends R005HostPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('r005_host');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
