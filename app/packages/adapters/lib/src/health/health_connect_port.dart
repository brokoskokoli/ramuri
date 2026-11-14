/// Der Port und seine Typen liegen seit WP32 Teil C in `core` (Import ohne Flutter testbar); hier nur die
/// Weiterleitung, damit die Adapter-Dateien und ihre Importe unverändert bleiben.
library;

export 'package:core/core.dart'
    show
        HealthConnectPort,
        HealthDataKind,
        HealthHeartRateSample,
        HealthPage,
        HealthReadError,
        HealthReadException,
        HealthRecord,
        HealthSdkStatus,
        HealthSleepStage;
