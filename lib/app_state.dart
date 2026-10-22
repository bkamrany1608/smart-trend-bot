import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/models.dart';
import 'core/params.dart';
import 'core/series.dart';
import 'core/sim.dart';
import 'core/optimizer.dart';
import 'data/market_data.dart';
import 'services/telegram.dart';
import 'services/journal.dart';
import 'services/broker.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAlive());
}

class _KeepAlive extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

final app = AppState();

class AppState extends ChangeNotifier {
  late SharedPreferences sp;
  Params params = Params();
  Map<String, dynamic> cfg = {
    'risk': 'medium', 'scanMin': 5, 'tf': '15m', 'nSym': 20, 'autoSymbols': true,
    'autoTrade': true, 'running': false, 'start': 1000.0, 'mode': 'virtual', 'liveOk': false,
    'tgToken': '', 'tgChat': '', 'tgOn': true, 'tgScan': false,
    'binKey': '', 'binSecret': '', 'autoTune': false, 'lastTune': 0, 'lastDay': '',
  };
  late Sim sim;
  final md = MarketData();
  Map<String, dynamic> tuneMeta = {};
  final Map<String, RegimeInfo> regimes = {};
  final Map<String, double> prices = {};
  final Map<String, int> lastBar = {};
  List<String> symbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT'];
  String sel = 'BTCUSDT';
  List<List<double>> eqHist = [];
  List<Map<String, dynamic>> pendingOrders = [];
  final List<String> logs = [];
  Timer? _scanTimer, _checkTimer;
  bool scanning = false, checking = false, tuning = false;
  String? lastError;
  int lastScanAt = 0, lastCheckAt = 0, _symAt = 0;
  double? exBal;
  Regime? _btcReg;

  Telegram get tgc => Telegram(cfg['tgToken'], cfg['tgChat']);
  int get scanMin => (cfg['scanMin'] as num).toInt();
  String get tf => cfg['tf'];
  int get barMs => tfMs[tf] ?? 900000;
  int get now => DateTime.now().millisecondsSinceEpoch;

