import 'unit_format.dart';

/// Zeit als `h:mm:ss`, unter einer Stunde `m:ss`; `null` ergibt „–“.
String formatClock(Duration? d) {
  if (d == null || d.isNegative) return UnitFormatter.noValue;
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final mm = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '${s ~/ 60}:$ss';
}
