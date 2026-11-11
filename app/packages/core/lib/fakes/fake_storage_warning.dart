import '../ports/storage_warning.dart';
import 'fake_storage_data.dart';

class FakeWarningStore implements WarningStore {
  FakeWarningStore(this._d);
  final FakeStorageData _d;

  @override
  Future<WarningSignal?> read() async => _d.warning;

  @override
  Future<void> set(WarningSignal warning) async {
    checkWarningForStorage(warning);
    _d.warning = warning;
  }

  @override
  Future<void> lift() async {
    _d.warning = null;
  }
}
