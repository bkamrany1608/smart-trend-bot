import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../core/models.dart';

/// Binance USDT-M Futures (testnet or live). One-way position mode.
class BinanceFutures {
  final String key, secret;
  final bool testnet;
  BinanceFutures(this.key, this.secret, this.testnet);
  String get base => testnet ? 'https://testnet.binancefuture.com' : 'https://fapi.binance.com';
  bool get ok => key.isNotEmpty && secret.isNotEmpty;
  final Map<String, double> _step = {};

  Future<dynamic> _req(String method, String path, Map<String, String> q, {bool signed = true}) async {
    if (signed) {
      q['timestamp'] = DateTime.now().millisecondsSinceEpoch.toString();
      q['recvWindow'] = '10000';
    }
    final qs = q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final sig = signed ? '&signature=${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(qs))}' : '';
    final uri = Uri.parse('$base$path?$qs$sig');
    final h = {'X-MBX-APIKEY': key};
    final http.Response r = method == 'GET'
        ? await http.get(uri, headers: h)
        : method == 'DELETE'
            ? await http.delete(uri, headers: h)
            : await http.post(uri, headers: h);
    if (r.statusCode >= 400) throw Exception('Binance ${r.statusCode}: ${r.body}');
    return jsonDecode(r.body);
  }

  Future<double> usdtBalance() async {
    final j = await _req('GET', '/fapi/v2/balance', {}) as List;
    for (final e in j) {
      if (e['asset'] == 'USDT') return double.parse(e['availableBalance']);
    }
    return 0;
  }

  Future<void> setLeverage(String sym, int lev) async =>
      _req('POST', '/fapi/v1/leverage', {'symbol': sym, 'leverage': '$lev'});

  Future<double> _stepSize(String sym) async {
    if (_step.isEmpty) {
      final j = await _req('GET', '/fapi/v1/exchangeInfo', {}, signed: false);
      for (final s in j['symbols'] as List) {
        for (final f in s['filters'] as List) {
          if (f['filterType'] == 'LOT_SIZE') _step[s['symbol']] = double.parse(f['stepSize']);
        }
      }
    }
    return _step[sym] ?? 0.001;
  }

  Future<String> market(String sym, Side side, double qty, {bool reduce = false}) async {
    final st = await _stepSize(sym);
    final q = (qty / st).floor() * st;
    if (q <= 0) return 'qty too small';
    final dec = st >= 1 ? 0 : st.toString().split('.').last.length;
    await _req('POST', '/fapi/v1/order', {
      'symbol': sym, 'side': side == Side.long ? 'BUY' : 'SELL', 'type': 'MARKET',
      'quantity': q.toStringAsFixed(dec), if (reduce) 'reduceOnly': 'true',
    });
    return 'ok';
  }

  /// Protective exchange-side stop (kept even if the phone dies).
  Future<void> setStop(String sym, Side posSide, double stop) async {
    await _req('DELETE', '/fapi/v1/allOpenOrders', {'symbol': sym});
    await _req('POST', '/fapi/v1/order', {
      'symbol': sym, 'side': posSide == Side.long ? 'SELL' : 'BUY', 'type': 'STOP_MARKET',
      'stopPrice': stop.toStringAsFixed(stop > 100 ? 2 : 6), 'closePosition': 'true', 'workingType': 'MARK_PRICE',
    });
  }
}
