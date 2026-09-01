import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedGraduationBadge extends StatefulWidget {
  final double size;

  const AnimatedGraduationBadge({super.key, this.size = 260});

  @override
  State<AnimatedGraduationBadge> createState() =>
      _AnimatedGraduationBadgeState();
}

class _AnimatedGraduationBadgeState extends State<AnimatedGraduationBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _SmokePainter(_controller)),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _HatPainter(_controller)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmokePainter extends CustomPainter {
  final Animation<double> animation;

  _SmokePainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final t = animation.value * 2 * math.pi;

    // Khói/nền phía sau lưng mũ
    _drawSmokeBlob(
      canvas,
      center.translate(0, s * 0.015 - math.sin(t) * s * 0.010),
      radius: s * 0.235,
      wobble: 0.050,
      phase: 0.0,
      time: t,
      bottomColor: const Color(0xFFD7E3FF),
      topColor: const Color(0xFFF6F8FF),
    );

    _drawSmokeBlob(
      canvas,
      center.translate(s * 0.020, s * 0.000 - math.sin(t + 1.1) * s * 0.014),
      radius: s * 0.185,
      wobble: 0.042,
      phase: 1.4,
      time: t,
      bottomColor: const Color(0xFFE2EAFF),
      topColor: const Color(0xFFF9FAFF),
    );

    _drawSmokeBlob(
      canvas,
      center.translate(
        -s * 0.012,
        s * 0.042 - math.sin(2 * t + 2.0) * s * 0.012,
      ),
      radius: s * 0.155,
      wobble: 0.036,
      phase: 2.4,
      time: t,
      bottomColor: const Color(0xFFE7EEFF),
      topColor: const Color(0xFFFCFDFF),
    );

    _drawSoftSmokeMarks(canvas, center, s, t);
    _drawStars(canvas, center, s, t);
  }

  void _drawSmokeBlob(
    Canvas canvas,
    Offset center, {
    required double radius,
    required double wobble,
    required double phase,
    required double time,
    required Color bottomColor,
    required Color topColor,
  }) {
    final path = Path();
    const points = 28;

    for (int i = 0; i <= points; i++) {
      final p = i / points;
      final angle = p * 2 * math.pi;

      // Dùng bội số nguyên của time để animation loop kín vòng
      final wave1 = math.sin(angle * 3 + time + phase) * wobble;
      final wave2 = math.cos(angle * 5 - time * 2 + phase) * wobble * 0.45;
      final wave3 = math.sin(angle * 2 + time * 3 + phase) * wobble * 0.22;

      final r = radius * (1 + wave1 + wave2 + wave3);

      final x = center.dx + math.cos(angle) * r;
      final y = center.dy + math.sin(angle) * r;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();

    final rect = Rect.fromCenter(
      center: center,
      width: radius * 2.6,
      height: radius * 2.6,
    );

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          bottomColor.withValues(alpha: 0.95),
          topColor.withValues(alpha: 0.88),
        ],
      ).createShader(rect);

    canvas.drawPath(path, paint);
  }

  void _drawSoftSmokeMarks(Canvas canvas, Offset center, double s, double t) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.28);

    final riseA = math.sin(t) * s * 0.006;
    final riseB = math.sin(2 * t + 1.4) * s * 0.005;
    final riseC = math.sin(3 * t + 2.2) * s * 0.004;

    final marks = <RRect>[
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(-s * 0.09, s * 0.12 - riseA),
          width: s * 0.030,
          height: s * 0.050,
        ),
        Radius.circular(s * 0.01),
      ),
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(s * 0.08, s * 0.14 - riseB),
          width: s * 0.026,
          height: s * 0.045,
        ),
        Radius.circular(s * 0.01),
      ),
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(s * 0.00, s * 0.21 - riseC),
          width: s * 0.028,
          height: s * 0.048,
        ),
        Radius.circular(s * 0.01),
      ),
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(s * 0.11, -s * 0.08 - riseA),
          width: s * 0.024,
          height: s * 0.038,
        ),
        Radius.circular(s * 0.01),
      ),
    ];

    for (final mark in marks) {
      canvas.drawRRect(mark, paint);
    }
  }

  void _drawStars(Canvas canvas, Offset center, double s, double t) {
    _drawSparkle(
      canvas,
      center.translate(-s * 0.23, -s * 0.16),
      size: s * 0.030,
      color: const Color(0xFF2D6BFF),
      scale: 1 + 0.08 * math.sin(2 * t),
    );

    _drawSparkle(
      canvas,
      center.translate(s * 0.24, -s * 0.14),
      size: s * 0.042,
      color: const Color(0xFFFFA300),
      scale: 1 + 0.10 * math.sin(3 * t + 1.2),
    );

    _drawSparkle(
      canvas,
      center.translate(-s * 0.28, s * 0.11),
      size: s * 0.035,
      color: const Color(0xFF2D6BFF),
      scale: 1 + 0.06 * math.sin(2 * t + 2.0),
    );
  }

  void _drawSparkle(
    Canvas canvas,
    Offset center, {
    required double size,
    required Color color,
    required double scale,
  }) {
    final half = size * 0.5 * scale;

    final path = Path()
      ..moveTo(center.dx, center.dy - half)
      ..lineTo(center.dx + half, center.dy)
      ..lineTo(center.dx, center.dy + half)
      ..lineTo(center.dx - half, center.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.95));
  }

  @override
  bool shouldRepaint(covariant _SmokePainter oldDelegate) => false;
}

