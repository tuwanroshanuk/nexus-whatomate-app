import 'package:flutter/material.dart';

void main() {
  runApp(const WhatomateApp());
}

class WhatomateApp extends StatelessWidget {
  const WhatomateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whatomate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0738F9),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(
              'Whatomate',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
