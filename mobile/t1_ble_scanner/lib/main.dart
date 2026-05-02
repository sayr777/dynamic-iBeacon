import 'package:flutter/material.dart';

import 'src/ui/scanner_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const T1BleScannerApp());
}

class T1BleScannerApp extends StatelessWidget {
  const T1BleScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1D4ED8);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'T1 BLE Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: const ScannerPage(),
    );
  }
}
