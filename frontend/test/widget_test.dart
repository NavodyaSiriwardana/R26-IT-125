import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('TruthLens app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TruthLensApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
