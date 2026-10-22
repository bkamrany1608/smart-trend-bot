import 'package:flutter/material.dart';
import '../app_state.dart';
import 'trades_page.dart';
import 'chart_page.dart';
import 'manual_page.dart';
import 'report_page.dart';
import 'train_page.dart';
import 'settings_page.dart';

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    const pages = <Widget>[TradesPage(), ChartPage(), ManualPage(), ReportPage(), TrainPage(), SettingsPage()];
    return ListenableBuilder(
      listenable: app,
      builder: (c, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Smart Trend Bot', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: 'اسکن فوری',
              icon: app.scanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar),
              onPressed: app.scanning ? null : app.scanNow,
            ),
            IconButton(
              tooltip: 'بررسی فوری معاملات',
              icon: app.checking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
              onPressed: app.checking ? null : app.checkNow,
            ),
            Switch(value: app.cfg['running'] == true, onChanged: (v) => app.setRunning(v)),
          ],
        ),
        body: SafeArea(child: pages[idx]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: (i) => setState(() => idx = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.show_chart), label: 'معاملات'),
            NavigationDestination(icon: Icon(Icons.candlestick_chart), label: 'چارت'),
            NavigationDestination(icon: Icon(Icons.edit_note), label: 'دستی'),
            NavigationDestination(icon: Icon(Icons.insights), label: 'گزارش'),
            NavigationDestination(icon: Icon(Icons.psychology), label: 'آموزش'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'تنظیمات'),
          ],
        ),
      ),
    );
  }
}
