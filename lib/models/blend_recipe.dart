import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Real-time 3D perspective state derived from device sensors or manual controls.
class PerspectiveState {
  /// Normalized horizon Y position in viewport (0.15 = looking down, 0.5 = level, 0.8 = looking up)
  final double horizonY;

  /// Normalized horizontal vanishing point X (0.0 .. 1.0)
  final double vanishingX;

  /// Camera pitch angle in degrees (-60 looking down .. +45 looking up)
  final double pitchDeg;

  /// Camera roll angle in degrees (-30 .. +30)
  final double rollDeg;

  /// Perspective plane intensity / lens FOV factor (0.2 .. 1.5)
  final double depthStrength;

  /// Whether perspective tracks device gyroscope/accelerometer automatically
  final bool sensorSyncEnabled;

  /// Whether ground grid overlay is visible in viewfinder
  final bool showGrid;

  const PerspectiveState({
    this.horizonY = 0.44,
    this.vanishingX = 0.50,
    this.pitchDeg = -8.0,
    this.rollDeg = 0.0,
    this.depthStrength = 0.85,
    this.sensorSyncEnabled = true,
    this.showGrid = true,
  });

  PerspectiveState copyWith({
    double? horizonY,
    double? vanishingX,
    double? pitchDeg,
    double? rollDeg,
    double? depthStrength,
    bool? sensorSyncEnabled,
    bool? showGrid,
  }) {
    return PerspectiveState(
      horizonY: horizonY ?? this.horizonY,
      vanishingX: vanishingX ?? this.vanishingX,
      pitchDeg: pitchDeg ?? this.pitchDeg,
      rollDeg: rollDeg ?? this.rollDeg,
      depthStrength: depthStrength ?? this.depthStrength,
      sensorSyncEnabled: sensorSyncEnabled ?? this.sensorSyncEnabled,
      showGrid: showGrid ?? this.showGrid,
    );
  }

  /// Perspective scale factor for a standee anchored at normalized ground position `footY`.
  /// Objects closer to horizon appear smaller; objects closer to bottom foreground appear larger.
  double scaleFactorAtY(double footY) {
    final safeHorizon = horizonY.clamp(0.10, 0.78);
    final depth = ((footY - safeHorizon) / (1.0 - safeHorizon)).clamp(0.12, 1.35);
    // Perspective scaling follows linear distance from vanishing horizon
    return (0.28 + depth * 0.92).clamp(0.25, 1.45);
  }

  Map<String, dynamic> toJson() => {
        'horizonY': horizonY,
        'vanishingX': vanishingX,
        'pitchDeg': pitchDeg,
        'rollDeg': rollDeg,
        'depthStrength': depthStrength,
        'sensorSyncEnabled': sensorSyncEnabled,
        'showGrid': showGrid,
      };

  factory PerspectiveState.fromJson(Map<String, dynamic> json) {
    return PerspectiveState(
      horizonY: (json['horizonY'] as num?)?.toDouble() ?? 0.44,
      vanishingX: (json['vanishingX'] as num?)?.toDouble() ?? 0.50,
      pitchDeg: (json['pitchDeg'] as num?)?.toDouble() ?? -8.0,
      rollDeg: (json['rollDeg'] as num?)?.toDouble() ?? 0.0,
      depthStrength: (json['depthStrength'] as num?)?.toDouble() ?? 0.85,
      sensorSyncEnabled: json['sensorSyncEnabled'] as bool? ?? true,
      showGrid: json['showGrid'] as bool? ?? true,
    );
  }
}

/// Standee placement in normalized viewport coordinates (anchored at feet center).
class PlacementTransform {
  /// Normalized X of character's foot anchor (0.0 .. 1.0)
  final double anchorX;

  /// Normalized Y of character's foot anchor (0.2 .. 0.98)
  final double anchorY;

  /// User manual scale multiplier on top of perspective scale (0.25 .. 2.5)
  final double userScale;

  /// In-plane rotation in radians
  final double rotationRad;

  /// Horizontal mirror flip
  final bool flipX;

  /// Subtle 3D tilt X to match camera pitch (-0.35 .. +0.35 rad)
  final double tiltXRad;

  /// Subtle 3D yaw turn (-0.35 .. +0.35 rad)
  final double yawYRad;

  /// Automatically scale character height according to perspective depth when dragging Y
  final bool lockToPerspectiveScale;

  const PlacementTransform({
    this.anchorX = 0.50,
    this.anchorY = 0.84,
    this.userScale = 1.0,
    this.rotationRad = 0.0,
    this.flipX = false,
    this.tiltXRad = 0.0,
    this.yawYRad = 0.0,
    this.lockToPerspectiveScale = true,
  });

