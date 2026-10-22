import 'dart:math';
import 'models.dart';
import 'params.dart';
import 'engine.dart';
import 'series.dart';

class Stats {
  int n = 0, wins = 0;
  double net = 0, pf = 0, maxDD = 0, winRate = 0, avgR = 0;
  Map<String, dynamic> toJson() =>
      {'n': n, 'net': net, 'pf': pf, 'maxDD': maxDD, 'winRate': winRate, 'avgR': avgR};
}

Stats computeStats(List<Basket> cl, double start) {
  final s = Stats();
  if (cl.isEmpty) return s;
  final list = [...cl]..sort((a, b) => (a.closedAt ?? 0).compareTo(b.closedAt ?? 0));
  double eq = start, peak = start, gp = 0, gl = 0, rs = 0;
  for (final b in list) {
    final pnl = b.realized;
    eq += pnl;
    peak = max(peak, eq);
    if (peak > 0) s.maxDD = max(s.maxDD, (peak - eq) / peak * 100);
    if (pnl > 0) {
      s.wins++;
      gp += pnl;
    } else {
      gl += -pnl;
    }
    rs += b.riskAmt > 0 ? pnl / b.riskAmt : 0;
  }
  s.n = list.length;
  s.net = eq - start;
  s.winRate = s.wins / s.n * 100;
  s.pf = gl == 0 ? (gp > 0 ? 99.0 : 0.0) : gp / gl;
  s.avgR = rs / s.n;
  return s;
}

class Sim {
  Params p;
  late Engine eng;
  double balance, start;
  List<Basket> open = [], closed = [];
  final Map<String, Signal> pending = {};
  final Map<String, int> cool = {};

  Sim(this.p, double bal)
      : balance = bal,
        start = bal {
    eng = Engine(p);
  }

  void setParams(Params np) {
    final cb = eng.onOrder;
    p = np;
    eng = Engine(np)..onOrder = cb;
  }

  double unreal(Basket b, double px) => eng.total(b, px);

  double equity(Map<String, double> prices) {
    var e = balance;
    for (final b in open) {
      e += eng.total(b, prices[b.symbol] ?? b.ref);
    }
    return e;
  }

  void settle(int now, int barMs) {
    for (final b in open.where((b) => b.closedAt != null).toList()) {
      balance += b.realized;
      open.remove(b);
      closed.add(b);
      if (b.auto) cool[b.symbol] = now + (p['coolBars'] * barMs).round();
    }
    if (closed.length > 600) closed = closed.sublist(closed.length - 600);
  }

  /// Backtest step on a CLOSED bar i: entry at next bar open (no look-ahead).
  void onBar(String sym, Series s, int i) {
    final cd = s.c[i];
    final barMs = s.c.length > 1 ? s.c[1].t - s.c[0].t : 900000;
    final reg = s.regimeAt(i, p);
    final pd = pending.remove(sym);
    if (pd != null && open.length < p['maxOpen'] && !open.any((b) => b.symbol == sym)) {
      final ok = pd.side == Side.long ? cd.o > pd.sl : cd.o < pd.sl;
      if (ok) open.add(eng.open(sym, pd.side, cd.o, pd.sl, balance, cd.t, score: pd.score));
    }
    for (final b in open.where((b) => b.symbol == sym).toList()) {
      eng.manage(b, hi: cd.h, lo: cd.l, close: cd.c, atrNow: s.atrA[i], reg: reg, t: cd.t, balance: balance);
    }
    settle(cd.t, barMs);
    if (!open.any((b) => b.symbol == sym) && (cool[sym] ?? 0) <= cd.t &&
        (reg.regime == Regime.up || reg.regime == Regime.down)) {
      final sg = s.signalAt(sym, i, p);
      if (sg != null && sg.score >= p['minScore']) pending[sym] = sg;
    }
  }

  Map<String, dynamic> toJson() => {
        'bal': balance, 'start': start,
        'open': open.map((b) => b.toJson()).toList(),
        'closed': closed.map((b) => b.toJson()).toList(),
        'cool': cool,
      };

  void load(Map j) {
    balance = (j['bal'] as num).toDouble();
    start = (j['start'] as num).toDouble();
    open = (j['open'] as List).map((e) => Basket.fromJson(e)).toList();
    closed = (j['closed'] as List).map((e) => Basket.fromJson(e)).toList();
    cool
      ..clear()
      ..addAll({for (final e in (j['cool'] as Map).entries) e.key as String: e.value as int});
  }
}
