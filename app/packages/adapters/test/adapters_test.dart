import 'package:adapters/adapters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Paket adapters löst core auf', () {
    expect(adaptersUsesCore, 'core-adapters');
  });
}
