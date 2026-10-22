import 'dart:math';
import 'models.dart';

List<double> ema(List<double> x, int p) {
  final k = 2 / (p + 1);
  final out = List<double>.filled(x.length, 0);
  if (x.isEmpty) return out;
  out[0] = x[0];
  for (var i = 1; i < x.length; i++) {
    out[i] = x[i] * k + out[i - 1] * (1 - k);
  }
  return out;
}

List<double> atr(List<Candle> c, int p) {
  final out = List<double>.filled(c.length, 0);
  if (c.isEmpty) return out;
  out[0] = c[0].h - c[0].l;
  for (var i = 1; i < c.length; i++) {
    final tr = max(c[i].h - c[i].l, max((c[i].h - c[i - 1].c).abs(), (c[i].l - c[i - 1].c).abs()));
    out[i] = (out[i - 1] * (p - 1) + tr) / p;
  }
  return out;
}

List<double> adx(List<Candle> c, int p) {
  final n = c.length;
  final out = List<double>.filled(n, 0);
  if (n < p * 2 + 2) return out;
  final pdm = List<double>.filled(n, 0), mdm = List<double>.filled(n, 0), tr = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final up = c[i].h - c[i - 1].h;
    final dn = c[i - 1].l - c[i].l;
    pdm[i] = (up > dn && up > 0) ? up : 0.0;
    mdm[i] = (dn > up && dn > 0) ? dn : 0.0;
    tr[i] = max(c[i].h - c[i].l, max((c[i].h - c[i - 1].c).abs(), (c[i].l - c[i - 1].c).abs()));
  }
  double sT = 0, sP = 0, sM = 0;
  for (var i = 1; i <= p; i++) {
    sT += tr[i]; sP += pdm[i]; sM += mdm[i];
  }
  final dx = List<double>.filled(n, 0);
  for (var i = p; i < n; i++) {
    if (i > p) {
      sT = sT - sT / p + tr[i];
      sP = sP - sP / p + pdm[i];
      sM = sM - sM / p + mdm[i];
    }
    final double pdi = sT == 0 ? 0.0 : 100 * sP / sT;
    final double mdi = sT == 0 ? 0.0 : 100 * sM / sT;
    final s = pdi + mdi;
    dx[i] = s == 0 ? 0.0 : 100 * (pdi - mdi).abs() / s;
  }
  double a = 0;
  for (var i = p; i < p * 2; i++) {
    a += dx[i];
  }
  a /= p;
  out[p * 2 - 1] = a;
  for (var i = p * 2; i < n; i++) {
    a = (a * (p - 1) + dx[i]) / p;
    out[i] = a;
  }
  return out;
}

List<double> rsi(List<double> x, int p) {
  final n = x.length;
  final out = List<double>.filled(n, 50);
  if (n <= p) return out;
  double g = 0, l = 0;
  for (var i = 1; i <= p; i++) {
    final d = x[i] - x[i - 1];
    if (d > 0) {
      g += d;
    } else {
      l -= d;
    }
  }
  g /= p;
  l /= p;
  out[p] = l == 0 ? 100.0 : 100 - 100 / (1 + g / l);
  for (var i = p + 1; i < n; i++) {
    final d = x[i] - x[i - 1];
    g = (g * (p - 1) + (d > 0 ? d : 0)) / p;
    l = (l * (p - 1) + (d < 0 ? -d : 0)) / p;
    out[i] = l == 0 ? 100.0 : 100 - 100 / (1 + g / l);
  }
  return out;
}