class _HatPainter extends CustomPainter {
  final Animation<double> animation;

  _HatPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final baseCenter = Offset(size.width / 2, size.height / 2);
    final t = animation.value * 2 * math.pi;

    // Mũ chuyển động nhẹ, loop kín
    final floatY = math.sin(t) * s * 0.012;
    final tilt = math.sin(t + 0.8) * 0.028;

    canvas.save();
    canvas.translate(baseCenter.dx, baseCenter.dy + floatY);
    canvas.rotate(tilt);
    canvas.translate(-baseCenter.dx, -baseCenter.dy);

    _drawHat(canvas, baseCenter, s, t);

    canvas.restore();
  }

  void _drawHat(Canvas canvas, Offset center, double s, double t) {
    // ===== THÂN MŨ =====
    final bodyPath = Path()
      ..moveTo(center.dx - s * 0.095, center.dy + s * 0.055)
      ..quadraticBezierTo(
        center.dx,
        center.dy + s * 0.030,
        center.dx + s * 0.095,
        center.dy + s * 0.050,
      )
      ..lineTo(center.dx + s * 0.110, center.dy + s * 0.170)
      ..quadraticBezierTo(
        center.dx + s * 0.085,
        center.dy + s * 0.245,
        center.dx,
        center.dy + s * 0.250,
      )
      ..quadraticBezierTo(
        center.dx - s * 0.085,
        center.dy + s * 0.245,
        center.dx - s * 0.110,
        center.dy + s * 0.170,
      )
      ..close();

    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E4FB3), Color(0xFF0B2C79)],
        ).createShader(bodyPath.getBounds()),
    );

    final bodyHighlight = Path()
      ..moveTo(center.dx - s * 0.068, center.dy + s * 0.078)
      ..quadraticBezierTo(
        center.dx - s * 0.035,
        center.dy + s * 0.130,
        center.dx - s * 0.040,
        center.dy + s * 0.195,
      )
      ..quadraticBezierTo(
        center.dx - s * 0.082,
        center.dy + s * 0.160,
        center.dx - s * 0.068,
        center.dy + s * 0.078,
      )
      ..close();

    canvas.drawPath(
      bodyHighlight,
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );

    // ===== MẶT DƯỚI MÁI =====
    final underPlane = Path()
      ..moveTo(center.dx - s * 0.110, center.dy + s * 0.028)
      ..lineTo(center.dx + s * 0.018, center.dy + s * 0.092)
      ..lineTo(center.dx + s * 0.138, center.dy + s * 0.045)
      ..lineTo(center.dx + s * 0.005, center.dy - s * 0.002)
      ..close();

    canvas.drawPath(
      underPlane,
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );

    // ===== MÁI MŨ =====
    final left = Offset(center.dx - s * 0.280, center.dy - s * 0.005);
    final top = Offset(center.dx - s * 0.005, center.dy - s * 0.110);
    final right = Offset(center.dx + s * 0.295, center.dy + s * 0.006);
    final bottom = Offset(center.dx + s * 0.022, center.dy + s * 0.092);

    final roofPath = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..close();

    canvas.drawPath(
      roofPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F79FF), Color(0xFF173FA8)],
        ).createShader(roofPath.getBounds()),
    );

    final lipPath = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(bottom.dx, bottom.dy + s * 0.016)
      ..lineTo(left.dx + s * 0.018, left.dy + s * 0.013)
      ..close();

    canvas.drawPath(
      lipPath,
      Paint()..color = const Color(0xFF173D97).withValues(alpha: 0.90),
    );

    // ===== NÚT GIỮ DÂY =====
    final button = Offset(center.dx - s * 0.004, center.dy - s * 0.003);
    canvas.drawCircle(
      button,
      s * 0.0105,
      Paint()..color = const Color(0xFFD1A33D),
    );

    // ===== DÂY TUA =====
    final tasselSwing = math.sin(2 * t) * s * 0.010;
    final tasselEnd = Offset(
      center.dx - s * 0.175 + tasselSwing,
      center.dy + s * 0.128,
    );

    final tasselPath = Path()
      ..moveTo(button.dx, button.dy)
      ..quadraticBezierTo(
        center.dx - s * 0.130,
        center.dy + s * 0.020,
        tasselEnd.dx,
        tasselEnd.dy,
      );

    canvas.drawPath(
      tasselPath,
      Paint()
        ..color = const Color(0xFFD9A31B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.0075
        ..strokeCap = StrokeCap.round,
    );

    final tasselHead = Path()
      ..moveTo(tasselEnd.dx, tasselEnd.dy)
      ..lineTo(tasselEnd.dx - s * 0.013, tasselEnd.dy + s * 0.038)
      ..lineTo(tasselEnd.dx + s * 0.013, tasselEnd.dy + s * 0.038)
      ..close();

    canvas.drawPath(
      tasselHead,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFB100), Color(0xFFFF7900)],
        ).createShader(tasselHead.getBounds()),
    );
  }

  @override
  bool shouldRepaint(covariant _HatPainter oldDelegate) => false;
}
