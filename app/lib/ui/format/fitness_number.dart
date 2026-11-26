/// Zahl mit einer Nachkommastelle, im Deutschen mit Komma; mit [sign] steht
/// bei positiven Werten ein Plus (FR-0087: 5,56 wird „5,6“). Das Vorzeichen
/// richtet sich nach dem gerundeten Wert: Was zu 0,0 rundet, steht ohne
/// Vorzeichen da. Minus ist das echte Minuszeichen „−“.
String fitnessNumber(bool german, double v, {bool sign = false}) {
  final rounded = double.parse(v.toStringAsFixed(1));
  final digits = rounded.abs().toStringAsFixed(1);
  final text = rounded < 0
      ? '\u2212$digits'
      : (sign && rounded > 0 ? '+$digits' : digits);
  return german ? text.replaceAll('.', ',') : text;
}
