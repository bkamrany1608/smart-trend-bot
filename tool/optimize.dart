import 'dart:convert';
import 'dart:io';
import 'package:smart_trend_bot/core/models.dart';
import 'package:smart_trend_bot/core/params.dart';
import 'package:smart_trend_bot/core/series.dart';
import 'package:smart_trend_bot/core/optimizer.dart';

void main() {
  final dir = Directory('data');
  final data = <String, Series>{};
  if (dir.existsSync()) {
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv'))) {
      final name = f.uri.pathSegments.last.split('_').first;
      final c = <Candle>[];
      for (final line in f.readAsLinesSync()) {
        final p = line.split(',');
        if (p.length < 6) continue;
        c.add(Candle(int.parse(p[0]), double.parse(p[1]), double.parse(p[2]), double.parse(p[3]),
            double.parse(p[4]), double.parse(p[5])));
      }
      if (c.length > 1500) data[name] = Series(c);
    }
  }
  if (data.isEmpty) {
    stdout.writeln('No data downloaded - keeping default parameters.');
    return;
  }
  stdout.writeln('Symbols: ${data.keys.join(', ')}');
  final base = Params().copyWith(Params.riskPreset('medium'));
  final rep = optimize(data, base, fullGrid);
  final fullDef = backtest(data, base);
  final fullBest = backtest(data, base.copyWith(rep.best));

  String row(String n, dynamic s) =>
      '| $n | ${s.n} | ${s.winRate.toStringAsFixed(1)}% | ${s.pf.toStringAsFixed(2)} | ${s.net.toStringAsFixed(1)} | ${s.maxDD.toStringAsFixed(1)}% | ${s.avgR.toStringAsFixed(2)} |';
  final md = StringBuffer()
    ..writeln('# Optimization report (walk-forward, 65% train / 35% hold-out)')
    ..writeln('Symbols: ${data.keys.join(', ')}  |  accepted: ${rep.accepted}')
    ..writeln('Best params: ${jsonEncode(rep.best)}\n')
    ..writeln('| Set | Trades | Win% | PF | Net (USDT, 1000 each) | MaxDD | Avg R |')
    ..writeln('|---|---|---|---|---|---|---|')
    ..writeln(row('Train (best)', rep.trainBest))
    ..writeln(row('Hold-out (best)', rep.testBest))
    ..writeln(row('Hold-out (defaults)', rep.testDefault))
    ..writeln(row('Full period (defaults)', fullDef.stats))
    ..writeln(row('Full period (best)', fullBest.stats));
  Directory('reports').createSync(recursive: true);
  File('reports/optimization.md').writeAsStringSync(md.toString());
  stdout.writeln(md);

  final out = {
    'params': rep.accepted ? rep.best : <String, double>{},
    'meta': {
      'validated': rep.accepted,
      'holdout': rep.testBest.toJson(),
      'holdoutDefault': rep.testDefault.toJson(),
      'symbols': data.keys.toList(),
      'date': DateTime.now().toIso8601String(),
    },
  };
  File('assets/params.json').writeAsStringSync(jsonEncode(out));
}
