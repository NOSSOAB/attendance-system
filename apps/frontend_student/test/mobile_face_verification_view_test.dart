import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/features/face_verification/mobile_face_scan_overlay.dart';
import 'package:frontend_student/features/face_verification/mobile_face_verification_view.dart';

void main() {
  testWidgets('camera view stays legible on a compact phone with larger text', (
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
        home: MobileFaceVerificationView(
          courseCode: 'AI101',
          instruction: 'Quay nhẹ sang trái',
          detail: 'Di chuyển đầu theo khuôn mặt hướng dẫn',
          cameraPreview: const ColoredBox(color: Colors.black),
          faceAligned: true,
          guidePhase: FaceGuidePhase.turnLeft,
          showRetry: false,
          onClose: () {},
          onRetry: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
    expect(find.text('Quay nhẹ sang trái'), findsOneWidget);
    expect(find.text('Di chuyển đầu theo khuôn mặt hướng dẫn'), findsOneWidget);
    expect(find.text('Điểm danh AI101'), findsOneWidget);
    expect(find.text('Hủy'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final instruction = tester.widget<Text>(find.text('Quay nhẹ sang trái'));
    expect(instruction.style?.fontFamily, 'BeVietnamPro');
  });

  testWidgets('long error and retry do not overflow a compact phone', (
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
        home: MobileFaceVerificationView(
          courseCode: 'AI101',
          instruction:
              'Ứng dụng đã cũ. Hãy cài APK mới nhất để xác minh khuôn mặt',
          detail: 'Giữ điện thoại ổn định rồi thử lại',
          cameraPreview: null,
          faceAligned: false,
          guidePhase: FaceGuidePhase.error,
          showRetry: true,
          onClose: () {},
          onRetry: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    expect(find.text('Thử lại'), findsOneWidget);
  });
}
