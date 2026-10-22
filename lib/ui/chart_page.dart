import 'dart:math';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../core/models.dart';
import '../core/series.dart';
import 'widgets.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});
  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  List<Candle> c = [];
  Series? s;
  String sym = app.sel, tf = '15m';
  bool loading = false, ema = true, rsiOn = true, vol = true;
  String? err;
  int shown = 90, endOff = 0, baseShown = 90;
  double acc = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      c = await app.md.klines(sym, tf, limit: 500, closedOnly: false);
      s = c.length > 60 ? Series(c) : null;
      endOff = 0;
    } catch (e) {
      err = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final syms = app.symbols.contains(sym) ? app.symbols : [sym, ...app.symbols];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          DropdownButton<String>(
            value: sym,
            underline: const SizedBox(),
            items: syms.map((e) => DropdownMenuItem(value: e, child: Text(e, textDirection: TextDirection.ltr))).toList(),
            onChanged: (v) {
              sym = v!;
              load();
            },
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: tf,
            underline: const SizedBox(),
            items: ['5m', '15m', '1h', '4h'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) {
              tf = v!;
              load();
            },
          ),
          const Spacer(),
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
        ]),
      ),
      Wrap(spacing: 8, children: [
        FilterChip(label: const Text('EMA'), selected: ema, onSelected: (v) => setState(() => ema = v)),
        FilterChip(label: const Text('RSI'), selected: rsiOn, onSelected: (v) => setState(() => rsiOn = v)),
        FilterChip(label: const Text('حجم'), selected: vol, onSelected: (v) => setState(() => vol = v)),
      ]),
      if (err != null) Padding(padding: const EdgeInsets.all(8), child: Text(err!, style: const TextStyle(color: kOrange, fontSize: 12))),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (ctx, cs) {
                return GestureDetector(
                  onScaleStart: (d) {
                    baseShown = shown;
                    acc = 0;
                  },
                  onScaleUpdate: (d) {
                    setState(() {
                      if (d.pointerCount >= 2) shown = (baseShown / d.scale).round().clamp(25, 300);
                      acc += d.focalPointDelta.dx;
                      final step = (cs.maxWidth - 52) / shown;
                      final mv = (acc / step).truncate();
                      if (mv != 0) {
                        endOff = (endOff + mv).clamp(0, max(0, c.length - shown));
                        acc -= mv * step;
                      }
                    });
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _P(c, s, shown, endOff, ema, rsiOn, vol, app.sim.open.where((b) => b.symbol == sym).toList()),
                  ),
                );
              }),
      ),
      const Padding(padding: EdgeInsets.all(4), child: Text('با دو انگشت زوم و با یک انگشت به چپ/راست بکشید', style: TextStyle(color: Colors.white38, fontSize: 11))),
    ]);
  }
}

class _P extends CustomPainter {
  final List<Candle> c;
  final Series? s;
  final int shown, endOff;
  final bool ema, rsiOn, vol;
  final List<Basket> baskets;
  _P(this.c, this.s, this.shown, this.endOff, this.ema, this.rsiOn, this.vol, this.baskets);

  void _t(Canvas cv, String t, Offset o, {Color col = Colors.white54, double sz = 10}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: col, fontSize: sz)), textDirection: TextDirection.ltr)..layout();
    tp.paint(cv, o);
  }

  @override
  void paint(Canvas cv, Size sz) {
    if (c.isEmpty) return;
    final end = c.length - 1 - endOff;
    final start = max(0, end - shown + 1);
    final n = end - start + 1;
    final rsiH = rsiOn ? sz.height * 0.18 : 0.0;
    final gap = rsiOn ? 8.0 : 0.0;
    final volH = vol ? sz.height * 0.10 : 0.0;
    final priceH = sz.height - rsiH - gap - 14;
    var hi = -1e18, lo = 1e18, vmax = 1e-9;
    for (var k = start; k <= end; k++) {
      hi = max(hi, c[k].h);
      lo = min(lo, c[k].l);
      vmax = max(vmax, c[k].v);
    }
    final pad = (hi - lo) * 0.05;
    hi += pad;
    lo -= pad;
    if (hi <= lo) hi = lo + 1;
    const rm = 56.0;
    final w = sz.width - rm;
    final cw = w / n;
    double y(double p) => (hi - p) / (hi - lo) * priceH;
    double x(int k) => (k - start + 0.5) * cw;

    final grid = Paint()..color = Colors.white10..strokeWidth = 1;
    for (var g = 0; g <= 5; g++) {
      final yy = priceH * g / 5;
      cv.drawLine(Offset(0, yy), Offset(w, yy), grid);
      _t(cv, fmtP(hi - (hi - lo) * g / 5), Offset(w + 4, yy - 6));
    }
    if (vol) {
      for (var k = start; k <= end; k++) {
        final h = c[k].v / vmax * volH;
        cv.drawRect(Rect.fromLTWH(x(k) - cw * 0.35, priceH - h, max(1, cw * 0.7), h),
            Paint()..color = (c[k].c >= c[k].o ? kGreen : kRed).withOpacity(0.25));
      }
    }
    for (var k = start; k <= end; k++) {
      final up = c[k].c >= c[k].o;
      final col = up ? kGreen : kRed;
      final p = Paint()..color = col..strokeWidth = 1;
      cv.drawLine(Offset(x(k), y(c[k].h)), Offset(x(k), y(c[k].l)), p);
      final top = y(max(c[k].o, c[k].c)), bot = y(min(c[k].o, c[k].c));
      cv.drawRect(Rect.fromLTRB(x(k) - cw * 0.35, top, x(k) + cw * 0.35, max(bot, top + 1)), p..style = PaintingStyle.fill);
    }
    final ser = s;
    if (ema && ser != null && ser.e1.length == c.length) {
      void line(List<double> a, Color col) {
        final path = Path();
        for (var k = start; k <= end; k++) {
          final o = Offset(x(k), y(a[k]));
          k == start ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        cv.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 1.4);
      }

      line(ser.e1, Colors.cyanAccent);
      line(ser.e2, Colors.amberAccent);
      line(ser.e3, Colors.purpleAccent);
    }
    for (final b in baskets) {
      void hl(double p, Color col, String label) {
        if (p <= 0 || p > hi || p < lo) return;
        cv.drawLine(Offset(0, y(p)), Offset(w, y(p)), Paint()..color = col..strokeWidth = 1.2);
        _t(cv, label, Offset(4, y(p) - 12), col: col);
      }

      hl(b.ref, Colors.white, 'ENTRY ${b.side.label}');
      hl(b.sl, kRed, 'SL');
    }
    if (rsiOn && ser != null && ser.rsiA.length == c.length) {
      final top = priceH + gap;
      cv.drawRect(Rect.fromLTWH(0, top, w, rsiH), Paint()..color = Colors.white10..style = PaintingStyle.stroke);
      final path = Path();
      for (var k = start; k <= end; k++) {
        final o = Offset(x(k), top + (100 - ser.rsiA[k]) / 100 * rsiH);
        k == start ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      cv.drawPath(path, Paint()..color = Colors.orangeAccent..style = PaintingStyle.stroke..strokeWidth = 1.3);
      for (final lv in [30.0, 70.0]) {
        final yy = top + (100 - lv) / 100 * rsiH;
        cv.drawLine(Offset(0, yy), Offset(w, yy), grid);
        _t(cv, '${lv.toInt()}', Offset(w + 4, yy - 6));
      }
      _t(cv, 'RSI', Offset(4, top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
