import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/api/face_auth_api_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  final String schoolCode;
  final String mssv;
  final String accessToken;
  final int attendanceSessionId;
  final String courseCode;

  const FaceVerificationScreen({
    super.key,
    required this.schoolCode,
    required this.mssv,
    required this.accessToken,
    required this.attendanceSessionId,
    required this.courseCode,
  });

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  static const Duration _verificationTimeout = Duration(seconds: 70);
  static const double _minimumComfortableFaceSize = 0.25;
  static const double _maximumComfortableFaceSize = 0.68;

  late final FaceAuthApiService _api;

  CameraController? _camera;
  FaceSessionTicket? _ticket;
  FaceVerificationResult? _result;
  DateTime? _verificationStartedAt;
  String _instruction = 'Đang chuẩn bị camera';
  String? _error;
  bool _cancelled = false;
  bool _captureRunning = false;
  bool _retrying = false;
  bool _returningResult = false;
  int _networkFailures = 0;

  bool get _isTerminal => _result?.isTerminal ?? false;
  bool get _isSuccess => _result?.isSuccess ?? false;
  bool get _canRetry =>
      !_captureRunning &&
      !_retrying &&
      (_error != null || (_result?.stage == 'FAILED'));

  @override
  void initState() {
    super.initState();
    _api = FaceAuthApiService(accessToken: widget.accessToken);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const FaceAuthApiException(
          'Thiết bị không tìm thấy camera trước',
        );
      }

      final selectedCamera = cameras.cast<CameraDescription?>().firstWhere(
        (camera) => camera?.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      )!;
      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted || _cancelled) {
        await controller.dispose();
        return;
      }

      setState(() {
        _camera = controller;
        _instruction = 'Đang kết nối dịch vụ xác minh';
      });
      await _startNewSession();
    } on CameraException catch (error) {
      _showFatalError(
        error.code == 'CameraAccessDenied'
            ? 'Hãy cấp quyền camera để tiếp tục điểm danh'
            : 'Không mở được camera. Vui lòng thử lại.',
      );
    } catch (error) {
      _showFatalError(_friendlyError(error));
    }
  }

  Future<void> _startNewSession() async {
    try {
      final ticket = await _api.startAttendanceSession(
        schoolCode: widget.schoolCode,
        mssv: widget.mssv,
        attendanceSessionId: widget.attendanceSessionId,
      );
      if (!mounted || _cancelled) {
        await _api.deleteSession(ticket);
        return;
      }

      setState(() {
        _ticket = ticket;
        _result = null;
        _error = null;
        _networkFailures = 0;
        _verificationStartedAt = DateTime.now();
        _instruction = 'Nhìn thẳng vào camera';
      });
      unawaited(_runVerification());
    } catch (error) {
      _showFatalError(_friendlyError(error));
    }
  }

  Future<void> _runVerification() async {
    if (_captureRunning) {
      return;
    }
    _captureRunning = true;
    if (mounted) {
      setState(() {});
    }

    try {
      while (mounted && !_cancelled && !_isTerminal) {
        final ticket = _ticket;
        final camera = _camera;
        if (ticket == null || camera == null || !camera.value.isInitialized) {
          break;
        }

        final startedAt = _verificationStartedAt;
        if (startedAt != null &&
            DateTime.now().difference(startedAt) > _verificationTimeout) {
          _showFatalError(
            'Phiên xác minh đã quá thời gian. Hãy giữ điện thoại ổn định và thử lại.',
          );
          break;
        }

        try {
          final FaceVerificationResult nextResult;
          if (_result?.stage == 'VERIFYING') {
            await Future<void>.delayed(const Duration(milliseconds: 650));
            nextResult = await _api.getStatus(ticket);
          } else {
            final photo = await camera.takePicture();
            nextResult = await _api.sendFrame(
              ticket: ticket,
              jpegBytes: await photo.readAsBytes(),
            );
            await Future<void>.delayed(const Duration(milliseconds: 280));
          }

          _networkFailures = 0;
          if (!mounted || _cancelled) {
            return;
          }

          setState(() {
            _result = nextResult;
            _instruction = _localizedInstruction(nextResult);
            _error = nextResult.stage == 'FAILED'
                ? _failureMessage(nextResult)
                : null;
          });

          if (nextResult.isSuccess) {
            unawaited(_returnSuccessAfterDelay(nextResult));
          }
        } on FaceAuthApiException catch (error) {
          if (error.statusCode == 429) {
            await Future<void>.delayed(const Duration(milliseconds: 900));
            continue;
          }

          _networkFailures += 1;
          if (!mounted || _cancelled) {
            return;
          }
          setState(() {
            _error = _networkFailures >= 3
                ? 'Kết nối không ổn định. Vui lòng thử lại.'
                : 'Đang kết nối lại...';
          });
          if (_networkFailures >= 3) {
            break;
          }
          await Future<void>.delayed(Duration(seconds: _networkFailures));
        }
      }
    } on CameraException {
      _showFatalError('Camera gặp sự cố. Vui lòng thử lại.');
    } catch (error) {
      _showFatalError(_friendlyError(error));
    } finally {
      _captureRunning = false;
      if (mounted && !_cancelled) {
        setState(() {});
      }
    }
  }

  Future<void> _returnSuccessAfterDelay(FaceVerificationResult result) async {
    if (_returningResult) {
      return;
    }
    _returningResult = true;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || _cancelled || _result != result) {
      _returningResult = false;
      return;
    }
    Navigator.of(context).pop(result);
  }

  Future<void> _retry() async {
    if (!_canRetry) {
      return;
    }
    setState(() {
      _retrying = true;
      _error = null;
      _result = null;
      _instruction = 'Đang tạo phiên xác minh mới';
    });

    final oldTicket = _ticket;
    _ticket = null;
    if (oldTicket != null) {
      await _api.deleteSession(oldTicket);
    }

    if (!mounted || _cancelled) {
      return;
    }
    setState(() {
      _retrying = false;
    });
    await _startNewSession();
  }

  String _localizedInstruction(FaceVerificationResult result) {
    if (result.stage == 'SUCCESS') {
      return 'Xác minh thành công';
    }
    if (result.stage == 'FAILED') {
      return 'Chưa xác minh được';
    }
    if (result.stage == 'VERIFYING') {
      return 'Đang đối chiếu khuôn mặt';
    }

    if (result.faceCount == 0) {
      return 'Đưa khuôn mặt vào giữa khung';
    }
    if (result.faceCount > 1) {
      return 'Chỉ để một khuôn mặt trong khung';
    }
    if (result.currentActionId.isNotEmpty && result.actionBaselineReady) {
      return _instructionForAction(result.currentActionId);
    }
    if (!result.brightnessOk) {
      return 'Di chuyển đến nơi đủ sáng';
    }
    final faceSize = result.faceSizeRatio;
    if (faceSize != null && faceSize < _minimumComfortableFaceSize) {
      return 'Đưa điện thoại lại gần hơn';
    }
    if (faceSize != null && faceSize > _maximumComfortableFaceSize) {
      return 'Đưa điện thoại ra xa hơn';
    }
    if (!result.faceCentered) {
      return 'Đưa khuôn mặt vào giữa khung';
    }
    return 'Vui lòng nhìn thẳng';
  }

  String _instructionForAction(String actionId) {
    switch (actionId) {
      case 'turn_left':
        return 'Quay mặt sang trái';
      case 'turn_right':
        return 'Quay mặt sang phải';
      case 'smile':
        return 'Mỉm cười';
      case 'mouth_open':
        return 'Há miệng';
      case 'blink':
        return 'Chớp mắt một lần';
      case 'look_up':
        return 'Nhìn lên';
      case 'look_down':
        return 'Nhìn xuống';
      default:
        return 'Vui lòng nhìn thẳng';
    }
  }

  String _animationAction(FaceVerificationResult? result) {
    if (result == null) {
      return 'align';
    }
    if (result.stage == 'VERIFYING') {
      return 'verifying';
    }
    if (result.faceCount > 1) {
      return 'multiple';
    }
    if (result.faceCount == 0) {
      return 'align';
    }
    if (result.currentActionId.isNotEmpty && result.actionBaselineReady) {
      return result.currentActionId;
    }
    if (!result.faceCentered) {
      return 'align';
    }
    if (!result.brightnessOk) {
      return 'light';
    }
    final faceSize = result.faceSizeRatio;
    if (faceSize != null && faceSize < _minimumComfortableFaceSize) {
      return 'closer';
    }
    if (faceSize != null && faceSize > _maximumComfortableFaceSize) {
      return 'farther';
    }
    return 'straight';
  }

  bool _facePlacementIsReady(FaceVerificationResult? result) {
    if (result == null || result.faceCount != 1 || !result.faceCentered) {
      return false;
    }
    final faceSize = result.faceSizeRatio;
    return result.brightnessOk &&
        faceSize != null &&
        faceSize >= _minimumComfortableFaceSize &&
        faceSize <= _maximumComfortableFaceSize;
  }

  String _instructionHint() {
    final normalized = _instruction.toLowerCase();
    if (_isSuccess) {
      return 'Đang hoàn tất điểm danh';
    }
    if (_result?.stage == 'VERIFYING') {
      return 'Vui lòng chờ trong giây lát';
    }
    if (normalized.contains('một khuôn mặt')) {
      return 'Người khác cần ra khỏi vùng camera';
    }
    if (normalized.contains('lại gần') || normalized.contains('ra xa')) {
      return 'Di chuyển chậm để khuôn mặt vừa với khung';
    }
    if (normalized.contains('đủ sáng')) {
      return 'Tránh đứng ngược sáng';
    }
    if (normalized.contains('quay mặt')) {
      return 'Làm theo chuyển động minh họa';
    }
    if (normalized.contains('chớp mắt')) {
      return 'Làm theo chuyển động minh họa';
    }
    if (normalized.contains('há miệng') || normalized.contains('mỉm cười')) {
      return 'Làm theo chuyển động minh họa';
    }
    return 'Đặt khuôn mặt vào giữa khung';
  }

  String _failureMessage(FaceVerificationResult result) {
    switch (result.resultCode) {
      case 'LIVENESS_FAILED':
        return 'Chưa nhận được thao tác. Hãy nhìn thẳng, làm theo hướng dẫn và thử lại.';
      case 'IDENTITY_MISMATCH':
      case 'RECOGNITION_FAILED':
        return 'Khuôn mặt không khớp với tài khoản sinh viên.';
      case 'SERVER_BUSY':
        return 'Máy chủ đang bận. Vui lòng thử lại sau ít giây.';
      default:
        return 'Chưa thể xác minh khuôn mặt. Vui lòng thử lại ở nơi đủ sáng.';
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) {
      return 'Không thể tiếp tục xác minh. Vui lòng thử lại.';
    }
    return raw;
  }

  void _showFatalError(String message) {
    if (!mounted || _cancelled) {
      return;
    }
    setState(() {
      _error = message;
      _instruction = 'Xác minh bị gián đoạn';
    });
  }

  Future<void> _cancel() async {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    final ticket = _ticket;
    if (ticket != null && !_isSuccess) {
      await _api.deleteSession(ticket);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_camera?.dispose());
    _api.close();
    super.dispose();
  }

  Widget _buildCameraPreview(CameraController camera) {
    final previewSize = camera.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(camera);
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(camera),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final result = _result;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_cancel());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F7FB),
          surfaceTintColor: Colors.transparent,
          leadingWidth: 64,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: IconButton.filledTonal(
              onPressed: _cancel,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          titleSpacing: 12,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Xác minh khuôn mặt',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Điểm danh ${widget.courseCode}',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: ColoredBox(
                      color: const Color(0xFF101828),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (camera != null && camera.value.isInitialized)
                            _buildCameraPreview(camera)
                          else
                            const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x66000000),
                                  Colors.transparent,
                                  Colors.transparent,
                                  Color(0x55000000),
                                ],
                                stops: [0, 0.22, 0.72, 1],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xB307111F),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.shield_outlined,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'Giữ điện thoại ổn định',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final guideWidth = math.min(
                                constraints.maxWidth * 0.66,
                                270.0,
                              );
                              final guideHeight = math.min(
                                guideWidth * 1.28,
                                constraints.maxHeight * 0.66,
                              );
                              final guideColor = _isSuccess
                                  ? const Color(0xFF32D583)
                                  : _error != null
                                  ? const Color(0xFFF97066)
                                  : _facePlacementIsReady(result)
                                  ? const Color(0xFF84ADFF)
                                  : Colors.white;
                              return Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: guideWidth,
                                  height: guideHeight,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      guideWidth,
                                    ),
                                    border: Border.all(
                                      color: guideColor,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: guideColor.withValues(
                                          alpha: 0.20,
                                        ),
                                        blurRadius: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_isSuccess)
                            const ColoredBox(
                              color: Color(0x5532D583),
                              child: Center(
                                child: CircleAvatar(
                                  radius: 34,
                                  backgroundColor: Color(0xFF12B76A),
                                  child: Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 42,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _error == null
                          ? const Color(0xFFEAECF0)
                          : const Color(0xFFFECACA),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D101828),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _isSuccess
                              ? const Color(0xFFECFDF3)
                              : _error != null
                              ? const Color(0xFFFEF3F2)
                              : const Color(0xFFEFF4FF),
                          shape: BoxShape.circle,
                        ),
                        child: _isSuccess
                            ? const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF039855),
                                size: 30,
                              )
                            : _error != null
                            ? const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFD92D20),
                                size: 28,
                              )
                            : _FaceActionAnimation(
                                actionId: _animationAction(result),
                              ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Column(
                            key: ValueKey('$_instruction|$_error'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _instruction,
                                style: const TextStyle(
                                  color: Color(0xFF101828),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _error ?? _instructionHint(),
                                style: TextStyle(
                                  color: _error == null
                                      ? const Color(0xFF667085)
                                      : const Color(0xFFD92D20),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_canRetry) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _retry,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF155EEF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'Thử lại',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 15,
                      color: Color(0xFF98A2B3),
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Hình ảnh chỉ dùng để xác minh phiên điểm danh này',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaceActionAnimation extends StatefulWidget {
  final String actionId;

  const _FaceActionAnimation({required this.actionId});

  @override
  State<_FaceActionAnimation> createState() => _FaceActionAnimationState();
}

class _FaceActionAnimationState extends State<_FaceActionAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _FaceActionPainter(
            actionId: widget.actionId,
            progress: Curves.easeInOut.transform(_controller.value),
          ),
        );
      },
    );
  }
}

