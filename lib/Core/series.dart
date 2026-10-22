import 'dart:math';
import 'models.dart';
import 'params.dart';
import 'indicators.dart';

/// Indicator arrays are causal (no look-ahead) and independent of Params,
/// so one Series can be reused for many parameter sets.
class Series {
  final List<Candle> c;
  late final List<double> closes, e1, e2, e3, e4, atrA, adxA, rsiA;

  Series(this.c) {
    closes = c.map((x) => x.c).toList();
    e1 = ema(closes, 20);
    e2 = ema(closes, 50);
    e3 = ema(closes, 200);
    e4 = ema(closes, 80); // higher-timeframe proxy (~1h EMA20 on 15m bars)
    atrA = atr(c, 14);
    adxA = adx(c, 14);
    rsiA = rsi(closes, 14);
  }

  static const int warm = 210;

  RegimeInfo regimeAt(int i, Params p) {
    if (i < warm) return const RegimeInfo(Regime.range, 0, 'warmup');
    final a = atrA[i];
    double avg = 0;
    for (var k = i - 50; k < i; k++) {
      avg += atrA[k];
    }
    avg /= 50;
    final vr = avg == 0 ? 1.0 : a / avg;
    if (vr > p['volSpike']) {
      return RegimeInfo(Regime.volatile, min(100.0, (vr - 1) * 60), 'vol ${vr.toStringAsFixed(1)}x');
    }
    final spread = (e1[i] - e2[i]).abs() / a;
    final adxv = adxA[i];
    final str = min(100.0, adxv * 1.7 + spread * 8);
    if (adxv < p['adxMin'] || spread < 0.25) {
      return RegimeInfo(Regime.range, min(100.0, adxv * 2), 'adx ${adxv.toStringAsFixed(0)}');
    }
    if (e1[i] > e2[i] && e2[i] > e3[i] && closes[i] > e2[i]) return RegimeInfo(Regime.up, str, 'adx ${adxv.toStringAsFixed(0)}');
    if (e1[i] < e2[i] && e2[i] < e3[i] && closes[i] < e2[i]) return RegimeInfo(Regime.down, str, 'adx ${adxv.toStringAsFixed(0)}');
    return RegimeInfo(Regime.range, min(100.0, adxv * 2), 'mixed');
  }

  /// Trend-pullback entry on the CLOSED bar i. Written once in "mirrored" space
  /// so long and short share identical logic.
  Signal? signalAt(String sym, int i, Params p) {
    if (i < warm) return null;
    final r = regimeAt(i, p);
    final long = r.regime == Regime.up;
    if (!long && r.regime != Regime.down) return null;
    final m = long ? 1.0 : -1.0;
    double H(int k) => long ? c[k].h : -c[k].l;
    double L(int k) => long ? c[k].l : -c[k].h;
    double C(int k) => m * c[k].c;
    double O(int k) => m * c[k].o;
    double E1(int k) => m * e1[k];
    double E2(int k) => m * e2[k];
    double R(int k) => long ? rsiA[k] : 100 - rsiA[k];
    final a = atrA[i];
    if (a <= 0) return null;
    if (p['htf'] > 0 && (long ? !(e4[i] > e3[i]) : !(e4[i] < e3[i]))) return null;

    final body = C(i) - O(i); // noise filter: need a real impulse candle
    if (body < p['minBody'] * a) return null;
    if (!(C(i) > E1(i) && C(i) > H(i - 1))) return null;
    if (!(R(i) > 45 && R(i) > R(i - 2))) return null;

    var j = i - 1;
    var pl = L(i - 1);
    for (var k = i - 10; k < i; k++) {
      if (L(k) < pl) {
        pl = L(k);
        j = k;
      }
    }
    var hh = H(j);
    var hi = j;
    for (var k = j - 30; k <= j; k++) {
      if (H(k) > hh) {
        hh = H(k);
        hi = k;
      }
    }
    var ls = hh;
    for (var k = hi - 30; k <= hi; k++) {
      if (L(k) < ls) ls = L(k);
    }
    final leg = hh - ls, depth = hh - pl;
    if (leg <= 0 || depth < p['pbMinAtr'] * a || depth / leg > p['pbMaxFrac']) return null;
    if (pl > E1(j) + 0.2 * a) return null; // pullback must reach the EMA20 zone
    if (pl < E2(j) - 0.6 * a) return null; // structure damaged => not a pullback

    var sl = pl - p['slBuf'] * a;
    var dist = C(i) - sl;
    if (dist < p['minSlAtr'] * a) {
      sl = C(i) - p['minSlAtr'] * a;
      dist = C(i) - sl;
    }
    if (dist > p['maxSlAtr'] * a) return null;
    final score = min(100.0, r.strength * 0.55 + min(25.0, depth / a * 8) + min(20.0, body / a * 20));
    return Signal(sym, long ? Side.long : Side.short, c[i].c, m * sl, score, a, c[i].t,
        'pullback ${(depth / a).toStringAsFixed(1)}ATR, ${r.note}');
  }

  /// Confirmed swing pivots (fractals) used for structure / top-bottom detection.
  List<int> swingHighs(int upTo, {int n = 3, int look = 120}) {
    final out = <int>[];
    for (var k = max(n, upTo - look); k <= upTo - n; k++) {
      var ok = true;
      for (var q = 1; q <= n; q++) {
        if (c[k].h <= c[k - q].h || c[k].h < c[k + q].h) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(k);
    }
    return out;
  }

  List<int> swingLows(int upTo, {int n = 3, int look = 120}) {
    final out = <int>[];
    for (var k = max(n, upTo - look); k <= upTo - n; k++) {
      var ok = true;
      for (var q = 1; q <= n; q++) {
        if (c[k].l >= c[k - q].l || c[k].l > c[k + q].l) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(k);
    }
    return out;
  }
}