  PlacementTransform copyWith({
    double? anchorX,
    double? anchorY,
    double? userScale,
    double? rotationRad,
    bool? flipX,
    double? tiltXRad,
    double? yawYRad,
    bool? lockToPerspectiveScale,
  }) {
    return PlacementTransform(
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
      userScale: userScale ?? this.userScale,
      rotationRad: rotationRad ?? this.rotationRad,
      flipX: flipX ?? this.flipX,
      tiltXRad: tiltXRad ?? this.tiltXRad,
      yawYRad: yawYRad ?? this.yawYRad,
      lockToPerspectiveScale:
          lockToPerspectiveScale ?? this.lockToPerspectiveScale,
    );
  }

  Map<String, dynamic> toJson() => {
        'anchorX': anchorX,
        'anchorY': anchorY,
        'userScale': userScale,
        'rotationRad': rotationRad,
        'flipX': flipX,
        'tiltXRad': tiltXRad,
        'yawYRad': yawYRad,
        'lockToPerspectiveScale': lockToPerspectiveScale,
      };

  factory PlacementTransform.fromJson(Map<String, dynamic> json) {
    return PlacementTransform(
      anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0.50,
      anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0.84,
      userScale: (json['userScale'] as num?)?.toDouble() ?? 1.0,
      rotationRad: (json['rotationRad'] as num?)?.toDouble() ?? 0.0,
      flipX: json['flipX'] as bool? ?? false,
      tiltXRad: (json['tiltXRad'] as num?)?.toDouble() ?? 0.0,
      yawYRad: (json['yawYRad'] as num?)?.toDouble() ?? 0.0,
      lockToPerspectiveScale:
          json['lockToPerspectiveScale'] as bool? ?? true,
    );
  }
}

/// Physical lighting & optical matching parameters sampled from the scene or tuned by user.
class LightingProfile {
  /// Scene color temperature in Kelvin (2600K warm candle .. 9500K cool twilight)
  final double kelvin;

  /// Green/Magenta tint shift (-1.0 green .. +1.0 magenta)
  final double tint;

  /// Exposure EV adjustment (-1.5 .. +1.5)
  final double exposureEv;

  /// Contrast multiplier (0.6 .. 1.45)
  final double contrast;

  /// Saturation match (0.4 .. 1.45)
  final double saturation;

  /// Atmospheric black-level lift (0.0 .. 0.25)
  final double blackLift;

  /// Dominant key light azimuth in degrees (0 = right, 90 = bottom, 180 = left, 270 = top)
  final double lightAzimuthDeg;

  /// Dominant light elevation in degrees (10 = low sunset long shadow .. 80 = high noon short shadow)
  final double lightElevationDeg;

  /// Directional rim/key shading strength on standee (0.0 .. 1.0)
  final double directionalStrength;

  /// Ambient ground bounce color ARGB32
  final int ambientColorValue;

  /// Ambient / ground bounce influence (0.0 .. 0.85)
  final double ambientStrength;

  /// Optical edge Light Wrap intensity (0.0 .. 1.0)
  final double lightWrap;

  /// Grounded contact AO + directional cast shadow opacity (0.0 .. 1.0)
  final double shadowOpacity;

  /// Cast shadow softness / penumbra blur (0.0 .. 1.0)
  final double shadowSoftness;

  /// Lens depth-of-field blur radius in px (0.0 .. 6.0)
  final double dofBlur;

  /// CMOS / film grain noise match (0.0 .. 0.30)
  final double filmGrain;

  /// Master harmonization blend strength (0.0 = raw cutout, 1.0 = full match)
  final double blendStrength;

  /// Whether auto-lighting probe continuously updates this profile in camera preview
  final bool autoMatchEnabled;

  const LightingProfile({
    this.kelvin = 5600,
    this.tint = 0.0,
    this.exposureEv = 0.0,
    this.contrast = 1.0,
    this.saturation = 0.94,
    this.blackLift = 0.04,
    this.lightAzimuthDeg = 315,
    this.lightElevationDeg = 42,
    this.directionalStrength = 0.62,
    this.ambientColorValue = 0xFF8C94A0,
    this.ambientStrength = 0.42,
    this.lightWrap = 0.48,
    this.shadowOpacity = 0.68,
    this.shadowSoftness = 0.55,
    this.dofBlur = 0.4,
    this.filmGrain = 0.08,
    this.blendStrength = 0.92,
    this.autoMatchEnabled = true,
  });

