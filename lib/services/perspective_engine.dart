import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/blend_recipe.dart';

/// Fuses device accelerometer data into real-time 3D perspective horizon & pitch/roll angles,
/// and provides geometric helpers for perspective grid lines and standee 3D transforms.
class PerspectiveEngine {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _filteredPitchDeg = -8.0;
  double _filteredRollDeg = 0.0;
  bool _hasReading = false;

  /// Typical smartphone main camera vertical FOV (~62 deg).
  static const double verticalFovDeg = 62.0;

  bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Starts streaming smoothed pitch/roll updates derived from gravity vector.
  void startListening({
    required void Function(double pitchDeg, double rollDeg, double horizonY) onUpdate,
  }) {
    stopListening();
    if (!isSupportedPlatform) return;

    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(
        (AccelerometerEvent event) {
          final raw = computeOrientationFromGravity(event.x, event.y, event.z);
          if (!_hasReading) {
            _filteredPitchDeg = raw.pitchDeg;
            _filteredRollDeg = raw.rollDeg;
            _hasReading = true;
          } else {
            const alpha = 0.14;
            _filteredPitchDeg += (raw.pitchDeg - _filteredPitchDeg) * alpha;
            _filteredRollDeg += (raw.rollDeg - _filteredRollDeg) * alpha;
          }
          final horizonY = pitchToHorizonY(_filteredPitchDeg);
          onUpdate(_filteredPitchDeg, _filteredRollDeg, horizonY);
        },
        onError: (Object error) {
          debugPrint('PerspectiveEngine sensor error: $error');
        },
      );
    } catch (e) {
      debugPrint('PerspectiveEngine unable to attach accelerometer: $e');
    }
  }

  void stopListening() {
    _accelSub?.cancel();
    _accelSub = null;
    _hasReading = false;
  }

  /// Pure math conversion from portrait device gravity vector `(gx, gy, gz)` in m/s^2
  /// to camera pitch (deg, negative = tilted downward) and roll (deg).
  static ({double pitchDeg, double rollDeg}) computeOrientationFromGravity(
    double gx,
    double gy,
    double gz,
  ) {
    final horizMag = math.sqrt(gx * gx + gy * gy).clamp(0.001, 100.0);
    // In upright portrait, +y points up; tilting phone downward makes +z face upward (>0).
    final pitchRad = -math.atan2(gz, horizMag);
    final rollRad = math.atan2(-gx, gy.abs() < 0.1 ? 0.1 : gy);

    final pitchDeg = (pitchRad * 180.0 / math.pi).clamp(-55.0, 40.0);
    final rollDeg = (rollRad * 180.0 / math.pi).clamp(-30.0, 30.0);
    return (pitchDeg: pitchDeg, rollDeg: rollDeg);
  }

  /// Maps camera pitch angle (degrees) to normalized screen horizon Y (0.14..0.78).
  static double pitchToHorizonY(double pitchDeg) {
    final halfFovRad = (verticalFovDeg * 0.5) * math.pi / 180.0;
    final pitchRad = pitchDeg * math.pi / 180.0;
    final offset = math.tan(pitchRad) / (2.0 * math.tan(halfFovRad));
    return (0.50 + offset).clamp(0.14, 0.78);
  }

  /// Inverse helper: converts a user-dragged horizonY back to approximate pitch degrees.
  static double horizonYToPitchDeg(double horizonY) {
    final halfFovRad = (verticalFovDeg * 0.5) * math.pi / 180.0;
    final pitchRad = math.atan((horizonY - 0.50) * 2.0 * math.tan(halfFovRad));
    return (pitchRad * 180.0 / math.pi).clamp(-55.0, 40.0);
  }

  /// Builds a 3D perspective Matrix4 for rendering the standee naturally on the ground plane,
  /// including coupling to the horizon rotation angle (`rollDeg`).
  static Matrix4 buildStandeeMatrix({
    required PlacementTransform placement,
    required PerspectiveState perspective,
  }) {
    final autoTiltX = (perspective.pitchDeg * 0.0045).clamp(-0.18, 0.12);
    final totalTiltX = (placement.tiltXRad + autoTiltX).clamp(-0.38, 0.38);
    final rollRad = perspective.rollDeg * math.pi / 180.0;

    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0012 * perspective.depthStrength)
      ..rotateZ(placement.rotationRad + rollRad)
      ..rotateX(totalTiltX)
      ..rotateY(placement.yawYRad);

    if (placement.flipX) {
      m.multiply(Matrix4.diagonal3Values(-1.0, 1.0, 1.0));
    }
    return m;
  }

  /// Computes continuous, non-degenerate 360-degree ground-plane basis vectors
  /// `(widthAxis, heightAxis)` mapping standee local width `u` (-W/2..+W/2) and
  /// height from feet `h` (0..H) onto 2D viewport ground coordinates around `(anchorX, anchorY)`.
  static ({Offset widthAxis, Offset heightAxis}) computeShadowBasis({
    required LightingProfile lighting,
    required PerspectiveState perspective,
    required double anchorYNorm,
  }) {
    final lightVec = lighting.lightDirectionVector;
    final castDirX = -lightVec.dx;
    final castDirY = -lightVec.dy;

    final flatness = contactEllipseFlatness(anchorYNorm, perspective.horizonY);
    final shadowLen = lighting.shadowLengthFactor;

    final hx = castDirX * shadowLen * 0.72;
    final hy = castDirY * shadowLen * flatness * 1.50;

    // Perpendicular ground cross-section vector: guarantees det > 0 smoothly across all 360°!
    final wx = castDirY * 0.88;
    final wy = -castDirX * flatness * 0.75;

    final rollRad = perspective.rollDeg * math.pi / 180.0;
    final cosR = math.cos(rollRad);
    final sinR = math.sin(rollRad);

    return (
      widthAxis: Offset(wx * cosR - wy * sinR, wx * sinR + wy * cosR),
      heightAxis: Offset(hx * cosR - hy * sinR, hx * sinR + hy * cosR),
    );
  }

  static double groundDepthRatio(double anchorY, double horizonY) {
    final safeH = horizonY.clamp(0.10, 0.78);
    return ((anchorY - safeH) / (1.0 - safeH)).clamp(0.05, 1.25);
  }

  static double estimateDistanceMeters(double anchorY, double horizonY) {
    final depth = groundDepthRatio(anchorY, horizonY);
    return (1.2 / depth).clamp(0.8, 18.0);
  }

  static double contactEllipseFlatness(double anchorY, double horizonY) {
    final depth = groundDepthRatio(anchorY, horizonY);
    return (0.14 + depth * 0.22).clamp(0.12, 0.42);
  }
}
