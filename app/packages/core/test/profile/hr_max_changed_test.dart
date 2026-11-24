import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _key = Uint8List.fromList(List.filled(32, 7));
final _t0 = DateTime.utc(2026, 11, 10, 7, 12);

void main() {
  test(
    'Änderung der HFmax setzt den Zeitpunkt (PAR-236), sonst nicht',
    () async {
      final s = await FakeStorage().open(_key);
      final clock = FakeClock(_t0);
      final svc = ProfileService(s.profile, clock, settings: s.settings);
      await svc.save(
        const ProfileRecord(birthYear: 1990, maxHeartRateBpm: 185),
      );
      expect(
        await s.settings.get(profileHrMaxChangedAtKey),
        _t0.toIso8601String(),
      );
      // Gleiche HFmax, anderes Feld: unverändert.
      clock.advance(const Duration(days: 1));
      await svc.save(
        const ProfileRecord(
          birthYear: 1990,
          maxHeartRateBpm: 185,
          restingHeartRateBpm: 55,
        ),
      );
      expect(
        await s.settings.get(profileHrMaxChangedAtKey),
        _t0.toIso8601String(),
      );
      // Neue HFmax: neuer Zeitpunkt.
      await svc.save(
        const ProfileRecord(
          birthYear: 1990,
          maxHeartRateBpm: 192,
          restingHeartRateBpm: 55,
        ),
      );
      expect(
        await s.settings.get(profileHrMaxChangedAtKey),
        clock.now().toUtc().toIso8601String(),
      );
    },
  );

  test(
    'ohne eingetragene HFmax zählt die Näherung aus dem Geburtsjahr',
    () async {
      final s = await FakeStorage().open(_key);
      final clock = FakeClock(_t0);
      final svc = ProfileService(s.profile, clock, settings: s.settings);
      await svc.save(const ProfileRecord(restingHeartRateBpm: 55));
      expect(await s.settings.get(profileHrMaxChangedAtKey), isNull);
      await svc.save(
        const ProfileRecord(restingHeartRateBpm: 55, birthYear: 1990),
      );
      expect(await s.settings.get(profileHrMaxChangedAtKey), isNotNull);
    },
  );
}
