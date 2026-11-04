import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'r005_host_method_channel.dart';

abstract class R005HostPlatform extends PlatformInterface {
  /// Constructs a R005HostPlatform.
  R005HostPlatform() : super(token: _token);

  static final Object _token = Object();

  static R005HostPlatform _instance = MethodChannelR005Host();

  /// The default instance of [R005HostPlatform] to use.
  ///
  /// Defaults to [MethodChannelR005Host].
  static R005HostPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [R005HostPlatform] when
  /// they register themselves.
  static set instance(R005HostPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
