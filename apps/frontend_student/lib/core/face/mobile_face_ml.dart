import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class MobileFaceAnalysis {
  final int faceCount;
  final double? faceSizeRatio;
  final bool faceCentered;
  final double? blinkScore;
  final double? smileScore;
  final double? turnScore;
  final double? signedTurnScore;
  final Float32List? embedding;

  const MobileFaceAnalysis({
    required this.faceCount,
    required this.faceSizeRatio,
    required this.faceCentered,
    required this.blinkScore,
    required this.smileScore,
    required this.turnScore,
    required this.signedTurnScore,
    required this.embedding,
  });
  bool get ready => faceCount == 1;

  factory MobileFaceAnalysis.fromMap(Map<Object?, Object?> raw) {
    final values = raw['embedding'] as List<Object?>?;
    return MobileFaceAnalysis(
      faceCount: (raw['faceCount'] as num?)?.toInt() ?? 0,
      faceSizeRatio: (raw['faceSizeRatio'] as num?)?.toDouble(),
      faceCentered: raw['faceCentered'] == true,
      blinkScore: (raw['blinkScore'] as num?)?.toDouble(),
      smileScore: (raw['smileScore'] as num?)?.toDouble(),
      turnScore: (raw['turnScore'] as num?)?.toDouble(),
      signedTurnScore: (raw['signedTurnScore'] as num?)?.toDouble(),
      embedding: values == null
          ? null
          : Float32List.fromList(
              values.whereType<num>().map((value) => value.toDouble()).toList(),
            ),
    );
  }
}

class MobileLivenessProof {
  final List<String> actions;
  final String completedAt;
  final int frameCount;
  final double blinkPeak;
  final double smilePeak;
  final double turnPeak;
  final double neutralBlinkMax;
  final double neutralSmileMax;
  final double neutralTurnMax;

  const MobileLivenessProof({
    required this.actions,
    required this.completedAt,
    required this.frameCount,
    required this.blinkPeak,
    required this.smilePeak,
    required this.turnPeak,
    required this.neutralBlinkMax,
    required this.neutralSmileMax,
    required this.neutralTurnMax,
  });

  Map<String, Object> toJson() => {
    'actions': actions,
    'completedAt': completedAt,
    'frameCount': frameCount,
    'blinkPeak': blinkPeak,
    'smilePeak': smilePeak,
    'turnPeak': turnPeak,
    'neutralBlinkMax': neutralBlinkMax,
    'neutralSmileMax': neutralSmileMax,
    'neutralTurnMax': neutralTurnMax,
  };

  String canonical() => [
    actions.join(','),
    completedAt,
    frameCount.toString(),
    blinkPeak.toStringAsFixed(6),
    smilePeak.toStringAsFixed(6),
    turnPeak.toStringAsFixed(6),
    neutralBlinkMax.toStringAsFixed(6),
    neutralSmileMax.toStringAsFixed(6),
    neutralTurnMax.toStringAsFixed(6),
  ].join('|');
}

class MobileFaceMl {
  static const _channel = MethodChannel('com.smartattendance.mobile/face_ml');
  static Future<void>? _initializing;

  static Future<void> initialize() async {
    final pending = _initializing ??= _channel.invokeMethod<void>('initialize');
    try {
      await pending;
    } catch (_) {
      if (identical(_initializing, pending)) {
        _initializing = null;
      }
      rethrow;
    }
  }

  static Future<MobileFaceAnalysis> analyzeJpeg(Uint8List jpeg) async {
    await initialize();
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'analyzeJpeg',
      {'jpeg': jpeg},
    );
    if (raw == null) {
      throw PlatformException(
        code: 'FACE_ML_EMPTY',
        message: 'Phân tích khuôn mặt không có kết quả',
      );
    }
    return MobileFaceAnalysis.fromMap(raw);
  }

  static Future<MobileFaceAnalysis> analyzeCameraImage(
    CameraImage image, {
    required int rotationDegrees,
    bool includeEmbedding = true,
  }) async {
    // Encode the frame into the platform message while CameraX still owns it.
    // Awaiting before this point can leave us reading a recycled camera buffer.
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'analyzeCameraImage',
      {
        'width': image.width,
        'height': image.height,
        'rotationDegrees': rotationDegrees,
        'includeEmbedding': includeEmbedding,
        'planes': image.planes
            .map(
              (plane) => {
                'bytes': plane.bytes,
                'bytesPerRow': plane.bytesPerRow,
                'bytesPerPixel': plane.bytesPerPixel ?? 1,
              },
            )
            .toList(growable: false),
      },
    );
    if (raw == null) {
      throw PlatformException(
        code: 'FACE_ML_EMPTY',
        message: 'Phân tích khuôn mặt không có kết quả',
      );
    }
    return MobileFaceAnalysis.fromMap(raw);
  }

  static Future<Map<String, String>> signNonce(String payload) async {
    final raw = await _channel.invokeMapMethod<String, String>(
      'signMobileFaceNonce',
      {'payload': payload},
    );
    if (raw == null || raw['publicKey'] == null || raw['signature'] == null) {
      throw PlatformException(code: 'DEVICE_KEY_EMPTY');
    }
    return raw;
  }

  /// Produces the exact proof expected by MobileFaceAuthService. The vector is
  /// normalized once here so its JSON digest stays stable when the server
  /// verifies the Android Keystore signature.
  static Future<MobileFaceProof> signFaceRequest({
    required String sessionId,
    required String nonce,
    required String modelId,
    required Float32List embedding,
    required MobileLivenessProof livenessProof,
  }) async {
    final values = List<double>.from(embedding);
    if (values.length != 128 || values.any((value) => !value.isFinite)) {
      throw PlatformException(code: 'FACE_VECTOR_INVALID');
    }
    final norm = values.fold<double>(0, (sum, value) => sum + value * value);
    if (!norm.isFinite || norm <= 0) {
      throw PlatformException(code: 'FACE_VECTOR_INVALID');
    }
    final scale = 1 / math.sqrt(norm);
    final normalized = values
        .map((value) => value * scale)
        .toList(growable: false);
    final digest = sha256.convert(utf8.encode(jsonEncode(normalized))).bytes;
    final digestBase64Url = base64UrlEncode(digest).replaceAll('=', '');
    final livenessDigest = sha256
        .convert(utf8.encode(livenessProof.canonical()))
        .bytes;
    final livenessDigestBase64Url = base64UrlEncode(
      livenessDigest,
    ).replaceAll('=', '');
    final signed = await signNonce(
      '$sessionId.$nonce.$modelId.$digestBase64Url.$livenessDigestBase64Url',
    );
    return MobileFaceProof(
      embedding: normalized,
      publicKey: signed['publicKey']!,
      signature: signed['signature']!,
    );
  }
}

class MobileFaceProof {
  final List<double> embedding;
  final String publicKey;
  final String signature;

  const MobileFaceProof({
    required this.embedding,
    required this.publicKey,
    required this.signature,
  });
}
