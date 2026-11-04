import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'recorder.dart';

const cmdCh = MethodChannel('r005/cmd');
Recorder? rec;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  cmdCh.setMethodCallHandler((c) async => handle((c.arguments as Map).cast<String, dynamic>()));
  print('R005ENGINE main isolate up');
  runApp(const SizedBox());
}

Future<void> handle(Map<String, dynamic> a) async {
  print('R005CMD $a');
  try {
    switch (a['cmd']) {
      case 'start':
        final host = a['host'] as String;
        if (host == 'own' || host == 'none') {
          if (host == 'own') await hostCh.invokeMethod('startService', {'cls': 'org.runningapp.r005.r005_proto.RecordService'});
          if (a['wake'] == true) await hostCh.invokeMethod('wakeLock', {'on': true});
          rec = Recorder(a);
          await rec!.start();
        } else {
          FlutterForegroundTask.init(
            androidNotificationOptions: AndroidNotificationOptions(channelId: 'ffgt', channelName: 'ffgt'),
            iosNotificationOptions: const IOSNotificationOptions(),
            foregroundTaskOptions: ForegroundTaskOptions(
              eventAction: ForegroundTaskEventAction.nothing(),
              allowWakeLock: a['wake'] == true, allowAutoRestart: false),
          );
          await FlutterForegroundTask.saveData(key: 'cfg', value: jsonEncode(a));
          final r = await FlutterForegroundTask.startService(
            serviceTypes: const [ForegroundServiceTypes.location],
            notificationTitle: 'R005', notificationText: 'ffgt', callback: ffgtStart);
          print('R005FFGT started $r');
        }
      case 'bench': await bench(a);
      case 'verify': await verify(a['run'] as String);
    }
  } catch (e, st) { print('R005ERR $e $st'); }
}

@pragma('vm:entry-point')
void ffgtStart() => FlutterForegroundTask.setTaskHandler(H());

class H extends TaskHandler {
  Recorder? r;
  @override
  Future<void> onStart(DateTime t, TaskStarter s) async {
    print('R005ENGINE ffgt engine up');
    final c = jsonDecode(await FlutterForegroundTask.getData<String>(key: 'cfg') ?? '{}') as Map<String, dynamic>;
    r = Recorder(c);
    await r!.start();
  }
  @override void onRepeatEvent(DateTime t) {}
  @override Future<void> onDestroy(DateTime t, bool to) async { print('R005FFGT destroy timeout=$to'); }
}
