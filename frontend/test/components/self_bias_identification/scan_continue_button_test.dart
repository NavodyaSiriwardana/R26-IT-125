import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/widgets/scan_continue_button.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('in the bottom bar it is button-sized, not screen-sized',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: ScanContinueButton(onTap: () => taps++),
          ),
        ),
      ),
    ));
    final size = tester.getSize(find.byKey(const Key('scan-continue')));
    expect(size.height, lessThan(90), reason: 'it must not fill the screen');
    expect(size.height, greaterThan(40));
    expect(size.width, closeTo(680, 1)); // full width less the 20px margins
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-continue')));
    expect(taps, 1);
  });

  testWidgets('inside a scrolling page it is the same size', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScanContinueButton(onTap: () {}),
        ),
      ),
    ));
    final size = tester.getSize(find.byKey(const Key('scan-continue')));
    expect(size.height, lessThan(90));
  });
}
