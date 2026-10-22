import 'package:flutter/material.dart';
import '../app_state.dart';
import '../core/models.dart';
import 'widgets.dart';

class TradesPage extends StatefulWidget {
  const TradesPage({super.key});
  @override
  State<TradesPage> createState() => _TradesPageState();
}

class _TradesPageState extends State<TradesPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (c, _) {
        final open = app.sim.open;
        final closed = app.sim.closed.reversed.toList();
        final eq = app.equity;
        final pnl = eq - app.sim.start;
        final items = tab == 0 ? open : closed;
        return ListView(children: [
          card(Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('حساب ${app.cfg['mode'] == 'virtual' ? 'مجازی' : app.cfg['mode'] == 'testnet' ? 'تست‌نت' : 'واقعی'}', style: const TextStyle(color: Colors.white60)),
              Chip(label: Text(app.cfg['running'] == true ? 'فعال' : 'متوقف'), backgroundColor: app.cfg['running'] == true ? kGreen.withOpacity(0.2) : Colors.white12),
            ]),
            Text(eq.toStringAsFixed(2), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            Text('${fmtM(pnl)}  (${(pnl / app.sim.start * 100).toStringAsFixed(2)}%)', textDirection: TextDirection.ltr, style: TextStyle(color: pnl >= 0 ? kGreen : kRed)),
            const SizedBox(height: 6),
            kv('موجودی', app.sim.balance.toStringAsFixed(2)),
            kv('معاملات باز / بسته', '${open.length} / ${app.sim.closed.length}'),
            kv('آخرین اسکن', app.lastScanAt == 0 ? '-' : fmtT(app.lastScanAt)),
            if (app.lastError != null) Text(app.lastError!, style: const TextStyle(color: kOrange, fontSize: 12)),
          ])),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('روند بازار', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              DropdownButton<String>(
                value: app.symbols.contains(app.sel) ? app.sel : null,
                underline: const SizedBox(),
                items: app.symbols.map((s) => DropdownMenuItem(value: s, child: Text(s, textDirection: TextDirection.ltr))).toList(),
                onChanged: (v) {
                  app.sel = v!;
                  app.refresh();
                },
              ),
            ]),
            TrendBar(app.regimes[app.sel]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in app.regimes.entries)
                GestureDetector(
                  onTap: () {
                    app.sel = e.key;
                    app.refresh();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: regimeColor(e.value.regime).withOpacity(0.18), borderRadius: BorderRadius.circular(10), border: Border.all(color: regimeColor(e.value.regime).withOpacity(e.key == app.sel ? 1 : 0.35))),
                    child: Text(e.key.replaceAll('USDT', ''), style: TextStyle(color: regimeColor(e.value.regime), fontSize: 12)),
                  ),
                ),
            ]),
          ])),
          if (app.pendingOrders.isNotEmpty)
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('سفارش‌های در انتظار', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final o in app.pendingOrders)
                ListTile(
                  dense: true,
                  title: Text('${o['sym']} ${o['side'] == 0 ? 'LONG' : 'SHORT'} ${o['type']} @${o['price']}', textDirection: TextDirection.ltr),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => app.cancelPending(o)),
                ),
            ])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SegmentedButton<int>(
              segments: [ButtonSegment(value: 0, label: Text('باز (${open.length})')), ButtonSegment(value: 1, label: Text('بسته (${closed.length})'))],
              selected: {tab},
              onSelectionChanged: (s) => setState(() => tab = s.first),
            ),
          ),
          if (items.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('معامله‌ای وجود ندارد', style: TextStyle(color: Colors.white38)))),
          for (final b in items.take(100)) _tile(context, b),
          const SizedBox(height: 20),
        ]);
      },
    );
  }

  Widget _tile(BuildContext context, Basket b) {
    final isOpen = b.closedAt == null;
    final pnl = isOpen ? app.unreal(b) : b.realized;
    final col = pnl >= 0 ? kGreen : kRed;
    return card(
      InkWell(
        onTap: () => showBasketSheet(context, b),
        child: Row(children: [
          Container(width: 4, height: 44, color: b.side == Side.long ? kGreen : kRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.symbol}  ${b.side.label}${b.auto ? '' : ' (دستی)'}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(isOpen ? 'پله ${b.stage}/2 • ${b.legs.length} لگ • ${fmtT(b.openedAt)}' : '${b.exitReason} • ${fmtT(b.closedAt!)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtM(pnl), textDirection: TextDirection.ltr, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${(b.riskAmt > 0 ? pnl / b.riskAmt : 0).toStringAsFixed(2)}R', style: TextStyle(color: col, fontSize: 12)),
          ]),
        ]),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }
}

void showBasketSheet(BuildContext context, Basket b) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCard,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (c, sc) {
        final isOpen = b.closedAt == null;
        final px = app.prices[b.symbol];
        final pnl = isOpen ? app.unreal(b) : b.realized;
        return ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
          Text('${b.symbol} ${b.side.label}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          kv('وضعیت', isOpen ? 'باز' : 'بسته (${b.exitReason})'),
          kv('حالت', b.mode),
          kv('سود/زیان', fmtM(pnl), color: pnl >= 0 ? kGreen : kRed),
          kv('R', '${(b.riskAmt > 0 ? pnl / b.riskAmt : 0).toStringAsFixed(2)}'),
          if (isOpen && px != null) kv('قیمت فعلی', fmtP(px)),
          kv('قیمت ورود مرجع', fmtP(b.ref)),
          kv('حد ضرر', b.sl > 0 ? fmtP(b.sl) : '-'),
          kv('فاصله ریسک (1R)', fmtP(b.rDist)),
          kv('ریسک پول (1R)', b.riskAmt.toStringAsFixed(2)),
          kv('مرحله خروج', '${b.stage} (0=بدون،1=TP1،2=TP2+تریل)'),
          kv('بیشترین سود شناور (قله)', b.peak.toStringAsFixed(2)),
          kv('MAE / MFE (R)', '${b.mae.toStringAsFixed(2)} / ${b.mfe.toStringAsFixed(2)}'),
          kv('کارمزد', b.fees.toStringAsFixed(3)),
          kv('امتیاز سیگنال', b.score.toStringAsFixed(0)),
          kv('تعداد ریکاوری', '${b.recCount}'),
          kv('باز شده', fmtT(b.openedAt)),
          if (b.closedAt != null) kv('بسته شده', fmtT(b.closedAt!)),
          if (b.tps.isNotEmpty) kv('تارگت‌ها', b.tps.map((t) => '${fmtP(t[0])}${t[2] == 1 ? '✓' : ''}').join(' | ')),
          const Divider(),
          const Text('لگ‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final l in b.legs) kv('${l.kind} ${l.side.label}', '@${fmtP(l.entry)}  q=${l.qty.toStringAsFixed(4)}/${l.origQty.toStringAsFixed(4)}'),
          const Divider(),
          const Text('گزارش رویدادها', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final l in b.log) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(l, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: Colors.white70))),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.tonal(
                onPressed: () {
                  app.closeBasket(b);
                  Navigator.pop(context);
                },
                child: const Text('بستن سبد در قیمت بازار'),
              ),
            ),
        ]);
      },
    ),
  );
}
