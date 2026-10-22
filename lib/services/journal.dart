import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../core/models.dart';
import '../core/sim.dart';

String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
String weekKey(DateTime d) {
  final j1 = DateTime(d.year, 1, 1);
  final w = ((d.difference(j1).inDays + j1.weekday - 1) / 7).floor() + 1;
  return '${d.year}-W${w.toString().padLeft(2, '0')}';
}

DateTime tOf(Basket b) => DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.openedAt);

Map<String, List<Basket>> groupBy(List<Basket> l, String Function(DateTime) k) {
  final m = <String, List<Basket>>{};
  for (final b in l) {
    m.putIfAbsent(k(tOf(b)), () => []).add(b);
  }
  return Map.fromEntries(m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

List<CellValue?> _row(List<Object> v) => v
    .map<CellValue?>((e) => e is int ? IntCellValue(e) : e is double ? DoubleCellValue(double.parse(e.toStringAsFixed(4))) : TextCellValue(e.toString()))
    .toList();

Future<File> buildJournal(Sim sim) async {
  final ex = Excel.createExcel();
  ex.rename('Sheet1', 'Trades');
  final t = ex['Trades'];
  t.appendRow(_row(['ID', 'Symbol', 'Side', 'Mode', 'Opened', 'Closed', 'Entry', 'Exit', 'PnL', 'R', 'Fees', 'Reason', 'MAE_R', 'MFE_R', 'Score', 'Legs']));
  final cl = [...sim.closed]..sort((a, b) => (a.closedAt ?? 0).compareTo(b.closedAt ?? 0));
  for (final b in cl) {
    t.appendRow(_row([
      b.id, b.symbol, b.side.label, b.mode,
      DateTime.fromMillisecondsSinceEpoch(b.openedAt).toIso8601String(),
      DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.openedAt).toIso8601String(),
      b.ref, b.exitPrice ?? 0.0, b.realized, b.riskAmt > 0 ? b.realized / b.riskAmt : 0.0, b.fees,
      b.exitReason ?? '', b.mae, b.mfe, b.score, b.legs.length,
    ]));
  }
  void period(String name, String Function(DateTime) k) {
    final s = ex[name];
    s.appendRow(_row(['Period', 'Trades', 'Wins', 'WinRate%', 'NetPnL', 'Fees', 'ProfitFactor', 'AvgR']));
    groupBy(cl, k).forEach((key, l) {
      final st = computeStats(l, 1000);
      s.appendRow(_row([key, st.n, st.wins, st.winRate, l.fold(0.0, (a, b) => a + b.realized), l.fold(0.0, (a, b) => a + b.fees), st.pf, st.avgR]));
    });
  }
  period('Daily', dayKey);
  period('Weekly', weekKey);
  period('Monthly', monthKey);
  final st = computeStats(cl, sim.start);
  final s = ex['Summary'];
  s.appendRow(_row(['Metric', 'Value']));
  for (final r in <List<Object>>[
    ['Start balance', sim.start], ['Balance', sim.balance], ['Net PnL', st.net],
    ['Trades', st.n], ['Win rate %', st.winRate], ['Profit factor', st.pf],
    ['Max drawdown %', st.maxDD], ['Avg R', st.avgR],
  ]) {
    s.appendRow(_row(r));
  }
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/journal.xlsx');
  await f.writeAsBytes(ex.encode()!);
  return f;
}
