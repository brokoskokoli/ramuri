/// Zahl und Einheit eines fertig formatierten Werts: Hat [text] die [unit] als
/// Endung, steht sie getrennt; sonst (etwa „–“ oder „noch keine Daten“) ist der
/// ganze Text der Wert.
(String, String?) splitUnit(String text, String unit) {
  final suffix = ' $unit';
  if (text.length > suffix.length && text.endsWith(suffix)) {
    return (text.substring(0, text.length - suffix.length), unit);
  }
  return (text, null);
}
