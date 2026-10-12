import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'mobile_face_scan_overlay.dart';

/// The camera view is separate from the camera/session controller so its real
/// layout can be rendered and checked at phone sizes without a device.
class MobileFaceVerificationView extends StatelessWidget {
  final String courseCode;
  final String instruction;
  final String detail;
  final Widget? cameraPreview;
  final bool faceAligned;
  final FaceGuidePhase guidePhase;
  final bool showRetry;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  const MobileFaceVerificationView({
    super.key,
    required this.courseCode,
    required this.instruction,
    required this.detail,
    required this.cameraPreview,
    required this.faceAligned,
    required this.guidePhase,
    required this.showRetry,
    required this.onClose,
    required this.onRetry,
  });

  static const _ink = Color(0xFF101828);
  static const _muted = Color(0xFF667085);
  static const _blue = Color(0xFF165DFF);

  @override
  Widget build(BuildContext context) {
    final cameraReady = cameraPreview != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: onClose,
                    tooltip: 'Đóng xác minh',
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _ink,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Xác minh khuôn mặt',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            color: _ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Điểm danh $courseCode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            color: _muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: cameraReady
                  ? ColoredBox(
                      color: const Color(0xFF152235),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 360),
                            curve: Curves.easeOut,
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: (1 - value) * 2,
                                  sigmaY: (1 - value) * 2,
                                ),
                                child: child,
                              ),
                            ),
                            child: RepaintBoundary(child: cameraPreview),
                          ),
                          IgnorePointer(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 360),
                              builder: (context, value, child) =>
                                  Opacity(opacity: value, child: child),
                              child: RepaintBoundary(
                                child: MobileFaceScanOverlay(
                                  faceAligned: faceAligned,
                                  phase: guidePhase,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ColoredBox(
                      color: const Color(0xFFEDF2F8),
                      child: Center(
                        child: Icon(
                          showRetry
                              ? Icons.no_photography_outlined
                              : Icons.camera_front_outlined,
                          size: 56,
                          color: const Color(0xFF98A8BF),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 66),
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .05),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey<String>(instruction),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            instruction,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'BeVietnamPro',
                              color: _ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 5),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Text(
                              detail,
                              key: ValueKey<String>(detail),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'BeVietnamPro',
                                color: _muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showRetry)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      minimumSize: const Size.fromHeight(48),
                      textStyle: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Thử lại'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
