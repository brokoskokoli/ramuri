import '../ports/health_connect.dart';

class FakeHealthConnect implements HealthConnect {
  FakeHealthConnect([this.state = HealthConnectAvailability.available]);

  HealthConnectAvailability state;

  @override
  Future<HealthConnectAvailability> availability() async => state;
}
