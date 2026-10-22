import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models.dart';

const tfMs = {'1m': 60000, '3m': 180000, '5m': 300000, '15m': 900000, '30m': 1800000, '1h': 3600000, '4h': 14400000};
const _bybitTf = {'1m': '1', '3m': '3', '5m': '5', '15m': '15', '30m': '30', '1h': '60', '4h': '240'};

/// Free public market data. No API key. Tries several mirrors, then Bybit.
class MarketData {
  static const hosts = [
    'https://data-api.binance.vision',
    'https://api.binance.com',
    'https://api1.binance.com',
    'https://api2.binance.com',
  ];
  String lastSource = '';

  Future<dynamic> _getJson(String url) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(r.body);
  }

  Future<List<Candle>> klines(String sym, String tf, {int limit = 500, bool closedOnly = true}) async {
    Object? err;
    for (final h in hosts) {
      try {
        final j = await _getJson('$h/api/v3/klines?symbol=$sym&interval=$tf&limit=$limit') as List;
        lastSource = h;
        final c = j
            .map((e) => Candle(e[0] as int, double.parse(e[1]), double.parse(e[2]), double.parse(e[3]),
                double.parse(e[4]), double.parse(e[5])))
            .toList();
        return _trim(c, tf, closedOnly);
      } catch (e) {
        err = e;
      }
    }
    try {
      final j = await _getJson(
          'https://api.bybit.com/v5/market/kline?category=linear&symbol=$sym&interval=${_bybitTf[tf]}&limit=$limit');
      final list = (j['result']['list'] as List).reversed.toList();
      lastSource = 'bybit';
      final c = list
          .map((e) => Candle(int.parse(e[0]), double.parse(e[1]), double.parse(e[2]), double.parse(e[3]),
              double.parse(e[4]), double.parse(e[5])))
          .toList();
      return _trim(c, tf, closedOnly);
    } catch (e) {
      throw Exception('no data source reachable ($err / $e) - try a VPN on the phone');
    }
  }

  List<Candle> _trim(List<Candle> c, String tf, bool closedOnly) {
    if (closedOnly && c.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (c.last.t + (tfMs[tf] ?? 900000) > now) c.removeLast();
    }
    return c;
  }

  Future<Map<String, double>> allPrices() async {
    for (final h in hosts) {
      try {
        final j = await _getJson('$h/api/v3/ticker/price') as List;
        return {for (final e in j) e['symbol'] as String: double.parse(e['price'])};
      } catch (_) {}
    }
    final j = await _getJson('https://api.bybit.com/v5/market/tickers?category=linear');
    return {for (final e in j['result']['list'] as List) e['symbol'] as String: double.parse(e['lastPrice'])};
  }

  static const _skip = ['UPUSDT', 'DOWNUSDT', 'BULLUSDT', 'BEARUSDT'];
  static const _stable = ['USDC', 'FDUSD', 'TUSD', 'USDP', 'DAI', 'BUSD', 'EUR', 'EURI', 'USD1', 'AEUR', 'XUSD', 'PAXG'];

  /// Whole USDT market ranked by 24h quote volume (top [n]).
  Future<List<String>> topSymbols(int n) async {
    for (final h in hosts) {
      try {
        final j = await _getJson('$h/api/v3/ticker/24hr') as List;
        final rows = j.where((e) {
          final s = e['symbol'] as String;
          if (!s.endsWith('USDT')) return false;
          final base = s.substring(0, s.length - 4);
          if (_stable.contains(base)) return false;
          if (_skip.any((k) => s.endsWith(k))) return false;
          return true;
        }).toList();
        rows.sort((a, b) => double.parse(b['quoteVolume']).compareTo(double.parse(a['quoteVolume'])));
        return rows.take(n).map<String>((e) => e['symbol'] as String).toList();
      } catch (_) {}
    }
    return ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'ADAUSDT', 'LINKUSDT'];
  }
}
