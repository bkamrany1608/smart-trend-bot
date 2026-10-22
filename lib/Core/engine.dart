import 'dart:math';
import 'models.dart';
import 'params.dart';

typedef OrderHook = void Function(Basket b, Side side, double qty, bool reduce);

String _f(double x) => x.abs() >= 100 ? x.toStringAsFixed(2) : x.toStringAsFixed(5);
String _ts(int t) => DateTime.fromMillisecondsSinceEpoch(t).toIso8601String().substring(5, 16);

class Engine {
  final Params p;
  OrderHook? onOrder;
  int _n = 0;
  Engine(this.p);

  Basket open(String sym, Side side, double price, double sl, double balance, int t,
      {double score = 0, String mode = 'virtual', double? qty, String note = 'signal'}) {
    final px = price * (1 + side.sign * p['slip']);
    var dist = (px - sl).abs();
    if (dist <= 0) dist = px * 0.01;
    var q = qty ?? (balance * p['riskPct'] / 100) / dist;
    final maxQ = balance * p['leverage'] / px;
    if (q > maxQ) q = maxQ;
    final b = Basket(
        id: '${t}_${sym}_${_n++}', symbol: sym, side: side, mode: mode,
        rDist: dist, sl: sl, ref: px, openedAt: t, score: score);
    b.extreme = px;
    b.legs.add(Leg('main', side, px, q, t));
    b.riskAmt = q * dist;
    _fee(b, q, px);
    b.log.add('${_ts(t)} OPEN ${side.label} @${_f(px)} qty ${_f(q)} SL ${_f(sl)} ($note)');
    onOrder?.call(b, side, q, false);
    return b;
  }

  void _fee(Basket b, double q, double px) {
    final f = q * px * p['fee'];
    b.fees += f;
    b.realized -= f;
  }

  void _close(Basket b, Leg l, double q, double px, String why) {
    q = min(q, l.qty);
    if (q <= 1e-12) return;
    final pnl = l.pnl(px, q);
    final f = q * px * p['fee'];
    b.realized += pnl - f;
    b.fees += f;
    l.qty -= q;
    b.log.add('CLOSE $why ${l.kind} ${l.side.label} q=${_f(q)} @${_f(px)} net=${(pnl - f).toStringAsFixed(2)}');
    onOrder?.call(b, l.side.opp, q, true);
  }

  void _partial(Basket b, double pct, double px, String why) {
    for (final l in b.legs) {
      if (l.side == b.side) _close(b, l, l.origQty * pct, px, why);
    }
  }

  void _finish(Basket b, double px, String why, int t) {
    for (final l in b.legs) {
      _close(b, l, l.qty, px, why);
    }
    b.closedAt = t;
    b.exitPrice = px;
    b.exitReason = why;
    b.log.add('${_ts(t)} BASKET CLOSED ($why) net=${b.realized.toStringAsFixed(2)}');
  }

  double total(Basket b, double px) => b.realized + b.legs.fold(0.0, (s, l) => s + l.pnl(px));

  double _potLoss(Basket b, [double extraQ = 0, double extraPx = 0]) {
    final sg = b.side.sign;
    var loss = 0.0;
    for (final l in b.legs) {
      if (l.side == b.side) loss += (l.entry - b.sl) * sg * l.qty;
    }
    if (extraQ > 0) loss += (extraPx - b.sl) * sg * extraQ;
    return loss - b.realized;
  }

