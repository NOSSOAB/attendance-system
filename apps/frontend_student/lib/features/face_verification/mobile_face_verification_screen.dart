import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/api/face_auth_api_service.dart';
import '../../core/face/mobile_face_ml.dart';
import 'mobile_face_scan_overlay.dart';
import 'mobile_face_verification_view.dart';

class MobileFaceVerificationResult {
  final String mobileFaceSessionId;
  final double similarity;

  const MobileFaceVerificationResult({
    required this.mobileFaceSessionId,
    required this.similarity,
  });
}

/// Continuous local recognition. Captured frames stay on the handset; only
/// the resulting vector and Android Keystore proof are submitted to the API.
class MobileFaceVerificationScreen extends StatefulWidget {
  final String accessToken;
  final int attendanceSessionId;
  final String courseCode;

  const MobileFaceVerificationScreen({
    super.key,
    required this.accessToken,
    required this.attendanceSessionId,
    required this.courseCode,
  });

  @override
  State<MobileFaceVerificationScreen> createState() =>
      _MobileFaceVerificationScreenState();
}

class _MobileFaceVerificationScreenState
    extends State<MobileFaceVerificationScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final FaceAuthApiService _service;
  late final AnimationController _entry;
  late final Animation<double> _entryOpacity;
  CameraController? _camera;
  MobileFaceSessionTicket? _pendingTicket;
  MobileFaceVerificationResult? _completedResult;
  String _message = 'Đưa khuôn mặt vào khung';
  String? _feedback;
  bool _working = true;
  bool _showProgress = true;
  bool _closed = false;
  bool _failed = false;
  bool _suspended = false;
  bool _submittingProof = false;
  int _setupGeneration = 0;
  Future<void> _cameraDisposal = Future<void>.value();
  Future<void>? _activePreparation;
  int _stableFaceFrames = 0;
  int _unusableFaceFrames = 0;
  bool _baselineReady = false;
  bool _faceAligned = false;
  bool _actionDetected = false;
  bool _verificationComplete = false;
  int _challengeIndex = 0;
  bool _turnLeft = true;
  int _neutralFrames = 0;
  int _actionFrames = 0;
  int _livenessFrameCount = 0;
  int _consecutiveFrameErrors = 0;
  DateTime? _livenessStartedAt;
  double _blinkPeak = 0;
  double _smilePeak = 0;
  double _turnPeak = 0;
  double _neutralBlinkMax = 0;
  double _neutralSmileMax = 0;
  double _neutralTurnMax = 0;
  Float32List? _openEyeEmbedding;
  DateTime _lastAnalyzedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMessageChangedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _entryOpacity = _entry.drive(CurveTween(curve: Curves.easeOut));
    _service = FaceAuthApiService(accessToken: widget.accessToken);
    unawaited(_prepareVerification());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed || !mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_suspended) return;
      _suspended = true;
      _setupGeneration++;
      final camera = _camera;
      _camera = null;
      _pendingTicket = null;
      _submittingProof = false;
      _cameraDisposal = _disposeCameraSafely(camera);
      setState(() {
        _working = true;
        _showProgress = true;
        _message = 'Camera tạm dừng';
      });
    } else if (state == AppLifecycleState.resumed && _suspended) {
      _suspended = false;
      if (_completedResult != null) {
        Navigator.of(context).pop(_completedResult);
        return;
      }
      unawaited(_prepareVerification());
    }
  }

  bool _canContinue(int generation) =>
      mounted && !_closed && !_suspended && generation == _setupGeneration;

  Future<void> _prepareVerification() async {
    final generation = ++_setupGeneration;
    final previous = _activePreparation;
    if (previous != null) await previous;
    if (!_canContinue(generation)) return;
    final pending = _openCameraAndTicket(generation);
    _activePreparation = pending;
    try {
      await pending;
    } finally {
      if (identical(_activePreparation, pending)) _activePreparation = null;
    }
  }

  Future<void> _openCameraAndTicket(int generation) async {
    CameraController? openingCamera;
    try {
      setState(() {
        _working = true;
        _showProgress = true;
        _failed = false;
        _message = 'Đưa khuôn mặt vào khung';
      });
      await _cameraDisposal;
      if (!_canContinue(generation)) return;
      await MobileFaceMl.initialize();
      if (!_canContinue(generation)) return;
      final cameras = await availableCameras();
      if (!_canContinue(generation)) return;
      final frontCameras = cameras.where(
        (item) => item.lensDirection == CameraLensDirection.front,
      );
      if (frontCameras.isEmpty) {
        throw const FaceAuthApiException('Không tìm thấy camera trước');
      }
      openingCamera = CameraController(
        frontCameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await openingCamera.initialize();
      if (!_canContinue(generation)) return;
      _camera = openingCamera;
      openingCamera = null;
      setState(() => _message = 'Đưa khuôn mặt vào khung');
      final ticket = await _service.startMobileAttendanceSession(
        attendanceSessionId: widget.attendanceSessionId,
      );
      if (!_canContinue(generation)) return;
      _pendingTicket = ticket;
      _turnLeft = _turnLeftForNonce(ticket.nonce);
      _submittingProof = false;
      _stableFaceFrames = 0;
      _unusableFaceFrames = 0;
      _consecutiveFrameErrors = 0;
      _lastAnalyzedAt = DateTime.fromMillisecondsSinceEpoch(0);
      _resetLivenessState();
      setState(() {
        _working = false;
        _showProgress = false;
        _message = 'Đưa khuôn mặt vào khung';
      });
      await _startAutomaticVerification();
    } catch (error) {
      if (_canContinue(generation)) _fail(_messageFor(error));
    } finally {
      if (openingCamera != null) {
        await _disposeCameraSafely(openingCamera);
      }
    }
  }

  Future<void> _startAutomaticVerification() async {
    final camera = _camera;
    if (camera == null || camera.value.isStreamingImages) return;
    await camera.startImageStream((image) {
      if (_closed || _suspended || _working || _failed) return;
      final now = DateTime.now();
      const interval = Duration(milliseconds: 150);
      if (now.difference(_lastAnalyzedAt) < interval) {
        return;
      }
      _lastAnalyzedAt = now;
      unawaited(_verify(image));
    });
  }

  Future<void> _verify(CameraImage image) async {
    final camera = _camera;
    if (_working || camera == null || !camera.value.isInitialized) return;
    _working = true;
    var completing = false;
    try {
      final ticket = _pendingTicket;
      if (ticket == null) {
        throw const FaceAuthApiException('Phiên xác minh không còn hợp lệ');
      }
      if (ticket.expiresAt.difference(DateTime.now().toUtc()) <
          const Duration(seconds: 18)) {
        completing = true;
        await _refreshTicket(camera);
        return;
      }
      final analysis = await MobileFaceMl.analyzeCameraImage(
        image,
        rotationDegrees: camera.description.sensorOrientation,
        // Landmark/blendshape checks are cheap. Run SFace only when taking
        // the final neutral sample that will be compared with enrollment.
        includeEmbedding:
            _baselineReady &&
            _actionDetected &&
            _challengeIndex == ticket.livenessActions.length - 1 &&
            _neutralFrames >= 1,
      );
      if (!mounted || _closed || _suspended || !identical(_camera, camera)) {
        return;
      }
      _consecutiveFrameErrors = 0;
      final doingTurn = _baselineReady && _currentAction() == 'turn';
      if (!analysis.ready ||
          (!doingTurn && !analysis.faceCentered) ||
          (analysis.faceSizeRatio ?? 0) < (doingTurn ? .07 : .10)) {
        _unusableFaceFrames++;
        final resetChallenge =
            analysis.faceCount > 1 || _unusableFaceFrames >= 6;
        final hadProgress =
            _stableFaceFrames > 0 || _baselineReady || _challengeIndex > 0;
        final wasAligned = _faceAligned;
        if (wasAligned && _unusableFaceFrames >= 3) {
          setState(() => _faceAligned = false);
        }
        if (resetChallenge) {
          _stableFaceFrames = 0;
          _resetLivenessState();
        }
        if (_unusableFaceFrames >= 3 || analysis.faceCount > 1) {
          _setFeedback(
            analysis.faceCount > 1
                ? 'Chỉ để một khuôn mặt trong khung'
                : !analysis.faceCentered && analysis.faceCount == 1
                ? 'Đưa khuôn mặt vào giữa khung'
                : analysis.faceCount == 1
                ? 'Đưa máy lại gần hơn một chút'
                : 'Đưa khuôn mặt vào giữa khung',
          );
        }
        if (resetChallenge && hadProgress) {
          _showIdleMessage('Đưa khuôn mặt vào khung', forceRebuild: true);
        } else {
          _working = false;
        }
        return;
      }
      _unusableFaceFrames = 0;
      if (_feedback != null) _setFeedback(null);
      _stableFaceFrames++;
      if (_stableFaceFrames < 2) {
        _showIdleMessage('Đưa khuôn mặt vào khung');
        return;
      }
      if (!_faceAligned) setState(() => _faceAligned = true);
      final blink = analysis.blinkScore ?? 0;
      final smile = analysis.smileScore ?? 0;
      final turn = analysis.turnScore ?? 0;
      _livenessStartedAt ??= DateTime.now();
      _livenessFrameCount++;
      if (_livenessFrameCount > 240 ||
          DateTime.now().difference(_livenessStartedAt!) >
              const Duration(seconds: 65)) {
        completing = true;
        await _refreshTicket(camera);
        return;
      }
      if (!_baselineReady) {
        if (!_isNeutral(blink, smile, turn)) {
          _neutralFrames = 0;
          _showIdleMessage('Nhìn thẳng vào camera');
          return;
        }
        _neutralFrames++;
        _recordNeutral(blink, smile, turn, analysis.embedding);
        if (_neutralFrames < 2) {
          _showIdleMessage('Giữ yên khuôn mặt');
          return;
        }
        _baselineReady = true;
        _neutralFrames = 0;
        _showIdleMessage(
          _actionInstruction(_currentAction()),
          forceRebuild: true,
        );
        return;
      }

      final currentAction = _currentAction();
      if (!_actionDetected) {
        _blinkPeak = blink > _blinkPeak ? blink : _blinkPeak;
        _smilePeak = smile > _smilePeak ? smile : _smilePeak;
        _turnPeak = turn > _turnPeak ? turn : _turnPeak;
        final detected = switch (currentAction) {
          'blink' => blink >= .35,
          'smile' => smile >= .30 && blink <= .45,
          'turn' =>
            turn >= .18 &&
                blink <= .45 &&
                _turnsRequestedDirection(analysis.signedTurnScore),
          _ => false,
        };
        _actionFrames = detected ? _actionFrames + 1 : 0;
        final requiredFrames = currentAction == 'blink' ? 1 : 2;
        if (_actionFrames >= requiredFrames) {
          _actionDetected = true;
          _actionFrames = 0;
          _neutralFrames = 0;
        }
        _showIdleMessage(
          _actionDetected
              ? _returnToNeutralInstruction(currentAction)
              : _actionInstruction(currentAction),
          forceRebuild: _actionDetected,
        );
        return;
      }

      if (!_isNeutral(blink, smile, turn)) {
        _neutralFrames = 0;
        _showIdleMessage(_returnToNeutralInstruction(currentAction));
        return;
      }
      _neutralFrames++;
      _recordNeutral(blink, smile, turn, analysis.embedding);
      if (_neutralFrames < 2) {
        _showIdleMessage('Nhìn thẳng vào camera');
        return;
      }
      _challengeIndex++;
      _actionDetected = false;
      _actionFrames = 0;
      _neutralFrames = 0;
      final ticketForChallenge = _pendingTicket;
      if (ticketForChallenge == null) {
        throw const FaceAuthApiException('Phiên xác minh không còn hợp lệ');
      }
      if (_challengeIndex < ticketForChallenge.livenessActions.length) {
        _showIdleMessage(
          _actionInstruction(_currentAction()),
          forceRebuild: true,
        );
        return;
      }
      var finalTicket = _pendingTicket;
      if (finalTicket == null ||
          finalTicket.expiresAt.difference(DateTime.now().toUtc()) <
              const Duration(seconds: 15)) {
        completing = true;
        await _refreshTicket(camera);
        return;
      }
      finalTicket = _pendingTicket!;
      completing = true;
      _pendingTicket = null;
      _submittingProof = true;
      final verificationEmbedding = _openEyeEmbedding;
      if (verificationEmbedding == null) {
        throw const FaceAuthApiException(
          'Chưa lấy được ảnh khuôn mặt rõ. Hãy thử lại',
        );
      }
      final livenessProof = MobileLivenessProof(
        actions: List<String>.from(finalTicket.livenessActions),
        completedAt: DateTime.now().toUtc().toIso8601String(),
        frameCount: _livenessFrameCount,
        blinkPeak: _blinkPeak,
        smilePeak: _smilePeak,
        turnPeak: _turnPeak,
        neutralBlinkMax: _neutralBlinkMax,
        neutralSmileMax: _neutralSmileMax,
        neutralTurnMax: _neutralTurnMax,
      );
      final proof = await MobileFaceMl.signFaceRequest(
        sessionId: finalTicket.sessionId,
        nonce: finalTicket.nonce,
        modelId: finalTicket.modelId,
        embedding: verificationEmbedding,
        livenessProof: livenessProof,
      );
      if (mounted) {
        setState(() {
          _showProgress = true;
          _message = 'Giữ yên khuôn mặt';
        });
      }
      final result = await _service.completeMobileAttendanceSession(
        ticket: finalTicket,
        embedding: proof.embedding,
        publicKey: proof.publicKey,
        signature: proof.signature,
        livenessProof: livenessProof,
      );
      if (!result.verified) {
        throw const FaceAuthApiException('Khuôn mặt không khớp với tài khoản');
      }
      if (mounted && !_closed && !_suspended && identical(_camera, camera)) {
        _completedResult = MobileFaceVerificationResult(
          mobileFaceSessionId: finalTicket.sessionId,
          similarity: result.similarity,
        );
        setState(() {
          _verificationComplete = true;
          _submittingProof = false;
          _showProgress = false;
          _message = 'Xác thực thành công';
        });
        await Future<void>.delayed(const Duration(milliseconds: 950));
        if (mounted && !_closed && !_suspended && _completedResult != null) {
          Navigator.of(context).pop(_completedResult);
        }
      }
    } catch (error) {
      if (!mounted || _closed || _suspended || !identical(_camera, camera)) {
        return;
      }
      if (completing) {
        _fail(_messageFor(error));
        return;
      }
      _consecutiveFrameErrors++;
      if (_consecutiveFrameErrors >= 3) {
        _fail(_messageFor(error));
      } else {
        _showIdleMessage('Đang điều chỉnh camera, giữ khuôn mặt trong khung');
      }
    }
  }

  Future<void> _disposeCameraSafely(CameraController? camera) async {
    if (camera == null) return;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } catch (_) {
      // CameraX may already have stopped the stream.
    }
    try {
      await camera.dispose();
    } catch (_) {
      // CameraX may already be releasing its preview surface.
    }
  }

  Future<void> _refreshTicket(CameraController camera) async {
    if (!mounted || _closed || _suspended || !identical(_camera, camera)) {
      return;
    }
    setState(() {
      _working = true;
      _showProgress = true;
      _message = 'Đưa khuôn mặt vào khung';
    });
    final ticket = await _service.startMobileAttendanceSession(
      attendanceSessionId: widget.attendanceSessionId,
    );
    if (!mounted || _closed || _suspended || !identical(_camera, camera)) {
      return;
    }
    _pendingTicket = ticket;
    _turnLeft = _turnLeftForNonce(ticket.nonce);
    _submittingProof = false;
    _stableFaceFrames = 0;
    _unusableFaceFrames = 0;
    _resetLivenessState();
    _showIdleMessage('Đưa khuôn mặt vào khung');
  }

  void _setFeedback(String? feedback) {
    if (!mounted || _closed || _suspended || _feedback == feedback) return;
    setState(() => _feedback = feedback);
  }

  void _showIdleMessage(String message, {bool forceRebuild = false}) {
    if (!mounted || _closed || _suspended) return;
    final now = DateTime.now();
    if (!forceRebuild &&
        !_showProgress &&
        _message != message &&
        now.difference(_lastMessageChangedAt) <
            const Duration(milliseconds: 450)) {
      _working = false;
      return;
    }
    final needsRebuild = forceRebuild || _message != message || _showProgress;
    _working = false;
    _showProgress = false;
    if (needsRebuild) {
      _lastMessageChangedAt = now;
      setState(() => _message = message);
    }
  }

  void _fail(String message) {
    if (!mounted || _closed || _suspended) return;
    setState(() {
      _working = false;
      _showProgress = false;
      _failed = true;
      _verificationComplete = false;
      _message = message;
    });
  }

  Future<void> _retry() async {
    if (_working || _closed) return;
    _setupGeneration++;
    setState(() {
      _working = true;
      _showProgress = true;
      _failed = false;
      _verificationComplete = false;
      _completedResult = null;
      _message = 'Đang khởi động lại camera';
    });
    final camera = _camera;
    _camera = null;
    _cameraDisposal = _disposeCameraSafely(camera);
    await _cameraDisposal;
    if (!mounted || _closed || _suspended) return;
    _pendingTicket = null;
    _submittingProof = false;
    _stableFaceFrames = 0;
    _unusableFaceFrames = 0;
    _consecutiveFrameErrors = 0;
    _lastAnalyzedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _resetLivenessState();
    await _prepareVerification();
  }

  void _resetLivenessState() {
    _baselineReady = false;
    _faceAligned = false;
    _actionDetected = false;
    _challengeIndex = 0;
    _feedback = null;
    _neutralFrames = 0;
    _actionFrames = 0;
    _livenessFrameCount = 0;
    _livenessStartedAt = null;
    _blinkPeak = 0;
    _smilePeak = 0;
    _turnPeak = 0;
    _neutralBlinkMax = 0;
    _neutralSmileMax = 0;
    _neutralTurnMax = 0;
    _openEyeEmbedding = null;
  }

  bool _isNeutral(double blink, double smile, double turn) =>
      blink <= .25 && smile <= .25 && turn <= .14;

  void _recordNeutral(
    double blink,
    double smile,
    double turn,
    Float32List? embedding,
  ) {
    _neutralBlinkMax = blink > _neutralBlinkMax ? blink : _neutralBlinkMax;
    _neutralSmileMax = smile > _neutralSmileMax ? smile : _neutralSmileMax;
    _neutralTurnMax = turn > _neutralTurnMax ? turn : _neutralTurnMax;
    if (embedding != null) _openEyeEmbedding = embedding;
  }

  bool _turnLeftForNonce(String nonce) =>
      nonce.codeUnits.fold<int>(0, (sum, code) => sum + code).isEven;

  bool _turnsRequestedDirection(double? signedTurn) =>
      signedTurn != null &&
      (_turnLeft ? signedTurn >= .18 : signedTurn <= -.18);

  String _currentAction() {
    final actions = _pendingTicket?.livenessActions ?? const <String>[];
    return _challengeIndex < actions.length ? actions[_challengeIndex] : '';
  }

  String _actionInstruction(String action) => switch (action) {
    'smile' => 'Mỉm cười nhẹ',
    'turn' => 'Quay nhẹ sang ${_turnLeft ? 'trái' : 'phải'}',
    _ => 'Nhắm mắt nhẹ',
  };

  String _returnToNeutralInstruction(String action) =>
      action == 'blink' ? 'Mở mắt và nhìn thẳng' : 'Nhìn thẳng vào camera';

  String get _guidanceHint {
    if (_verificationComplete) return 'Đang chuyển tiếp...';
    if (_failed) return 'Giữ điện thoại ổn định rồi thử lại';
    if (_submittingProof) return 'Đang xác thực an toàn';
    if (_showProgress) {
      return 'Canh khuôn mặt theo hướng dẫn';
    }
    if (_feedback != null) return _feedback!;
    if (_actionDetected ||
        _message == 'Nhìn thẳng vào camera' ||
        _message == 'Mở mắt và nhìn thẳng') {
      return 'Giữ khuôn mặt ổn định trong giây lát';
    }
    if (!_baselineReady) {
      return _faceAligned
          ? 'Giữ khuôn mặt ổn định trong giây lát'
          : 'Canh khuôn mặt theo hướng dẫn';
    }
    return switch (_currentAction()) {
      'blink' => 'Giữ điện thoại yên và nhắm cả hai mắt',
      'smile' => 'Giữ khuôn mặt trong khung',
      'turn' => 'Di chuyển đầu theo khuôn mặt hướng dẫn',
      _ => 'Canh khuôn mặt theo hướng dẫn',
    };
  }

  FaceGuidePhase get _guidePhase {
    if (_verificationComplete) return FaceGuidePhase.success;
    if (_failed) return FaceGuidePhase.error;
    if (_submittingProof) return FaceGuidePhase.forward;
    if (!_baselineReady) {
      return _faceAligned ? FaceGuidePhase.hold : FaceGuidePhase.align;
    }
    if (_actionDetected) return FaceGuidePhase.forward;
    return switch (_currentAction()) {
      'blink' => FaceGuidePhase.blink,
      'smile' => FaceGuidePhase.smile,
      'turn' => _turnLeft ? FaceGuidePhase.turnLeft : FaceGuidePhase.turnRight,
      _ => FaceGuidePhase.align,
    };
  }

  String _messageFor(Object error) =>
      _friendlyMessage(error.toString().replaceFirst('Exception: ', ''));

  String _friendlyMessage(String raw) {
    final normalized = raw.toLowerCase();
    if (normalized.contains('embeddings must be a number') ||
        normalized.contains('each value in embeddings')) {
      return 'Máy chủ chưa nhận được mẫu khuôn mặt. Hãy thử lại';
    }
    if (normalized.contains('livenessproof') ||
        normalized.contains('phiên bản ứng dụng đã cũ')) {
      return 'Ứng dụng đã cũ. Hãy cài APK mới nhất để xác minh khuôn mặt';
    }
    if (normalized.contains('khuôn mặt mobile chưa được đăng ký') ||
        normalized.contains('chưa có mẫu khuôn mặt')) {
      return 'Tài khoản chưa có dữ liệu khuôn mặt. Hãy liên hệ quản trị viên';
    }
    if (normalized.contains('illegalstateexception') ||
        normalized.contains('surfaceproducer') ||
        normalized.contains('surfacetexture')) {
      return 'Camera đang khởi động lại. Hãy thử lại sau vài giây';
    }
    if (normalized.contains('cameraaccessdenied') ||
        normalized.contains('permission denied')) {
      return 'Hãy cấp quyền camera cho ứng dụng rồi thử lại';
    }
    if (normalized.contains('libmediapipe_tasks_vision_jni.so') ||
        normalized.contains('libonnxruntime.so') ||
        normalized.contains('unsatisfiedlinkerror')) {
      return 'Thiết bị này chưa hỗ trợ nhận diện khuôn mặt. Hãy dùng điện thoại Android 64-bit';
    }
    if (normalized.contains('cameraexception') ||
        normalized.contains('face_ml_error') ||
        normalized.contains('face_vector_invalid')) {
      return 'Camera chưa phân tích được khuôn mặt. Hãy thử lại';
    }
    if (normalized.contains('timeoutexception') ||
        normalized.contains('socketexception')) {
      return 'Kết nối máy chủ quá chậm. Hãy kiểm tra mạng rồi thử lại';
    }
    if (normalized.contains('không khớp') || normalized.contains('not match')) {
      return 'Khuôn mặt chưa khớp với hồ sơ. Hãy thử lại ở nơi đủ sáng';
    }
    if (normalized.contains('phiên điểm danh') ||
        normalized.contains('attendance session')) {
      return 'Phiên điểm danh không còn mở. Hãy quay lại trang chủ';
    }
    // Never render raw server or platform exceptions in the camera UI.
    return 'Không thể hoàn tất xác minh. Hãy thử lại';
  }

  Future<void> _cancel() async {
    _closed = true;
    _setupGeneration++;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    _setupGeneration++;
    unawaited(_disposeCameraSafely(_camera));
    _entry.dispose();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final cameraReady = camera?.value.isInitialized == true;
    return FadeTransition(
      opacity: _entryOpacity,
      child: MobileFaceVerificationView(
        courseCode: widget.courseCode,
        instruction: _message,
        detail: _guidanceHint,
        cameraPreview: cameraReady ? _buildFittedCameraPreview(camera!) : null,
        faceAligned: _faceAligned,
        guidePhase: _guidePhase,
        showRetry: _failed && !_working,
        onClose: _cancel,
        onRetry: _retry,
      ),
    );
  }

  Widget _buildFittedCameraPreview(CameraController camera) {
    final previewSize = camera.value.previewSize;
    if (previewSize == null) return CameraPreview(camera);
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: portrait ? previewSize.height : previewSize.width,
        height: portrait ? previewSize.width : previewSize.height,
        child: CameraPreview(camera),
      ),
    );
  }
}