  BinanceFutures? get broker {
    if (cfg['mode'] == 'virtual') return null;
    final b = BinanceFutures(cfg['binKey'], cfg['binSecret'], cfg['mode'] == 'testnet');
    return b.ok ? b : null;
  }

  Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    final c = sp.getString('cfg');
    if (c != null) cfg.addAll(Map<String, dynamic>.from(jsonDecode(c)));
    var base = Params().copyWith(Params.riskPreset(cfg['risk']));
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/params.json'));
      if (j['params'] is Map) base = base.copyWith(Params.fromJson(j['params']).m);
      tuneMeta = Map<String, dynamic>.from(j['meta'] ?? {});
    } catch (_) {}
    final pj = sp.getString('params');
    params = pj != null ? Params.fromJson(jsonDecode(pj)) : base;
    sim = Sim(params, (cfg['start'] as num).toDouble());
    final sj = sp.getString('sim');
    if (sj != null) {
      try {
        sim.load(jsonDecode(sj));
      } catch (_) {}
    }
    sim.eng.onOrder = _hook;
    final eq = sp.getString('eq');
    if (eq != null) eqHist = (jsonDecode(eq) as List).map<List<double>>((e) => (e as List).map<double>((x) => (x as num).toDouble()).toList()).toList();
    final po = sp.getString('pend');
    if (po != null) pendingOrders = List<Map<String, dynamic>>.from((jsonDecode(po) as List).map((e) => Map<String, dynamic>.from(e)));
    final sy = sp.getStringList('symbols');
    if (sy != null && sy.isNotEmpty) symbols = sy;
    sel = symbols.first;
    if (cfg['running'] == true) {
      _startTimers();
      Future.delayed(const Duration(seconds: 2), () {
        _startService();
        scanNow();
      });
    }
  }

  Future<void> save() async {
    await sp.setString('cfg', jsonEncode(cfg));
    await sp.setString('params', jsonEncode(params.toJson()));
    await sp.setString('sim', jsonEncode(sim.toJson()));
    if (eqHist.length > 2000) eqHist = eqHist.sublist(eqHist.length - 2000);
    await sp.setString('eq', jsonEncode(eqHist));
    await sp.setString('pend', jsonEncode(pendingOrders));
    await sp.setStringList('symbols', symbols);
  }

  void refresh() => notifyListeners();

  void setParams(Params p) {
    params = p;
    sim.setParams(p);
    sim.eng.onOrder = _hook;
    save();
    notifyListeners();
  }

  void setRisk(String level) {
    cfg['risk'] = level;
    setParams(params.copyWith(Params.riskPreset(level)));
  }

  void setCfg(String k, dynamic v) {
    cfg[k] = v;
    if (k == 'scanMin' && cfg['running'] == true) _startTimers();
    save();
    notifyListeners();
  }

  void resetAccount(double start) {
    cfg['start'] = start;
    sim = Sim(params, start)..eng.onOrder = _hook;
    eqHist = [];
    pendingOrders = [];
    save();
    notifyListeners();
  }

  void _log(String m) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, '$t  $m');
    if (logs.length > 200) logs.removeLast();
  }

  Future<void> tg(String text) async {
    if (cfg['tgOn'] == true && tgc.ok) await tgc.send(text);
  }

  void _report(Basket b, List<String> lines) {
    if (lines.isEmpty) return;
    for (final l in lines) {
      _log('${b.symbol} $l');
    }
    tg('${b.symbol} ${b.side.label} [${b.mode}]\n${lines.join('\n')}');
  }

  // ---------- broker mirroring (testnet / live) ----------
  void _hook(Basket b, Side side, double qty, bool reduce) {
    final br = broker;
    if (br == null || b.mode == 'virtual') return;
    () async {
      try {
        final r = await br.market(b.symbol, side, qty, reduce: reduce);
        if (r != 'ok') _log('broker: $r');
      } catch (e) {
        _log('BROKER ERROR $e');
        tg('⚠️ Broker error ${b.symbol}: $e');
      }
    }();
  }

  Future<void> _afterOpen(Basket b) async {
    final br = broker;
    if (br == null || b.mode == 'virtual') return;
    try {
      await br.setLeverage(b.symbol, params['leverage'].round());
      if (b.sl > 0) await br.setStop(b.symbol, b.side, b.sl);
    } catch (e) {
      _log('BROKER ERROR $e');
      tg('⚠️ Broker setup error ${b.symbol}: $e');
    }
  }

  // ---------- timers / service ----------
  void _startTimers() {
    _scanTimer?.cancel();
    _checkTimer?.cancel();
    _scanTimer = Timer.periodic(Duration(minutes: scanMin), (_) => scanNow());
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) => checkNow());
  }

  Future<void> _startService() async {
    try {
      await FlutterForegroundTask.requestNotificationPermission();
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'trend_bot',
          channelName: 'Trend bot',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Smart Trend Bot',
        notificationText: 'running - scanning markets',
        callback: startCallback,
      );
    } catch (e) {
      _log('foreground service: $e');
    }
  }

  Future<void> setRunning(bool on) async {
    cfg['running'] = on;
    if (on) {
      await _startService();
      _startTimers();
      scanNow();
    } else {
      _scanTimer?.cancel();
      _checkTimer?.cancel();
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
    }
    await save();
    notifyListeners();
  }

  // ---------- scanning ----------
  Future<void> scanNow() async {
    if (scanning) return;
    scanning = true;
    lastError = null;
    notifyListeners();
    try {
      if (cfg['autoSymbols'] == true && now - _symAt > 3600000) {
        symbols = await md.topSymbols((cfg['nSym'] as num).toInt());
        _symAt = now;
        if (!symbols.contains(sel)) sel = symbols.first;
      }
      try {
        prices.addAll(await md.allPrices());
      } catch (_) {}
      if (broker != null) {
        try {
          exBal = await broker!.usdtBalance();
        } catch (e) {
          _log('balance: $e');
        }
      }
      final queue = [...symbols];
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final s = queue.removeLast();
          try {
            await _scanSymbol(s);
          } catch (e) {
            lastError = '$s: $e';
          }
        }
      }

      await Future.wait(List.generate(4, (_) => worker()));
      sim.settle(now, barMs);
      lastScanAt = now;
      final btc = regimes['BTCUSDT'];
      if (btc != null) {
        if (_btcReg != null && _btcReg != btc.regime && cfg['autoTune'] == true && now - (cfg['lastTune'] as num) > 7200000) {
          tuneNow();
        }
        _btcReg = btc.regime;
      }
      if (cfg['tgScan'] == true) {
        final up = regimes.values.where((r) => r.regime == Regime.up).length;
        final dn = regimes.values.where((r) => r.regime == Regime.down).length;
        tg('🔎 scan done: ${regimes.length} symbols | up $up | down $dn | open ${sim.open.length}');
      }
    } catch (e) {
      lastError = '$e';
    } finally {
      scanning = false;
      await save();
      notifyListeners();
    }
  }

  Future<void> _scanSymbol(String s) async {
    final c = await md.klines(s, tf, limit: 500);
    if (c.length < 260) return;
    final ser = Series(c);
    final i = c.length - 1;
    final reg = ser.regimeAt(i, params);
    regimes[s] = reg;
    final newBar = (lastBar[s] ?? 0) < c[i].t;
    if (!newBar) return;
    lastBar[s] = c[i].t;
    for (final b in sim.open.where((b) => b.symbol == s && b.auto && c[i].t > b.openedAt).toList()) {
      final lines = sim.eng.manage(b,
          hi: c[i].h, lo: c[i].l, close: c[i].c, atrNow: ser.atrA[i], reg: reg, t: c[i].t, balance: sim.balance);
      _report(b, lines);
    }
    sim.settle(now, barMs);
    if (cfg['autoTrade'] != true) return;
    if (sim.open.any((b) => b.symbol == s) || sim.open.length >= params['maxOpen']) return;
    if ((sim.cool[s] ?? 0) > now) return;
    if (reg.regime != Regime.up && reg.regime != Regime.down) return;
    final sg = ser.signalAt(s, i, params);
    if (sg == null || sg.score < params['minScore']) return;
    final fresh = now - (c[i].t + barMs) < barMs * 0.6;
    final px = prices[s] ?? c.last.c;
    if (!fresh || (px - sg.price).abs() > 0.6 * sg.atr) return;
    if (sg.side == Side.long ? px <= sg.sl : px >= sg.sl) return;
    final bal = exBal ?? sim.balance;
    final b = sim.eng.open(s, sg.side, px, sg.sl, bal, now, score: sg.score, mode: cfg['mode'], note: sg.reason);
    b.atr = sg.atr;
    sim.open.add(b);
    _report(b, b.log);
    _afterOpen(b);
  }

  // ---------- 1-minute check of open (virtual) trades ----------
  Future<void> checkNow() async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      prices.addAll(await md.allPrices());
      for (final o in pendingOrders.toList()) {
        final px = prices[o['sym']];
        if (px == null) continue;
        final long = o['side'] == 0;
        final lim = (o['price'] as num).toDouble();
        final hit = o['type'] == 'limit' ? (long ? px <= lim : px >= lim) : (long ? px >= lim : px <= lim);
        if (hit) {
          pendingOrders.remove(o);
          _openManual(o, px);
        }
      }
      for (final b in sim.open.toList()) {
        final px = prices[b.symbol];
        if (px == null) continue;
        final lines = sim.eng.manage(b, hi: px, lo: px, close: px, t: now, balance: sim.balance);
        _report(b, lines);
      }
      sim.settle(now, barMs);
      lastCheckAt = now;
      eqHist.add([now.toDouble(), sim.equity(prices)]);
      await _rollover();
    } catch (e) {
      lastError = '$e';
    } finally {
      checking = false;
      await save();
      notifyListeners();
    }
  }

  // ---------- manual orders ----------
  String? placeManual({
    required String sym, required Side side, required String type, double price = 0,
    double sl = 0, List<double> tps = const [], required double margin, required double lev,
  }) {
    if (margin <= 0 || margin > sim.balance) return 'مارجین بیشتر از موجودی یا نامعتبر است';
    final px = prices[sym];
    if (px == null && type == 'market') return 'قیمت لحظه‌ای ${sym} در دسترس نیست (اسکن/چک کنید)';
    final o = {
      'id': '${now}_$sym', 'sym': sym, 'side': side.index, 'type': type, 'price': price,
      'sl': sl, 'tps': tps, 'margin': margin, 'lev': lev,
    };
    if (type == 'market') {
      _openManual(o, px!);
    } else {
      pendingOrders.add(o);
      _log('pending ${type.toUpperCase()} $sym @$price');
      tg('📝 Pending $type ${side.label} $sym @$price');
    }
    save();
    notifyListeners();
    return null;
  }

  void _openManual(Map o, double px) {
    final side = Side.values[o['side'] as int];
    final sl = (o['sl'] as num).toDouble();
    final lev = (o['lev'] as num).toDouble();
    final margin = (o['margin'] as num).toDouble();
    final qty = margin * lev / px;
    final slForR = sl > 0 ? sl : px * (1 - 0.01 * side.sign);
    final b = sim.eng.open(o['sym'], side, px, slForR, sim.balance, now,
        mode: cfg['mode'], qty: qty, note: 'manual x${lev.toStringAsFixed(0)}');
    b.auto = false;
    b.sl = sl;
    final tps = (o['tps'] as List).map((e) => (e as num).toDouble()).toList();
    b.tps = [for (final t in tps) [t, 1 / tps.length, 0.0]];
    sim.open.add(b);
    _report(b, b.log);
    _afterOpen(b);
  }

  void closeBasket(Basket b) {
    final px = prices[b.symbol] ?? b.ref;
    sim.eng.closeNow(b, px, now);
    sim.settle(now, barMs);
    _report(b, [b.log.last]);
    save();
    notifyListeners();
  }

  void cancelPending(Map o) {
    pendingOrders.remove(o);
    save();
    notifyListeners();
  }

  // ---------- journal / reports ----------
  Future<File> journal() => buildJournal(sim);

  Future<String> sendJournal([String caption = 'Journal']) async {
    final f = await journal();
    if (!tgc.ok) return 'تلگرام تنظیم نشده؛ فایل ذخیره شد: ${f.path}';
    final ok = await tgc.sendFile(f.path, caption: caption);
    return ok ? 'ارسال شد' : 'ارسال ناموفق؛ فایل: ${f.path}';
  }

  Future<void> _rollover() async {
    final d = dayKey(DateTime.now());
    final last = cfg['lastDay'] as String;
    if (last.isEmpty) {
      cfg['lastDay'] = d;
      return;
    }
    if (last == d) return;
    cfg['lastDay'] = d;
    final y = DateTime.now().subtract(const Duration(days: 1));
    final list = sim.closed.where((b) => dayKey(tOf(b)) == dayKey(y)).toList();
    final st = computeStats(list, sim.balance);
    final buf = StringBuffer('📊 Daily ${dayKey(y)}: ${st.n} trades, win ${st.winRate.toStringAsFixed(0)}%, net ${st.net.toStringAsFixed(2)} | balance ${sim.balance.toStringAsFixed(2)}');
    final today = DateTime.now();
    if (today.weekday == DateTime.monday) {
      final wk = sim.closed.where((b) => weekKey(tOf(b)) == weekKey(y)).toList();
      buf.write('\nWeekly ${weekKey(y)}: net ${computeStats(wk, 0).net.toStringAsFixed(2)} (${wk.length} trades)');
    }
    if (today.day == 1) {
      final mo = sim.closed.where((b) => monthKey(tOf(b)) == monthKey(y)).toList();
      buf.write('\nMonthly ${monthKey(y)}: net ${computeStats(mo, 0).net.toStringAsFixed(2)} (${mo.length} trades)');
    }
    await tg(buf.toString());
    if (tgc.ok) await sendJournal('Journal ${dayKey(y)}');
  }

  // ---------- adaptive training ----------
  Future<String> tuneNow() async {
    if (tuning) return 'در حال اجراست';
    tuning = true;
    notifyListeners();
    try {
      final raw = <String, List<List<double>>>{};
      for (final s in symbols.take(6)) {
        final c = await md.klines(s, '15m', limit: 1000);
        raw[s] = c.map((x) => [x.t.toDouble(), x.o, x.h, x.l, x.c, x.v]).toList();
      }
      final base = params;
      final res = await Isolate.run(() {
        final data = <String, Series>{
          for (final e in raw.entries)
            e.key: Series(e.value.map((r) => Candle(r[0].toInt(), r[1], r[2], r[3], r[4], r[5])).toList())
        };
        return jsonEncode(optimize(data, base, quickGrid, split: 0.6).toJson());
      });
      final j = jsonDecode(res);
      cfg['lastTune'] = now;
      final test = j['test'], def = j['testDefault'];
      final msg = 'hold-out: ${test['n']} trades, PF ${(test['pf'] as num).toStringAsFixed(2)}, net ${(test['net'] as num).toStringAsFixed(1)}, DD ${(test['maxDD'] as num).toStringAsFixed(1)}%\n'
          'defaults: PF ${(def['pf'] as num).toStringAsFixed(2)}, net ${(def['net'] as num).toStringAsFixed(1)}';
      if (j['accepted'] == true) {
        setParams(params.copyWith(Map<String, double>.from((j['best'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())))));
        tuneMeta = {'validated': true, 'date': DateTime.now().toIso8601String(), 'holdout': test};
        tg('🧠 Parameters re-tuned and applied\n$msg');
        return 'اعمال شد ✅\n$msg\n${jsonEncode(j['best'])}';
      }
      tg('🧠 Re-tune finished, NOT applied (failed hold-out check)\n$msg');
      return 'اعمال نشد (اعتبارسنجی رد شد) ❌\n$msg';
    } catch (e) {
      return 'خطا: $e';
    } finally {
      tuning = false;
      await save();
      notifyListeners();
    }
  }

  // ---------- helpers for UI ----------
  double get equity => sim.equity(prices);
  double unreal(Basket b) => sim.eng.total(b, prices[b.symbol] ?? b.ref);
}