  /// Advance a basket with one price observation (a closed bar, or a live tick
  /// where hi==lo==close). [reg] is non-null only for closed bars.
  List<String> manage(Basket b,
      {required double hi, required double lo, required double close, double? atrNow,
      RegimeInfo? reg, required int t, required double balance}) {
    if (b.closedAt != null) return const [];
    final before = b.log.length;
    if (!b.auto) {
      _manual(b, hi, lo, close, t);
      return b.log.sublist(before);
    }
    final sg = b.side.sign;
    if (atrNow != null && atrNow > 0) b.atr = atrNow;
    final a = b.atr;
    if (reg != null) b.barsOpen++;
    final adv = sg > 0 ? lo : hi, fav = sg > 0 ? hi : lo;
    b.mae = min(b.mae, sg * (adv - b.ref) / b.rDist);
    b.mfe = max(b.mfe, sg * (fav - b.ref) / b.rDist);
    var recOpenedNow = false;

    if (!b.slHit) {
      // 1) recovery trigger: quick adverse move => open 1.5x opposite leg
      final windowOk = b.recCount > 0 || b.barsOpen <= p['recBars'] + 1;
      if (p['recOn'] > 0 && b.recState == 0 && b.recCount < p['maxRec'] && b.stage == 0 && windowOk) {
        final trig = b.ref - sg * p['recTrigR'] * b.rDist;
        if (sg * (trig - adv) >= 0) {
          final rs = b.side.opp;
          final q = p['recMult'] * b.legs.first.origQty;
          final px = trig * (1 + rs.sign * p['slip']);
          b.legs.add(Leg('rec', rs, px, q, t));
          _fee(b, q, px);
          b.recState = 1;
          b.recExtreme = px;
          b.recCount++;
          recOpenedNow = true;
          b.log.add('${_ts(t)} RECOVERY #${b.recCount} ${rs.label} @${_f(px)} q=${_f(q)}');
          onOrder?.call(b, rs, q, false);
        }
      }
      // 2) stop-loss (conservative: checked before targets)
      if (sg * (b.sl - adv) >= 0) {
        final px = b.sl * (1 - sg * p['slip']);
        final why = b.stage >= 2 ? 'TRAIL' : (b.stage == 1 ? 'BE' : 'SL');
        for (final l in b.legs) {
          if (l.side == b.side) _close(b, l, l.qty, px, why);
        }
        if (b.recState == 1) {
          b.slHit = true;
          b.exitReason = why;
          b.log.add('${_ts(t)} main legs stopped ($why); recovery leg keeps running');
        } else {
          _finish(b, px, why, t);
          return b.log.sublist(before);
        }
      }
    }

    // 3) recovery leg management: ride the move, exit instantly on reversal
    if (b.recState == 1) {
      final rs = b.side.opp, rsg = rs.sign;
      final revPx = b.recExtreme - rsg * p['recTrailAtr'] * a;
      final reversed = !recOpenedNow && a > 0 && (rsg > 0 ? lo <= revPx : hi >= revPx);
      if (reversed) {
        final px = revPx * (1 - rsg * p['slip']);
        for (final l in b.legs) {
          if (l.kind == 'rec') _close(b, l, l.qty, px, 'REC_EXIT');
        }
        b.recState = 0;
        if (b.slHit) {
          _finish(b, px, '${b.exitReason ?? 'SL'}+REC', t);
          return b.log.sublist(before);
        }
        final q = p['recMult'] * b.legs.first.origQty;
        final ep = revPx * (1 + b.side.sign * p['slip']);
        if (_potLoss(b, q, ep) <= p['basketCap'] / 100 * balance) {
          b.legs.add(Leg('same', b.side, ep, q, t));
          _fee(b, q, ep);
          b.log.add('${_ts(t)} SAME-DIRECTION leg ${b.side.label} @${_f(ep)} q=${_f(q)}');
          onOrder?.call(b, b.side, q, false);
        } else {
          b.log.add('${_ts(t)} same-direction leg skipped (basket risk cap)');
        }
        if (b.recCount >= 2 && total(b, close) > 0) {
          _finish(b, close, 'REC_PROFIT', t);
          return b.log.sublist(before);
        }
      } else {
        b.recExtreme = rsg > 0 ? max(b.recExtreme, hi) : min(b.recExtreme, lo);
      }
    }

    if (!b.slHit) {
      // 4) staged targets, executed for the whole basket together
      final prog = sg * (fav - b.ref) / b.rDist;
      if (b.stage == 0 && prog >= p['tp1R']) {
        _partial(b, p['tp1Pct'], b.ref + sg * p['tp1R'] * b.rDist, 'TP1');
        b.stage = 1;
        final be = b.ref + sg * 0.05 * b.rDist;
        b.sl = sg > 0 ? max(b.sl, be) : min(b.sl, be);
      }
      if (b.stage == 1 && prog >= p['tp2R']) {
        _partial(b, p['tp2Pct'], b.ref + sg * p['tp2R'] * b.rDist, 'TP2');
        b.stage = 2;
      }
      b.extreme = sg > 0 ? max(b.extreme, hi) : min(b.extreme, lo);
      if (b.stage >= 2 && a > 0) {
        final ts = b.extreme - sg * p['trailAtr'] * a;
        b.sl = sg > 0 ? max(b.sl, ts) : min(b.sl, ts);
      }
    }

    // 5) basket-level protections evaluated on the close value
    final tot = total(b, close);
    b.peak = max(b.peak, tot);
    if (!b.slHit) {
      if (tot <= -p['basketCap'] / 100 * balance) {
        _finish(b, close, 'CAP', t);
        return b.log.sublist(before);
      }
      if (b.peak >= p['giveMinR'] * b.riskAmt && tot <= b.peak * (1 - p['give'])) {
        _finish(b, close, 'GIVEBACK', t);
        return b.log.sublist(before);
      }
      if (reg != null && p['flip'] > 0 && tot > 0 &&
          reg.regime == (sg > 0 ? Regime.down : Regime.up) && reg.strength >= 50) {
        _finish(b, close, 'TREND_FLIP', t);
        return b.log.sublist(before);
      }
      // 6) pyramid: add with increasing size only while trend is confirmed
      if (reg != null && p['pyrOn'] > 0 && b.recState == 0 && b.stage < 2) {
        final steps = b.legs.where((l) => l.kind == 'main' || l.kind == 'pyr').length;
        final progC = sg * (close - b.ref) / b.rDist;
        if (steps < p['maxSteps'] &&
            progC >= p['pyrStepR'] * steps &&
            reg.regime == (sg > 0 ? Regime.up : Regime.down) &&
            a > 0 && sg * (close - b.extreme) >= -0.3 * a) {
          final last = b.legs.lastWhere((l) => l.kind == 'main' || l.kind == 'pyr');
          final q = last.origQty * p['pyrMult'];
          if (_potLoss(b, q, close) <= p['basketCap'] / 100 * balance) {
            final px = close * (1 + sg * p['slip']);
            b.legs.add(Leg('pyr', b.side, px, q, t));
            _fee(b, q, px);
            b.log.add('${_ts(t)} PYRAMID step ${steps + 1} @${_f(px)} q=${_f(q)}');
            onOrder?.call(b, b.side, q, false);
          }
        }
      }
    }
    return b.log.sublist(before);
  }

  void _manual(Basket b, double hi, double lo, double close, int t) {
    final sg = b.side.sign;
    final adv = sg > 0 ? lo : hi, fav = sg > 0 ? hi : lo;
    if (b.sl > 0 && sg * (b.sl - adv) >= 0) {
      _finish(b, b.sl, 'SL', t);
      return;
    }
    for (final tp in b.tps) {
      if (tp[2] == 0 && sg * (fav - tp[0]) >= 0) {
        tp[2] = 1;
        for (final l in b.legs) {
          _close(b, l, l.origQty * tp[1], tp[0], 'TP');
        }
      }
    }
    if (b.legs.every((l) => l.qty <= 1e-12)) {
      b.closedAt = t;
      b.exitPrice = b.tps.isNotEmpty ? b.tps.last[0] : close;
      b.exitReason = 'TP';
      b.log.add('${_ts(t)} BASKET CLOSED (all targets) net=${b.realized.toStringAsFixed(2)}');
    }
  }

  void closeNow(Basket b, double px, int t, [String why = 'MANUAL']) => _finish(b, px, why, t);
}
