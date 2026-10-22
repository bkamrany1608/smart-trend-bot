import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_state.dart';
import '../core/models.dart';
import '../core/sim.dart';
import '../services/journal.dart';
import 'widgets.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  String kind = 'equity';
  String msg = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (c, _) {
        final cl = [...app.sim.closed]..sort((a, b) => (a.closedAt ?? 0).compareTo(b.closedAt ?? 0));
        final st = computeStats(cl, app.sim.start);
        return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          card(Column(children: [
            kv('تعداد معاملات', '${st.n}'),
            kv('نرخ برد', '${st.winRate.toStringAsFixed(1)}%'),
            kv('ضریب سود (PF)', st.pf.toStringAsFixed(2)),
            kv('سود خالص', fmtM(st.net), color: st.net >= 0 ? kGreen : kRed),
            kv('حداکثر دراوداون', '${st.maxDD.toStringAsFixed(2)}%'),
            kv('میانگین R', st.avgR.toStringAsFixed(2)),
          ])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, children: [
              for (final e in {'equity': 'سرمایه', 'drawdown': 'دراوداون', 'daily': 'روزانه', 'weekly': 'هفتگی', 'monthly': 'ماهانه', 'winloss': 'برد/باخت'}.entries)
                ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) => setState(() => kind = e.key)),
            ]),
          ),
          card(SizedBox(height: 260, child: cl.isEmpty ? const Center(child: Text('هنوز معامله‌ای بسته نشده', style: TextStyle(color: Colors.white38))) : _chart(cl))),
          card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              icon: const Icon(Icons.table_chart),
              label: const Text('ساخت ژورنال اکسل و اشتراک‌گذاری'),
              onPressed: () async {
                final f = await app.journal();
                await Share.shareXFiles([XFile(f.path)], text: 'Trading journal');
                setState(() => msg = 'ذخیره شد: ${f.path}');
              },
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.send),
              label: const Text('ارسال ژورنال به تلگرام'),
              onPressed: () async {
                final r = await app.sendJournal();
                setState(() => msg = r);
              },
            ),
            if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg, style: const TextStyle(fontSize: 12, color: Colors.white60))),
          ])),
        ]);
      },
    );
  }

  Widget _chart(List<Basket> cl) {
    FlTitlesData titles() => const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 46)),
        );
    Widget line(List<double> ys, Color col) => LineChart(LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
              isCurved: false, color: col, barWidth: 2, dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: col.withOpacity(0.12)),
            )
          ],
          titlesData: titles(),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
        ));
    Widget bars(List<double> vs) => BarChart(BarChartData(
          barGroups: [
            for (var i = 0; i < vs.length; i++)
              BarChartGroupData(x: i, barRods: [BarChartRodData(toY: vs[i], color: vs[i] >= 0 ? kGreen : kRed, width: max(3.0, min(14.0, 260 / max(1, vs.length))))])
          ],
          titlesData: titles(),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
        ));
    if (kind == 'equity' || kind == 'drawdown') {
      var eq = app.sim.start;
      var peak = eq;
      final e = <double>[eq], d = <double>[0];
      for (final b in cl) {
        eq += b.realized;
        peak = max(peak, eq);
        e.add(eq);
        d.add(-(peak - eq) / peak * 100);
      }
      return kind == 'equity' ? line(e, kGreen) : line(d, kRed);
    }
    if (kind == 'winloss') {
      final w = cl.where((b) => b.realized > 0).length.toDouble();
      final l = cl.length - w;
      return PieChart(PieChartData(sections: [
        PieChartSectionData(value: max(w, 0.001), color: kGreen, title: 'برد ${w.toInt()}', radius: 70),
        PieChartSectionData(value: max(l, 0.001), color: kRed, title: 'باخت ${l.toInt()}', radius: 70),
      ]));
    }
    final g = groupBy(cl, kind == 'daily' ? dayKey : kind == 'weekly' ? weekKey : monthKey);
    return bars([for (final l in g.values) l.fold(0.0, (a, b) => a + b.realized)]);
  }
}
