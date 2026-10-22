import 'package:flutter/material.dart';
import '../app_state.dart';
import 'widgets.dart';

class TrainPage extends StatefulWidget {
  const TrainPage({super.key});
  @override
  State<TrainPage> createState() => _TrainPageState();
}

class _TrainPageState extends State<TrainPage> {
  String result = '';
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (c, _) {
        final p = app.params;
        final meta = app.tuneMeta;
        return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('آموزش و بهینه‌سازی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('بهینه‌سازی walk-forward روی داده‌های اخیر: پارامترها روی بخش اول انتخاب و روی بخش دوم (دیده‌نشده) اعتبارسنجی می‌شوند. فقط در صورت بهتر بودن از پیش‌فرض و سودده بودن اعمال می‌شوند تا بیش‌برازش نشود.', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: app.tuning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high),
              label: Text(app.tuning ? 'در حال بهینه‌سازی...' : 'بهینه‌سازی روی داده‌های اخیر'),
              onPressed: app.tuning ? null : () async {
                final r = await app.tuneNow();
                setState(() => result = r);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('بهینه‌سازی خودکار هنگام تغییر روند'),
              subtitle: const Text('حداکثر هر ۲ ساعت'),
              value: app.cfg['autoTune'] == true,
              onChanged: (v) => app.setCfg('autoTune', v),
            ),
            if (result.isNotEmpty) Text(result, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ])),
          card(Column(children: [
            const Align(alignment: Alignment.centerRight, child: Text('نتیجه بهینه‌سازی زمان ساخت (روی داده تاریخی)', style: TextStyle(fontWeight: FontWeight.bold))),
            kv('اعتبارسنجی شده', meta['validated'] == true ? 'بله' : 'خیر / پیش‌فرض'),
            if (meta['holdout'] is Map) ...[
              kv('معاملات هولدآوت', '${meta['holdout']['n']}'),
              kv('PF', (meta['holdout']['pf'] as num).toStringAsFixed(2)),
              kv('نرخ برد', '${(meta['holdout']['winRate'] as num).toStringAsFixed(1)}%'),
              kv('حداکثر دراوداون', '${(meta['holdout']['maxDD'] as num).toStringAsFixed(1)}%'),
            ],
          ])),
          card(Column(children: [
            const Align(alignment: Alignment.centerRight, child: Text('پارامترهای فعلی', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final k in ['adxMin', 'pbMinAtr', 'slBuf', 'trailAtr', 'give', 'minScore', 'riskPct', 'basketCap', 'maxSteps', 'maxRec'])
              kv(k, p[k].toStringAsFixed(2)),
          ])),
        ]);
      },
    );
  }
}
