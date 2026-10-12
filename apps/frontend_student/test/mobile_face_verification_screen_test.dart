import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/features/face_verification/mobile_face_verification_screen.dart';

void main() {
  testWidgets('face verification controls fit a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MobileFaceVerificationScreen(
          accessToken: 'test',
          attendanceSessionId: 17,
          courseCode: 'AI101',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.text('Xác minh khuôn mặt'), findsOneWidget);
    expect(find.textContaining('Đang quét'), findsNothing);
    expect(find.textContaining('Xác minh AI101'), findsNothing);
    expect(find.textContaining('Bước '), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Đóng xác minh'), findsOneWidget);
  });

  testWidgets('face verification remains usable with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const MobileFaceVerificationScreen(
          accessToken: 'test',
          attendanceSessionId: 17,
          courseCode: 'AI101',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.text('Xác minh khuôn mặt'), findsOneWidget);
    expect(find.byTooltip('Đóng xác minh'), findsOneWidget);
  });
}