  Color get ambientColor => Color(ambientColorValue);

  /// Converts Kelvin + Tint into normalized linear RGB white-balance multipliers.
  List<double> get whiteBalanceRgb {
    final k = kelvin.clamp(2200.0, 10000.0) / 100.0;
    double r, g, b;
    if (k <= 66.0) {
      r = 255.0;
      g = (99.4708025861 * math.log(k) - 161.1195681661).clamp(0.0, 255.0);
      b = k <= 19.0
          ? 0.0
          : (138.5177312231 * math.log(k - 10.0) - 305.0447927307)
              .clamp(0.0, 255.0);
    } else {
      r = (329.698727446 * math.pow(k - 60.0, -0.1332047592)).clamp(0.0, 255.0);
      g = (288.1221695283 * math.pow(k - 60.0, -0.0755148492))
          .clamp(0.0, 255.0);
      b = 255.0;
    }

    // Normalize relative to neutral D65 daylight (~6500K) and apply tint
    double nr = (r / 255.0);
    double ng = (g / 255.0) * (1.0 - tint * 0.14);
    double nb = (b / 255.0) * (1.0 + tint * 0.06);

    // Keep perceived luminance balanced so color temp doesn't darken/blow out exposure
    final luma = (0.2126 * nr + 0.7152 * ng + 0.0722 * nb).clamp(0.25, 2.0);
    return [
      (nr / luma).clamp(0.55, 1.45),
      (ng / luma).clamp(0.55, 1.45),
      (nb / luma).clamp(0.55, 1.45),
    ];
  }

  /// Normalized 2D light direction vector pointing toward light source on screen
  Offset get lightDirectionVector {
    final rad = lightAzimuthDeg * math.pi / 180.0;
    return Offset(math.cos(rad), math.sin(rad));
  }

  /// Cast shadow length multiplier derived from light elevation
  double get shadowLengthFactor {
    final elevRad = lightElevationDeg.clamp(10.0, 82.0) * math.pi / 180.0;
    return (1.0 / math.tan(elevRad)).clamp(0.25, 2.2);
  }

  LightingProfile copyWith({
    double? kelvin,
    double? tint,
    double? exposureEv,
    double? contrast,
    double? saturation,
    double? blackLift,
    double? lightAzimuthDeg,
    double? lightElevationDeg,
    double? directionalStrength,
    int? ambientColorValue,
    double? ambientStrength,
    double? lightWrap,
    double? shadowOpacity,
    double? shadowSoftness,
    double? dofBlur,
    double? filmGrain,
    double? blendStrength,
    bool? autoMatchEnabled,
  }) {
    return LightingProfile(
      kelvin: kelvin ?? this.kelvin,
      tint: tint ?? this.tint,
      exposureEv: exposureEv ?? this.exposureEv,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      blackLift: blackLift ?? this.blackLift,
      lightAzimuthDeg: lightAzimuthDeg ?? this.lightAzimuthDeg,
      lightElevationDeg: lightElevationDeg ?? this.lightElevationDeg,
      directionalStrength: directionalStrength ?? this.directionalStrength,
      ambientColorValue: ambientColorValue ?? this.ambientColorValue,
      ambientStrength: ambientStrength ?? this.ambientStrength,
      lightWrap: lightWrap ?? this.lightWrap,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      shadowSoftness: shadowSoftness ?? this.shadowSoftness,
      dofBlur: dofBlur ?? this.dofBlur,
      filmGrain: filmGrain ?? this.filmGrain,
      blendStrength: blendStrength ?? this.blendStrength,
      autoMatchEnabled: autoMatchEnabled ?? this.autoMatchEnabled,
    );
  }

  /// Smoothly interpolates toward a newly probed lighting frame to prevent jitter.
  LightingProfile lerpTo(LightingProfile target, double t) {
    double lerpNum(double a, double b) => a + (b - a) * t;
    // Shortest angular interpolation for azimuth
    double diff = ((target.lightAzimuthDeg - lightAzimuthDeg + 540) % 360) - 180;
    final nextAzimuth = (lightAzimuthDeg + diff * t + 360) % 360;
    final cA = ambientColor;
    final cB = target.ambientColor;
    final blendedColor = Color.lerp(cA, cB, t) ?? cB;

    return copyWith(
      kelvin: lerpNum(kelvin, target.kelvin),
      tint: lerpNum(tint, target.tint),
      exposureEv: lerpNum(exposureEv, target.exposureEv),
      contrast: lerpNum(contrast, target.contrast),
      saturation: lerpNum(saturation, target.saturation),
      blackLift: lerpNum(blackLift, target.blackLift),
      lightAzimuthDeg: nextAzimuth,
      lightElevationDeg: lerpNum(lightElevationDeg, target.lightElevationDeg),
      ambientColorValue: blendedColor.toARGB32(),
      filmGrain: lerpNum(filmGrain, target.filmGrain),
    );
  }

