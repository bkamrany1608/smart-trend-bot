import 'package:flutter/material.dart';
import '../app_state.dart';
import '../core/params.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String tgMsg = '';

  Widget pSwitch(String label, String key) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: app.params[key] > 0,
        onChanged: (v) => app.setParams(app.params.copyWith({key: v ? 1 : 0})),
      );

  Widget pNum(String label, String key) => NumTile(label, app.params[key].toString(), (v) {
        final d = double.tryParse(v);
        if (d != null) app.setParams(app.params.copyWith({key: d}));
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (c, _) => ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('عمومی', style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('معامله خودکار'), value: app.cfg['autoTrade'] == true, onChanged: (v) => app.setCfg('autoTrade', v)),
          const Text('سطح ریسک'),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'low', label: Text('کم')), ButtonSegment(value: 'medium', label: Text('متوسط')), ButtonSegment(value: 'high', label: Text('زیاد'))],
            selected: {app.cfg['risk'] as String},
            onSelectionChanged: (s) => app.setRisk(s.first),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('فاصله اسکن (دقیقه)'),
            const Spacer(),
            DropdownButton<int>(
              value: [1, 3, 5, 10, 15, 30].contains(app.scanMin) ? app.scanMin : 5,
              items: [1, 3, 5, 10, 15, 30].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
              onChanged: (v) => app.setCfg('scanMin', v),
            ),
          ]),
          Row(children: [
            const Text('تایم‌فریم'),
            const Spacer(),
            DropdownButton<String>(
              value: app.tf,
              items: ['5m', '15m', '30m', '1h'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) {
                app.lastBar.clear();
                app.setCfg('tf', v);
              },
            ),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('انتخاب خودکار پرحجم‌ترین ارزهای USDT'), value: app.cfg['autoSymbols'] == true, onChanged: (v) => app.setCfg('autoSymbols', v)),
          NumTile('تعداد ارزها برای اسکن', '${app.cfg['nSym']}', (v) => app.setCfg('nSym', int.tryParse(v) ?? 20)),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('استراتژی (فعال/غیرفعال)', style: TextStyle(fontWeight: FontWeight.bold)),
          pSwitch('تایید روند تایم‌فریم بالاتر', 'htf'),
          pSwitch('ورود هرمی', 'pyrOn'),
          pSwitch('ریکاوری هوشمند', 'recOn'),
          pSwitch('خروج با تغییر روند', 'flip'),
          pNum('حداقل امتیاز سیگنال', 'minScore'),
          pNum('حداقل ADX (فیلتر رنج)', 'adxMin'),
          pNum('حد نوسان شدید (ATR ratio)', 'volSpike'),
          pNum('ضریب تریلینگ (ATR)', 'trailAtr'),
          pNum('خروج با اصلاح از سود (۰.۱۰ = ۱۰٪)', 'give'),
          pNum('حداقل سود برای فعال‌شدن خروج اصلاح (R)', 'giveMinR'),
          pNum('ریسک هر معامله (% حساب)', 'riskPct'),
          pNum('سقف زیان کل سبد (% حساب)', 'basketCap'),
          pNum('حداکثر پله هرمی', 'maxSteps'),
          pNum('ضریب حجم پله', 'pyrMult'),
          pNum('ضریب حجم ریکاوری', 'recMult'),
          pNum('حداکثر ریکاوری', 'maxRec'),
          pNum('حداکثر سبد همزمان', 'maxOpen'),
          pNum('اهرم', 'leverage'),
          TextButton(onPressed: () => app.setParams(Params().copyWith(Params.riskPreset(app.cfg['risk']))), child: const Text('بازگشت به پیش‌فرض')),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('تلگرام', style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('ارسال گزارش‌ها'), value: app.cfg['tgOn'] == true, onChanged: (v) => app.setCfg('tgOn', v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('گزارش هر اسکن'), value: app.cfg['tgScan'] == true, onChanged: (v) => app.setCfg('tgScan', v)),
          NumTile('Bot Token', app.cfg['tgToken'], (v) => app.setCfg('tgToken', v.trim()), text: true, obscure: true),
          NumTile('Chat ID', app.cfg['tgChat'], (v) => app.setCfg('tgChat', v.trim()), text: true),
          FilledButton.tonal(
            onPressed: () async {
              final ok = await app.tgc.send('✅ Smart Trend Bot connected');
              setState(() => tgMsg = ok ? 'پیام تست ارسال شد' : 'ارسال ناموفق (توکن/چت‌آیدی/اینترنت را بررسی کنید)');
            },
            child: const Text('ارسال پیام تست'),
          ),
          if (tgMsg.isNotEmpty) Text(tgMsg, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('بروکر (Binance Futures)', style: TextStyle(fontWeight: FontWeight.bold)),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'virtual', label: Text('مجازی')), ButtonSegment(value: 'testnet', label: Text('دمو')), ButtonSegment(value: 'live', label: Text('واقعی'))],
            selected: {app.cfg['mode'] as String},
            onSelectionChanged: (s) async {
              final m = s.first;
              if (m == 'live') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('هشدار حساب واقعی'),
                    content: const Text('معاملات با پول واقعی انجام می‌شود و ضرر ممکن است. پیشنهاد: ابتدا حداقل ۲ هفته روی دمو تست کنید و با مبلغ کم شروع کنید. ادامه می‌دهید؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ادامه')),
                    ],
                  ),
                );
                if (ok != true) return;
              }
              app.setCfg('mode', m);
            },
          ),
          NumTile('API Key', app.cfg['binKey'], (v) => app.setCfg('binKey', v.trim()), text: true, obscure: true),
          NumTile('API Secret', app.cfg['binSecret'], (v) => app.setCfg('binSecret', v.trim()), text: true, obscure: true),
          const Text('کلید را فقط با دسترسی Trade بسازید و Withdraw را غیرفعال کنید. دمو: testnet.binancefuture.com', style: TextStyle(fontSize: 11, color: Colors.white54)),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('حساب مجازی', style: TextStyle(fontWeight: FontWeight.bold)),
          NumTile('سرمایه اولیه (فقط با ریست اعمال می‌شود)', '${app.cfg['start']}', (v) => app.cfg['start'] = double.tryParse(v) ?? 1000.0),
          FilledButton.tonal(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('ریست حساب مجازی؟'),
                  content: const Text('تمام معاملات و تاریخچه پاک می‌شود.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('خیر')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بله')),
                  ],
                ),
              );
              if (ok == true) app.resetAccount((app.cfg['start'] as num).toDouble());
            },
            child: const Text('ریست حساب'),
          ),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('لاگ برنامه', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final l in app.logs.take(30)) Text(l, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ])),
      ]),
    );
  }
}
