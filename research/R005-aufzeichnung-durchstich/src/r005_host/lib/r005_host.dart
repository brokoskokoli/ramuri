
import 'r005_host_platform_interface.dart';

class R005Host {
  Future<String?> getPlatformVersion() {
    return R005HostPlatform.instance.getPlatformVersion();
  }
}