  Map<String, dynamic> toJson() => {
        'kelvin': kelvin,
        'tint': tint,
        'exposureEv': exposureEv,
        'contrast': contrast,
        'saturation': saturation,
        'blackLift': blackLift,
        'lightAzimuthDeg': lightAzimuthDeg,
        'lightElevationDeg': lightElevationDeg,
        'directionalStrength': directionalStrength,
        'ambientColorValue': ambientColorValue,
        'ambientStrength': ambientStrength,
        'lightWrap': lightWrap,
        'shadowOpacity': shadowOpacity,
        'shadowSoftness': shadowSoftness,
        'dofBlur': dofBlur,
        'filmGrain': filmGrain,
        'blendStrength': blendStrength,
        'autoMatchEnabled': autoMatchEnabled,
      };

  factory LightingProfile.fromJson(Map<String, dynamic> json) {
    return LightingProfile(
      kelvin: (json['kelvin'] as num?)?.toDouble() ?? 5600,
      tint: (json['tint'] as num?)?.toDouble() ?? 0.0,
      exposureEv: (json['exposureEv'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.94,
      blackLift: (json['blackLift'] as num?)?.toDouble() ?? 0.04,
      lightAzimuthDeg: (json['lightAzimuthDeg'] as num?)?.toDouble() ?? 315,
      lightElevationDeg: (json['lightElevationDeg'] as num?)?.toDouble() ?? 42,
      directionalStrength:
          (json['directionalStrength'] as num?)?.toDouble() ?? 0.62,
      ambientColorValue:
          (json['ambientColorValue'] as num?)?.toInt() ?? 0xFF8C94A0,
      ambientStrength: (json['ambientStrength'] as num?)?.toDouble() ?? 0.42,
      lightWrap: (json['lightWrap'] as num?)?.toDouble() ?? 0.48,
      shadowOpacity: (json['shadowOpacity'] as num?)?.toDouble() ?? 0.68,
      shadowSoftness: (json['shadowSoftness'] as num?)?.toDouble() ?? 0.55,
      dofBlur: (json['dofBlur'] as num?)?.toDouble() ?? 0.4,
      filmGrain: (json['filmGrain'] as num?)?.toDouble() ?? 0.08,
      blendStrength: (json['blendStrength'] as num?)?.toDouble() ?? 0.92,
      autoMatchEnabled: json['autoMatchEnabled'] as bool? ?? true,
    );
  }
}

/// Complete non-destructive blend recipe stored with every gallery item.
class BlendRecipe {
  final String standeeId;
  final PlacementTransform placement;
  final PerspectiveState perspective;
  final LightingProfile lighting;

  const BlendRecipe({
    required this.standeeId,
    this.placement = const PlacementTransform(),
    this.perspective = const PerspectiveState(),
    this.lighting = const LightingProfile(),
  });

  BlendRecipe copyWith({
    String? standeeId,
    PlacementTransform? placement,
    PerspectiveState? perspective,
    LightingProfile? lighting,
  }) {
    return BlendRecipe(
      standeeId: standeeId ?? this.standeeId,
      placement: placement ?? this.placement,
      perspective: perspective ?? this.perspective,
      lighting: lighting ?? this.lighting,
    );
  }

  Map<String, dynamic> toJson() => {
        'standeeId': standeeId,
        'placement': placement.toJson(),
        'perspective': perspective.toJson(),
        'lighting': lighting.toJson(),
      };

  factory BlendRecipe.fromJson(Map<String, dynamic> json) {
    return BlendRecipe(
      standeeId: json['standeeId'] as String? ?? '',
      placement: json['placement'] is Map<String, dynamic>
          ? PlacementTransform.fromJson(
              json['placement'] as Map<String, dynamic>)
          : const PlacementTransform(),
      perspective: json['perspective'] is Map<String, dynamic>
          ? PerspectiveState.fromJson(
              json['perspective'] as Map<String, dynamic>)
          : const PerspectiveState(),
      lighting: json['lighting'] is Map<String, dynamic>
          ? LightingProfile.fromJson(json['lighting'] as Map<String, dynamic>)
          : const LightingProfile(),
    );
  }
}
