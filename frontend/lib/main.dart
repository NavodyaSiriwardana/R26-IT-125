import 'package:flutter/material.dart';
import 'package:frontend/components/self_bias_identification/screens/login_screen.dart';

void main() {
  runApp(const TruthLensApp());
}

class TruthLensApp extends StatelessWidget {
  const TruthLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TruthLens',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF534AB7)),
      ),
      home: const LoginScreen(),
    );
  }
}
