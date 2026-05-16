import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/beacon_view_model.dart';

/// Animated BLE radar canvas.
///
/// Devices are placed at an RSSI-derived distance from the centre and at a
/// stable angle that is deterministically derived from their key, so their
/// position does not jump between frames.
class RadarView extends StatefulWidget {
  const RadarView({
    super.key,
    required this.devices,
    this.maxRangeMeters = 20.0,
  });

  final List<BeaconViewModel> devices;
  final double maxRangeMeters;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Pre-built, cached TextPainters for static labels (range rings + legend).
  // Recreated only when maxRangeMeters changes (practically never).
  late List<TextPainter> _rangePainters;
  late List<TextPainter> _legendPainters;

  static const _legendItems = [
    (Color(0xFF00FF87), 'T1 расшифровано'),
    (Color(0xFFFFAA00), 'T1 метка'),
    (Color(0xFF40C4FF), 'iBeacon'),
    (Color(0xFF546E7A), 'BLE'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _buildStaticPainters();
  }

  @override
  void didUpdateWidget(RadarView old) {
    super.didUpdateWidget(old);
    if (old.maxRangeMeters != widget.maxRangeMeters) {
      _buildStaticPainters();
    }
  }

  void _buildStaticPainters() {
    const ringLabelStyle = TextStyle(
      color: Color(0x6640C4FF),
      fontSize: 9,
    );
    _rangePainters = List.generate(3, (i) {
      final label = '${(widget.maxRangeMeters * (i + 1) / 3).round()}m';
      return TextPainter(
        text: TextSpan(text: label, style: ringLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
    });

    _legendPainters = _legendItems.map((item) {
      return TextPainter(
        text: TextSpan(
          text: item.$2,
          style: TextStyle(
            color: item.$1.withValues(alpha: 0.75),
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }).toList(growable: false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _RadarPainter(
          devices: widget.devices,
          sweepFraction: _ctrl.value,
          maxRangeMeters: widget.maxRangeMeters,
          now: DateTime.now(),
          rangePainters: _rangePainters,
          legendColors: _legendItems.map((e) => e.$1).toList(growable: false),
          legendPainters: _legendPainters,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.devices,
    required this.sweepFraction,
    required this.maxRangeMeters,
    required this.now,
    required this.rangePainters,
    required this.legendColors,
    required this.legendPainters,
  });

  final List<BeaconViewModel> devices;
  final double sweepFraction;
  final double maxRangeMeters;
  final DateTime now;
  // Pre-built static painters passed from State (no allocation per frame).
  final List<TextPainter> rangePainters;
  final List<Color> legendColors;
  final List<TextPainter> legendPainters;

  static const int _rings = 3;
  static const double _pathLossN = 2.5;
  static const double _defaultTxPower = -59.0;

  // ── helpers ───────────────────────────────────────────────────────────────

  double _rssiToMeters(int rssi, int? txPower) {
    final tx = (txPower ?? _defaultTxPower.toInt()).toDouble();
    final exp = (tx - rssi) / (10.0 * _pathLossN);
    return math.pow(10.0, exp).toDouble().clamp(0.3, maxRangeMeters);
  }

  /// Deterministic angle in radians from beacon key hash (djb2 variant).
  double _angleOf(String id) {
    var h = 5381;
    for (final c in id.codeUnits) {
      h = ((h << 5) + h + c) & 0xFFFFFFFF;
    }
    return (h % 360) * math.pi / 180.0;
  }

  // ── paint ─────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(cx, cy) - 4.0;
    final center = Offset(cx, cy);
    final sweepAngle = sweepFraction * math.pi * 2;
    final circleRect = Rect.fromCircle(center: center, radius: R);

    // ── background ──────────────────────────────────────────────────────────
    canvas.drawCircle(center, R,
        Paint()..color = const Color(0xFF071628));

    // ── range rings ─────────────────────────────────────────────────────────
    final ringPaint = Paint()
      ..color = const Color(0xFF1B3A5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 1; i <= _rings; i++) {
      canvas.drawCircle(center, R * i / _rings, ringPaint);
    }

    // ── crosshairs ──────────────────────────────────────────────────────────
    final crossPaint = Paint()
      ..color = const Color(0xFF1B3A5C)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(cx - R, cy), Offset(cx + R, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - R), Offset(cx, cy + R), crossPaint);

    // ── sweep tail (multi-segment arc for smooth gradient) ──────────────────
    canvas.save();
    canvas.clipPath(Path()..addOval(circleRect));
    const int tailSegments = 14;
    const double tailSpan = math.pi * 0.55; // ~100° tail
    for (var i = 0; i < tailSegments; i++) {
      final t = (i + 1) / tailSegments;
      final segStart = sweepAngle - tailSpan + tailSpan * (i / tailSegments);
      final segSpan = tailSpan / tailSegments;
      canvas.drawArc(
        circleRect,
        segStart,
        segSpan,
        true,
        Paint()
          ..color = Color.fromARGB(
            (t * t * 55).round(), // quadratic fade in
            0, 255, 65,
          ),
      );
    }
    canvas.restore();

    // ── sweep line ──────────────────────────────────────────────────────────
    canvas.drawLine(
      center,
      center + Offset(math.cos(sweepAngle), math.sin(sweepAngle)) * R,
      Paint()
        ..color = const Color(0xBB00FF41)
        ..strokeWidth = 1.5,
    );

    // ── range labels (pre-built painters, no allocation per frame) ──────────
    for (var i = 0; i < _rings; i++) {
      final tp = rangePainters[i];
      tp.paint(canvas, Offset(cx + 4, cy - R * (i + 1) / _rings - 14));
    }

    // ── beacons ─────────────────────────────────────────────────────────────
    for (final device in devices) {
      final distM = _rssiToMeters(device.rssi, device.iBeacon?.txPower);
      final r = (distM / maxRangeMeters).clamp(0.06, 0.93) * R;
      final angle = _angleOf(device.id);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * r;

      // Freshness-based opacity: full for 2 s, then fades to 25 % over 8 s.
      final ageMsec = now.difference(device.lastSeen).inMilliseconds;
      final alpha = ageMsec < 2000
          ? 1.0
          : (1.0 - (ageMsec - 2000) / 8000.0).clamp(0.25, 1.0);

      final Color base;
      final double dotR;
      if (device.isResolved) {
        base = const Color(0xFF00FF87);
        dotR = 7.0;
      } else if (device.isT1) {
        base = const Color(0xFFFFAA00);
        dotR = 6.0;
      } else if (device.operatorColor != null) {
        base = Color(device.operatorColor!);
        dotR = 5.5;
      } else if (device.isIBeacon) {
        base = const Color(0xFF40C4FF);
        dotR = 5.0;
      } else {
        base = const Color(0xFF546E7A);
        dotR = 3.5;
      }

      final color = base.withValues(alpha: alpha);

      // Glow for T1 / resolved / named operator
      if (device.isT1 || device.isResolved || device.operatorColor != null) {
        canvas.drawCircle(
          pos,
          dotR + 6,
          Paint()
            ..color = base.withValues(alpha: 0.15 * alpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      }

      // Dot fill
      canvas.drawCircle(pos, dotR, Paint()..color = color);

      // Dot border
      canvas.drawCircle(
        pos,
        dotR,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

      // Label for resolved beacons
      if (device.isResolved && device.resolvedData != null) {
        final label = '#${device.resolvedData!.tagId}';
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: base.withValues(alpha: alpha),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos + Offset(dotR + 3, -(tp.height / 2)));
      }
    }

    // ── scanner centre dot ───────────────────────────────────────────────────
    canvas.drawCircle(center, 5, Paint()..color = const Color(0xFF1D4ED8));
    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white);

    // ── outer border ─────────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      R,
      Paint()
        ..color = const Color(0xFF1B3A5C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── legend (bottom-left corner of the radar circle) ───────────────────
    _drawLegend(canvas, center, R);
  }

  void _drawLegend(Canvas canvas, Offset center, double R) {
    final ox = center.dx - R + 8;
    var oy = center.dy + R - 8 - legendPainters.length * 14.0;

    for (var i = 0; i < legendPainters.length; i++) {
      final color = legendColors[i];
      canvas.drawCircle(Offset(ox + 4, oy + 5), 3.5, Paint()..color = color);
      legendPainters[i].paint(canvas, Offset(ox + 11, oy - 0.5));
      oy += 14;
    }
  }

  @override
  bool shouldRepaint(_RadarPainter o) =>
      o.sweepFraction != sweepFraction ||
      !identical(o.devices, devices) ||
      o.now != now;
}
