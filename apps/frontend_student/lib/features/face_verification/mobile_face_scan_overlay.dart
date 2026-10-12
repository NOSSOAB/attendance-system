import 'dart:math' as math;

import 'package:flutter/material.dart';

enum FaceGuidePhase {
  align,
  hold,
  blink,
  smile,
  turnLeft,
  turnRight,
  forward,
  success,
  error,
}

Rect faceOvalFor(Size size) {
  final width = math.min(size.width * .76, size.height * .61);
  final height = width * 1.30;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * .48),
    width: width,
    height: height,
  );
}

/// A calm mask and a translucent, animated head drawn over the live preview.
class MobileFaceScanOverlay extends StatefulWidget {
  final bool faceAligned;
  final FaceGuidePhase phase;

  const MobileFaceScanOverlay({
    super.key,
    required this.faceAligned,
    required this.phase,
  });

  @override
  State<MobileFaceScanOverlay> createState() => _MobileFaceScanOverlayState();
}

class _MobileFaceScanOverlayState extends State<MobileFaceScanOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _alignment;
  late final AnimationController _pose;
  late final AnimationController _success;
  double _fromYaw = 0;
  double _toYaw = 0;

  double get _yaw =>
      _fromYaw + (_toYaw - _fromYaw) * Curves.easeInOut.transform(_pose.value);

  @override
  void initState() {
    super.initState();
    _alignment = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: widget.faceAligned ? 1 : 0,
    );
    _pose = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _success = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.phase == FaceGuidePhase.success) _success.forward();
    _toYaw = _targetYaw(widget.phase);
    if (_toYaw != 0) _pose.forward();
  }

  static double _targetYaw(FaceGuidePhase phase) => switch (phase) {
    FaceGuidePhase.turnLeft => -.47,
    FaceGuidePhase.turnRight => .47,
    _ => 0,
  };

  @override
  void didUpdateWidget(covariant MobileFaceScanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.faceAligned != widget.faceAligned) {
      widget.faceAligned ? _alignment.forward() : _alignment.reverse();
    }
    if (oldWidget.phase != widget.phase) {
      // Capture the in-flight pose so changing direction never snaps.
      final currentYaw = _yaw;
      _pose.stop();
      _fromYaw = currentYaw;
      _toYaw = _targetYaw(widget.phase);
      _pose.duration = Duration(
        milliseconds: (550 + 220 * (_toYaw - _fromYaw).abs() / .47).round(),
      );
      _pose.forward(from: 0);
      if (widget.phase == FaceGuidePhase.success) {
        _success.forward(from: 0);
      } else if (oldWidget.phase == FaceGuidePhase.success) {
        _success.reset();
      }
    }
  }

  @override
  void dispose() {
    _alignment.dispose();
    _pose.dispose();
    _success.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_alignment, _pose, _success]),
    builder: (context, child) => CustomPaint(
      painter: FaceVerificationPainter(
        aligned: _alignment.value,
        yaw: _yaw,
        phase: widget.phase,
        success: _success.value,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

/// Draw order: dim outside the oval, head guide, oval border, final check.
class FaceVerificationPainter extends CustomPainter {
  final double aligned;
  final double yaw;
  final FaceGuidePhase phase;
  final double success;

  const FaceVerificationPainter({
    required this.aligned,
    required this.yaw,
    required this.phase,
    required this.success,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final oval = faceOvalFor(size);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(shade, Paint()..color = const Color(0x66091830));

    if (phase != FaceGuidePhase.error && success < 1) {
      canvas.save();
      canvas.clipPath(Path()..addOval(oval));
      _paintHead(canvas, oval, 1 - success);
      canvas.restore();
    }

    final base = Color.lerp(
      const Color(0xBDEAF2FF),
      const Color(0xFFEAF2FF),
      aligned,
    )!;
    canvas.drawOval(
      oval,
      Paint()
        ..color = Color.lerp(base, const Color(0xFF46CBA4), success)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (success > 0) {
      final check = Path()
        ..moveTo(oval.center.dx - 18, oval.center.dy)
        ..lineTo(oval.center.dx - 5, oval.center.dy + 13)
        ..lineTo(oval.center.dx + 20, oval.center.dy - 15);
      canvas.drawPath(
        check,
        Paint()
          ..color = const Color(0xFFDBFFF0).withValues(alpha: success)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _paintHead(Canvas canvas, Rect oval, double opacity) {
    final center = oval.center.translate(0, oval.height * .025);
    // Keep the guide close to real head proportions; a narrow, tall outline
    // looked distorted even when the oval and camera preview were correct.
    final sx = oval.width * .46;
    final sy = oval.height * .38;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    Offset project(double x, double y, [double z = 0]) {
      final rotatedX = x * c + z * s;
      final rotatedZ = z * c - x * s;
      final perspective = 1 + rotatedZ * .08;
      return Offset(
        center.dx + rotatedX * sx * perspective,
        center.dy + y * sy * perspective,
      );
    }

    final ink = const Color(0xFFD5F0FF).withValues(alpha: .23 * opacity);
    final shadow = const Color(0xFF183551).withValues(alpha: .13 * opacity);
    void stroke(List<(double, double, double)> points, {double width = 1.7}) {
      if (points.length < 2) return;
      final path = Path();
      final projected = [
        for (final point in points) project(point.$1, point.$2, point.$3),
      ];
      path.moveTo(projected.first.dx, projected.first.dy);
      for (var i = 1; i < projected.length - 1; i++) {
        final current = projected[i];
        final next = projected[i + 1];
        path.quadraticBezierTo(
          current.dx,
          current.dy,
          (current.dx + next.dx) / 2,
          (current.dy + next.dy) / 2,
        );
      }
      path.lineTo(projected.last.dx, projected.last.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = shadow
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 1.3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    stroke([
      (0, -1.03, -.08),
      (-.38, -.99, -.04),
      (-.68, -.78, .01),
      (-.81, -.43, .03),
      (-.81, -.05, .03),
      (-.72, .34, .06),
      (-.50, .72, .08),
      (-.22, .94, .09),
      (0, 1.00, .10),
      (.22, .94, .09),
      (.50, .72, .08),
      (.72, .34, .06),
      (.81, -.05, .03),
      (.81, -.43, .03),
      (.68, -.78, .01),
      (.38, -.99, -.04),
      (0, -1.03, -.08),
    ], width: 1.8);
    stroke([(-.52, -.55, .10), (-.32, -.60, .19), (-.15, -.59, .23)]);
    stroke([(.15, -.59, .23), (.32, -.60, .19), (.52, -.55, .10)]);
    for (final sign in [-1.0, 1.0]) {
      stroke([
        (sign * .52, -.26, .13),
        (sign * .40, -.30, .24),
        (sign * .25, -.28, .30),
        (sign * .15, -.24, .33),
        (sign * .29, -.20, .29),
        (sign * .43, -.21, .21),
        (sign * .52, -.26, .13),
      ], width: 1.5);
      stroke([
        (sign * .62, -.10, .06),
        (sign * .59, .11, .08),
        (sign * .52, .30, .13),
      ], width: 1.2);
    }
    stroke([
      (0, -.37, .30),
      (0, -.12, .48),
      (0, .20, .55),
      (-.13, .30, .43),
      (0, .34, .50),
      (.13, .30, .43),
    ]);
    stroke([
      (-.23, .51, .34),
      (-.10, .48, .40),
      (0, .49, .43),
      (.10, .48, .40),
      (.23, .51, .34),
    ], width: 1.4);
    stroke([(-.15, .55, .35), (0, .58, .40), (.15, .55, .35)], width: 1.1);
    stroke([(-.20, .76, .17), (0, .81, .21), (.20, .76, .17)], width: 1.1);
  }

  @override
  bool shouldRepaint(covariant FaceVerificationPainter old) =>
      aligned != old.aligned ||
      yaw != old.yaw ||
      phase != old.phase ||
      success != old.success;
}
