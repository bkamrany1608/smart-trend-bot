import 'dart:math';
import 'models.dart';
import 'params.dart';
import 'series.dart';
import 'sim.dart';

class BtResult {
  final Stats stats;
  final double score;
  BtResult(this.stats, this.score);
}

/// Run the exact live engine over [from,to) of every series.
BtResult backtest(Map<String, Series> data, Params p, {double from = 0, double to = 1}) {
  final all = <Basket>[];
  double startSum = 0;
  for (final e in data.entries) {
    final s = e.value;
    final n = s.c.length;
    var a = max(Series.warm, (n * from).floor());
    final b = (n * to).floor();
    if (b - a < 200) continue;
    final sim = Sim(p, 1000);
    for (var i = a; i < b; i++) {
      sim.onBar(e.key, s, i);
    }
    // close leftovers at last price so open trades are counted
    final last = s.c[b - 1];
    for (final bk in sim.open.toList()) {
      sim.eng.closeNow(bk, last.c, last.t, 'END');
    }
    sim.settle(last.t, 900000);
    all.addAll(sim.closed);
    startSum += 1000;
  }
  final st = computeStats(all, startSum == 0 ? 1000 : startSum);
  final netPct = startSum == 0 ? 0.0 : st.net / startSum * 100;
  // objective: return minus drawdown penalty; punish tiny samples
  final penalty = st.n < 30 ? 50.0 : 0.0;
  return BtResult(st, netPct - 1.5 * st.maxDD - penalty);
}

List<Map<String, double>> expandGrid(Map<String, List<double>> g) {
  var out = <Map<String, double>>[{}];
  for (final e in g.entries) {
    final next = <Map<String, double>>[];
    for (final o in out) {
      for (final v in e.value) {
        next.add({...o, e.key: v});
      }
    }
    out = next;
  }
  return out;
}

class OptReport {
  final Map<String, double> best;
  final Stats trainBest, testBest, testDefault;
  final bool accepted;
  OptReport(this.best, this.trainBest, this.testBest, this.testDefault, this.accepted);
  Map<String, dynamic> toJson() => {
        'best': best, 'train': trainBest.toJson(), 'test': testBest.toJson(),
        'testDefault': testDefault.toJson(), 'accepted': accepted,
      };
}

/// Walk-forward: choose on the first [split] of history, validate on the rest.
/// Parameters are only accepted when the hold-out is profitable and not worse
/// than the defaults, which guards against curve fitting.
OptReport optimize(Map<String, Series> data, Params base, Map<String, List<double>> grid,
    {double split = 0.65}) {
  final combos = expandGrid(grid);
  Map<String, double> best = {};
  double bestScore = -1e18;
  Stats bestTrain = Stats();
  for (final c in combos) {
    final r = backtest(data, base.copyWith(c), from: 0, to: split);
    if (r.score > bestScore) {
      bestScore = r.score;
      best = c;
      bestTrain = r.stats;
    }
  }
  final testBest = backtest(data, base.copyWith(best), from: split, to: 1);
  final testDef = backtest(data, base, from: split, to: 1);
  final accepted = testBest.stats.n >= 15 &&
      testBest.stats.net > 0 &&
      testBest.stats.pf >= 1.05 &&
      testBest.score >= testDef.score;
  return OptReport(best, bestTrain, testBest.stats, testDef.stats, accepted);
}

const Map<String, List<double>> fullGrid = {
  'adxMin': [18, 22, 26],
  'pbMinAtr': [0.4, 0.7],
  'slBuf': [0.2, 0.5],
  'trailAtr': [1.5, 2.5],
  'give': [0.10, 0.20, 0.30],
  'minScore': [40, 55],
};

const Map<String, List<double>> quickGrid = {
  'adxMin': [20, 25],
  'trailAtr': [1.5, 2.5],
  'give': [0.10, 0.20],
  'minScore': [40, 55],
};
