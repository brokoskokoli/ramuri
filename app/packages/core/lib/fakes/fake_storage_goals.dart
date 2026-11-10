import '../ports/storage.dart';
import '../ports/storage_goals.dart';
import '../src/goals/training_goal.dart';
import 'fake_storage_data.dart';

class FakeGoalStore implements GoalStore {
  FakeGoalStore(this._d);
  final FakeStorageData _d;

  @override
  Future<TrainingGoal?> goal() async => _d.goal;

  @override
  Future<void> save(TrainingGoal goal, {DateTime? today}) async {
    checkGoalForStorage(goal, today: today);
    _d.goal = goal;
  }

  @override
  Future<void> delete() async {
    if (_d.goal == null) throw const StorageException(StorageFailure.notFound);
    _d.deleteGoal();
  }
}
