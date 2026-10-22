import 'package:flutter/material.dart';
import 'app_state.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  runApp(const BotApp());
}

class BotApp extends StatelessWidget {
  const BotApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Trend Bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00BFA5), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0E1621),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0E1621), elevation: 0),
      ),
      builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
      home: const Home(),
    );
  }
}
