enum Regime { up, down, range, volatile }

enum Side { long, short }

extension SideX on Side {
  int get sign => this == Side.long ? 1 : -1;
  String get label => this == Side.long ? 'LONG' : 'SHORT';
  Side get opp => this == Side.long ? Side.short : Side.long;
}

class Candle {
  final int t;
  final double o, h, l, c, v;
  const Candle(this.t, this.o, this.h, this.l, this.c, this.v);
}

class RegimeInfo {
  final Regime regime;
  final double strength;
  final String note;
  const RegimeInfo(this.regime, this.strength, [this.note = '']);
}

class Signal {
  final String symbol;
  final Side side;
  final double price, sl, score, atr;
  final int t;
  final String reason;
  const Signal(this.symbol, this.side, this.price, this.sl, this.score, this.atr, this.t, this.reason);
}

double _d(dynamic x) => (x as num).toDouble();

class Leg {
  String kind; // main, pyr, rec, same, manual
  Side side;
  double entry, qty, origQty;
  int t;
  Leg(this.kind, this.side, this.entry, this.qty, this.t) : origQty = qty;
  double pnl(double px, [double? q]) => (px - entry) * side.sign * (q ?? qty);
  Map<String, dynamic> toJson() =>
      {'k': kind, 's': side.index, 'e': entry, 'q': qty, 'o': origQty, 't': t};
  factory Leg.fromJson(Map j) {
    final l = Leg(j['k'], Side.values[j['s']], _d(j['e']), _d(j['q']), j['t']);
    l.origQty = _d(j['o']);
    return l;
  }
}

class Basket {
  String id, symbol, mode;
  Side side;
  List<Leg> legs = [];
  double rDist, sl, ref;
  double riskAmt = 0, extreme = 0, peak = 0, realized = 0, fees = 0;
  double recExtreme = 0, mae = 0, mfe = 0, score = 0, atr = 0;
  int stage = 0, barsOpen = 0, recState = 0, recCount = 0, openedAt;
  bool slHit = false, auto = true;
  int? closedAt;
  double? exitPrice;
  String? exitReason;
  List<List<double>> tps = []; // manual: [price, pct, done]
  List<String> log = [];

  Basket({
    required this.id,
    required this.symbol,
    required this.side,
    required this.mode,
    required this.rDist,
    required this.sl,
    required this.ref,
    required this.openedAt,
    this.score = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'sym': symbol, 'mode': mode, 'side': side.index,
        'legs': legs.map((l) => l.toJson()).toList(),
        'r': rDist, 'sl': sl, 'ref': ref, 'risk': riskAmt, 'ext': extreme, 'peak': peak,
        'real': realized, 'fees': fees, 'rx': recExtreme, 'mae': mae, 'mfe': mfe,
        'score': score, 'atr': atr, 'stage': stage, 'bars': barsOpen, 'rs': recState,
        'rc': recCount, 'ot': openedAt, 'slHit': slHit, 'auto': auto, 'ct': closedAt,
        'xp': exitPrice, 'xr': exitReason, 'tps': tps, 'log': log,
      };

  factory Basket.fromJson(Map j) {
    final b = Basket(
      id: j['id'], symbol: j['sym'], side: Side.values[j['side']], mode: j['mode'],
      rDist: _d(j['r']), sl: _d(j['sl']), ref: _d(j['ref']), openedAt: j['ot'],
      score: _d(j['score']),
    );
    b.legs = (j['legs'] as List).map((e) => Leg.fromJson(e)).toList();
    b.riskAmt = _d(j['risk']); b.extreme = _d(j['ext']); b.peak = _d(j['peak']);
    b.realized = _d(j['real']); b.fees = _d(j['fees']); b.recExtreme = _d(j['rx']);
    b.mae = _d(j['mae']); b.mfe = _d(j['mfe']); b.atr = _d(j['atr']);
    b.stage = j['stage']; b.barsOpen = j['bars']; b.recState = j['rs']; b.recCount = j['rc'];
    b.slHit = j['slHit']; b.auto = j['auto']; b.closedAt = j['ct'];
    b.exitPrice = j['xp'] == null ? null : _d(j['xp']);
    b.exitReason = j['xr'];
    b.tps = (j['tps'] as List).map<List<double>>((e) => (e as List).map<double>((x) => _d(x)).toList()).toList();
    b.log = (j['log'] as List).map((e) => e.toString()).toList();
    return b;
  }
}
