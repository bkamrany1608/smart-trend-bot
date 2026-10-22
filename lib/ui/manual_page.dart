import 'package:flutter/material.dart';
import '../app_state.dart';
import '../core/models.dart';
import '../services/signal_parser.dart';
import 'widgets.dart';

class ManualPage extends StatefulWidget {
  const ManualPage({super.key});
  @override
  State<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends State<ManualPage> {
  final sym = TextEditingController(text: 'BTCUSDT');
  final price = TextEditingController();
  final margin = TextEditingController(text: '50');
  final sl = TextEditingController();
  final tp1 = TextEditingController(), tp2 = TextEditingController(), tp3 = TextEditingController();
  final paste = TextEditingController();
  Side side = Side.long;
  String type = 'market';
  double lev = 5;
  String info = '';

  double _n(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  void parse() {
    final p = parseSignal(paste.text);
    final lines = <String>[];
    setState(() {
      if (p.symbol != null) { sym.text = p.symbol!; lines.add('نماد: ${p.symbol}'); }
      if (p.side != null) { side = p.side!; lines.add('جهت: ${p.side!.label}'); }
      if (p.entry != null) {
        price.text = '${p.entry}';
        type = 'limit';
        lines.add('ورود: ${p.entry}${p.entry2 != null ? ' - ${p.entry2}' : ''}');
      }
      if (p.sl != null) { sl.text = '${p.sl}'; lines.add('حد ضرر: ${p.sl}'); }
      final t = p.tps;
      tp1.text = t.isNotEmpty ? '${t[0]}' : '';
      tp2.text = t.length > 1 ? '${t[1]}' : '';
      tp3.text = t.length > 2 ? '${t[2]}' : '';
      if (t.isNotEmpty) lines.add('تارگت‌ها: ${t.join(' / ')}');
      if (p.leverage != null) { lev = p.leverage!.clamp(1, 50).toDouble(); lines.add('اهرم: ${p.leverage!.toStringAsFixed(0)}x'); }
      info = lines.isEmpty ? 'چیزی تشخیص داده نشد؛ متن را بررسی کنید.' : 'اطلاعات جانمایی شد - لطفاً صحت را بررسی و تایید کنید:\n${lines.join('\n')}';
    });
  }

  Future<void> submit() async {
    final s = sym.text.trim().toUpperCase();
    final tps = [_n(tp1), _n(tp2), _n(tp3)].where((e) => e > 0).toList();
    final px = type == 'market' ? (app.prices[s] ?? 0) : _n(price);
    final m = _n(margin);
    final slv = _n(sl);
    final err = <String>[];
    if (px <= 0) err.add('قیمت ورود/بازار مشخص نیست (ابتدا بررسی/اسکن کنید)');
    if (slv > 0 && (side == Side.long ? slv >= px : slv <= px)) err.add('حد ضرر در سمت اشتباه است');
    for (final t in tps) {
      if (side == Side.long ? t <= px : t >= px) err.add('تارگت $t در سمت اشتباه است');
    }
    if (err.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.join('\n'))));
      return;
    }
    final notional = m * lev;
    final risk = slv > 0 ? (px - slv).abs() / px * notional : 0.0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تایید سفارش'),
        content: Text('$s ${side.label} (${type.toUpperCase()})\nقیمت: ${fmtP(px)}\nمارجین: $m  x${lev.toStringAsFixed(0)} = حجم ${notional.toStringAsFixed(1)} USDT\nحد ضرر: ${slv > 0 ? fmtP(slv) : 'ندارد'}${slv > 0 ? '\nریسک تقریبی: ${risk.toStringAsFixed(2)} USDT' : ''}\nتارگت‌ها: ${tps.isEmpty ? 'ندارد' : tps.join(' / ')}\nحالت حساب: ${app.cfg['mode']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('اجرا')),
        ],
      ),
    );
    if (ok != true) return;
    final r = app.placeManual(sym: s, side: side, type: type, price: px, sl: slv, tps: tps, margin: m, lev: lev);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r ?? 'سفارش ثبت شد')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ورود دستی سیگنال', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        NumTile('نماد (مثلاً BTCUSDT)', sym.text, (v) => sym.text = v.toUpperCase(), text: true),
        SegmentedButton<Side>(
          segments: const [ButtonSegment(value: Side.long, label: Text('خرید / LONG')), ButtonSegment(value: Side.short, label: Text('فروش / SHORT'))],
          selected: {side},
          onSelectionChanged: (s) => setState(() => side = s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'market', label: Text('مارکت')), ButtonSegment(value: 'limit', label: Text('لیمیت')), ButtonSegment(value: 'stop', label: Text('استاپ'))],
          selected: {type},
          onSelectionChanged: (s) => setState(() => type = s.first),
        ),
        if (type != 'market') TextField(controller: price, textDirection: TextDirection.ltr, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قیمت ورود / تریگر')),
        TextField(controller: margin, textDirection: TextDirection.ltr, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مارجین (USDT)')),
        Row(children: [Text('اهرم ${lev.toStringAsFixed(0)}x'), Expanded(child: Slider(value: lev, min: 1, max: 50, divisions: 49, onChanged: (v) => setState(() => lev = v)))]),
        TextField(controller: sl, textDirection: TextDirection.ltr, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد ضرر (اختیاری)')),
        Row(children: [
          for (final t in [tp1, tp2, tp3])
            Expanded(child: Padding(padding: const EdgeInsets.all(2), child: TextField(controller: t, textDirection: TextDirection.ltr, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'TP${[tp1, tp2, tp3].indexOf(t) + 1}')))),
        ]),
        const SizedBox(height: 10),
        FilledButton(onPressed: submit, child: const Text('بررسی و اجرا')),
      ])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('جای‌گذاری متن سیگنال (تلگرام)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: paste, maxLines: 6, textDirection: TextDirection.ltr, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '#BTCUSDT LONG\nEntry: 65000-65200\nTP1: 66000 TP2: 67000\nSL: 64000\nLeverage: 10x')),
        const SizedBox(height: 8),
        FilledButton.tonal(onPressed: parse, child: const Text('تایید و جانمایی اطلاعات')),
        if (info.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(info, style: const TextStyle(color: kGreen, fontSize: 13))),
      ])),
    ]);
  }
}
