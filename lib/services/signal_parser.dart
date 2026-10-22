import '../core/models.dart';

class ParsedSignal {
  String? symbol;
  Side? side;
  double? entry, entry2, sl, leverage;
  List<double> tps = [];
  bool get complete => symbol != null && side != null;
}

ParsedSignal parseSignal(String raw) {
  final t = raw.replaceAll(',', '').replaceAll('٫', '.');
  final s = ParsedSignal();
  const stop = {'LONG', 'SHORT', 'BUY', 'SELL', 'ENTRY', 'TP', 'SL', 'STOP', 'LOSS', 'TARGET', 'SIGNAL', 'LEVERAGE', 'USDT', 'FUTURES', 'SPOT', 'CROSS', 'ISOLATED', 'TAKE', 'PROFIT', 'ZONE'};
  final pair = RegExp(r'#?\$?([A-Za-z0-9]{2,12})\s*[/\-_ ]?\s*(USDT|USD)\b', caseSensitive: false).firstMatch(t);
  if (pair != null) {
    s.symbol = '${pair.group(1)!.toUpperCase()}USDT';
  } else {
    for (final m in RegExp(r'#\$?([A-Za-z0-9]{2,12})|\$([A-Za-z0-9]{2,12})').allMatches(t)) {
      final w = (m.group(1) ?? m.group(2))!.toUpperCase();
      if (!stop.contains(w)) {
        s.symbol = '${w}USDT';
        break;
      }
    }
  }
  final low = t.toLowerCase();
  final short = RegExp(r'short|sell|شورت|فروش').hasMatch(low);
  final long = RegExp(r'long|buy|لانگ|خرید').hasMatch(low);
  if (short && !long) {
    s.side = Side.short;
  } else if (long && !short) {
    s.side = Side.long;
  } else if (short && long) {
    s.side = low.indexOf(RegExp(r'short|sell|شورت|فروش')) < low.indexOf(RegExp(r'long|buy|لانگ|خرید')) ? Side.short : Side.long;
  }
  const num = r'(\d+(?:\.\d+)?)';
  final en = RegExp('(?:entry|enter|buy zone|buy|sell|ورود|قیمت ورود)[^0-9]{0,25}$num(?:\\s*(?:-|–|to|تا)\\s*$num)?', caseSensitive: false).firstMatch(t);
  if (en != null) {
    s.entry = double.tryParse(en.group(1)!);
    if (en.group(2) != null) s.entry2 = double.tryParse(en.group(2)!);
  }
  final sl = RegExp('(?:sl|stop[ -]?loss|stop|حد ضرر|استاپ)[^0-9]{0,15}$num', caseSensitive: false).firstMatch(t);
  if (sl != null) s.sl = double.tryParse(sl.group(1)!);
  for (final m in RegExp('(?:tp|target|take profit|تارگت|هدف)\\s*\\d?[^0-9]{0,12}$num', caseSensitive: false).allMatches(t)) {
    final v = double.tryParse(m.group(1)!);
    if (v != null) s.tps.add(v);
  }
  final lev = RegExp(r'(?:leverage|lev|لورج|اهرم)[^0-9]{0,10}(\d+)|(\d+)\s*[xX]\b', caseSensitive: false).firstMatch(t);
  if (lev != null) s.leverage = double.tryParse(lev.group(1) ?? lev.group(2) ?? '');
  return s;
}
