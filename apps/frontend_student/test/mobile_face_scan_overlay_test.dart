import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/features/face_verification/mobile_face_scan_overlay.dart';

void main() {
  testWidgets('guide face turns through center without revealing progress', (
    tester,
  ) async {
    Widget scene(FaceGuidePhase phase) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 420,
          child: MobileFaceScanOverlay(faceAligned: true, phase: phase),
        ),
      ),
    );

    FaceVerificationPainter painter() =>
        (tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint &&
                        widget.painter is FaceVerificationPainter,
                  ),
                )
                .painter!
            as FaceVerificationPainter);

    await tester.pumpWidget(scene(FaceGuidePhase.align));
    expect(painter().yaw, 0);
    expect(
      faceOvalFor(const Size(320, 420)).height,
      greaterThan(faceOvalFor(const Size(320, 420)).width),
    );

    await tester.pumpWidget(scene(FaceGuidePhase.turnLeft));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(painter().yaw, lessThan(-.4));

    await tester.pumpWidget(scene(FaceGuidePhase.turnRight));
    expect(painter().yaw, lessThan(-.4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(painter().yaw.abs(), lessThan(.12));
    await tester.pump(const Duration(milliseconds: 600));
    expect(painter().yaw, greaterThan(.4));

    await tester.pumpWidget(scene(FaceGuidePhase.success));
    await tester.pump(const Duration(milliseconds: 350));
    expect(painter().success, 1);
    expect(tester.takeException(), isNull);
  });
}