class _FaceActionPainter extends CustomPainter {
  final String actionId;
  final double progress;

  const _FaceActionPainter({required this.actionId, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = const Color(0xB8155EEF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = const Color(0x24155EEF)
      ..style = PaintingStyle.fill;

    if (actionId == 'verifying') {
      final rect = Rect.fromCircle(
        center: center,
        radius: size.shortestSide * .28,
      );
      canvas.drawArc(
        rect,
        progress * math.pi * 2,
        math.pi * 1.25,
        false,
        stroke..strokeWidth = 3,
      );
      canvas.drawCircle(center, size.shortestSide * .13, fill);
      canvas.drawCircle(
        center,
        size.shortestSide * .13,
        stroke..strokeWidth = 2,
      );
      return;
    }

    if (actionId == 'multiple') {
      _drawPerson(
        canvas,
        Offset(center.dx - 8, center.dy + 2),
        size.shortestSide * .72,
        stroke,
        fill,
        phase: 0,
      );
      final fadedStroke = Paint()
        ..color = const Color(0x73155EEF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7;
      final fadedFill = Paint()
        ..color = const Color(0x16155EEF)
        ..style = PaintingStyle.fill;
      _drawPerson(
        canvas,
        Offset(center.dx + 11, center.dy + 5),
        size.shortestSide * .58,
        fadedStroke,
        fadedFill,
        phase: 0,
      );
      return;
    }

    if (actionId == 'light') {
      final radius = size.shortestSide * (.12 + .025 * progress);
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, stroke);
      for (var index = 0; index < 8; index++) {
        final angle = index * math.pi / 4;
        final start = Offset(
          center.dx + math.cos(angle) * radius * 1.55,
          center.dy + math.sin(angle) * radius * 1.55,
        );
        final end = Offset(
          center.dx + math.cos(angle) * radius * 2.15,
          center.dy + math.sin(angle) * radius * 2.15,
        );
        canvas.drawLine(start, end, stroke);
      }
      return;
    }

    var scale = 1.0;
    if (actionId == 'closer') {
      scale = .72 + progress * .25;
    } else if (actionId == 'farther') {
      scale = 1.06 - progress * .24;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    _drawPerson(
      canvas,
      center,
      size.shortestSide * .78,
      stroke,
      fill,
      phase: progress,
      action: actionId,
    );
    canvas.restore();

    if (actionId == 'align' || actionId == 'straight') {
      final guide = Paint()
        ..color = const Color(0x66155EEF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final inset = 8.0 + progress * 2;
      final rect = Rect.fromLTWH(
        inset,
        inset,
        size.width - inset * 2,
        size.height - inset * 2,
      );
      canvas.drawArc(rect, math.pi, math.pi / 2, false, guide);
      canvas.drawArc(rect, -math.pi / 2, math.pi / 2, false, guide);
    }
  }

  void _drawPerson(
    Canvas canvas,
    Offset center,
    double extent,
    Paint stroke,
    Paint fill, {
    required double phase,
    String action = 'straight',
  }) {
    final direction = action == 'turn_left'
        ? -1.0
        : action == 'turn_right'
        ? 1.0
        : 0.0;
    final turnAmount = direction == 0 ? 0.0 : phase;
    final headCenter = Offset(
      center.dx + direction * extent * .035 * turnAmount,
      center.dy - extent * .08,
    );
    final headWidth = extent * (.38 - .09 * turnAmount);
    final headHeight = extent * .48;

    final shoulders = Path()
      ..moveTo(center.dx - extent * .28, center.dy + extent * .34)
      ..quadraticBezierTo(
        center.dx - extent * .20,
        center.dy + extent * .21,
        center.dx,
        center.dy + extent * .22,
      )
      ..quadraticBezierTo(
        center.dx + extent * .20,
        center.dy + extent * .21,
        center.dx + extent * .28,
        center.dy + extent * .34,
      );
    canvas.drawPath(shoulders, fill);
    canvas.drawPath(shoulders, stroke);

    final headRect = Rect.fromCenter(
      center: headCenter,
      width: headWidth,
      height: headHeight,
    );
    canvas.drawOval(headRect, fill);
    canvas.drawOval(headRect, stroke);

    final featureShift = direction * extent * .055 * turnAmount;
    final eyeY = headCenter.dy - extent * .045;
    final eyeSpread = headWidth * (.20 - .06 * turnAmount);
    canvas.drawLine(
      Offset(headCenter.dx - eyeSpread + featureShift, eyeY),
      Offset(headCenter.dx - eyeSpread + featureShift + 2.5, eyeY),
      stroke,
    );
    canvas.drawLine(
      Offset(headCenter.dx + eyeSpread + featureShift - 2.5, eyeY),
      Offset(headCenter.dx + eyeSpread + featureShift, eyeY),
      stroke,
    );

    final noseX = headCenter.dx + featureShift;
    canvas.drawLine(
      Offset(noseX, eyeY + 2),
      Offset(noseX + direction * extent * .025 * turnAmount, eyeY + 8),
      stroke,
    );

    final mouthCenter = Offset(
      headCenter.dx + featureShift,
      headCenter.dy + extent * .095,
    );
    if (action == 'mouth_open') {
      canvas.drawOval(
        Rect.fromCenter(
          center: mouthCenter,
          width: extent * .09,
          height: extent * (.025 + .08 * phase),
        ),
        stroke,
      );
    } else if (action == 'smile') {
      canvas.drawArc(
        Rect.fromCenter(
          center: mouthCenter.translate(0, -extent * .025),
          width: extent * (.10 + .04 * phase),
          height: extent * (.08 + .04 * phase),
        ),
        .18,
        math.pi - .36,
        false,
        stroke,
      );
    } else {
      canvas.drawLine(
        mouthCenter.translate(-extent * .045, 0),
        mouthCenter.translate(extent * .045, 0),
        stroke,
      );
    }

    if (direction != 0) {
      final arrowPaint = Paint()
        ..color = const Color(0x8A155EEF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      final y = headCenter.dy - headHeight * .64;
      final startX = center.dx - direction * extent * .08;
      final endX = center.dx + direction * extent * (.12 + .04 * phase);
      canvas.drawLine(Offset(startX, y), Offset(endX, y), arrowPaint);
      canvas.drawLine(
        Offset(endX, y),
        Offset(endX - direction * 4, y - 3),
        arrowPaint,
      );
      canvas.drawLine(
        Offset(endX, y),
        Offset(endX - direction * 4, y + 3),
        arrowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceActionPainter oldDelegate) {
    return oldDelegate.actionId != actionId || oldDelegate.progress != progress;
  }
}
