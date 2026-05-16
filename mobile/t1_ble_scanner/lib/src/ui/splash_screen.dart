import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'scanner_page.dart';

/// Animated splash screen shown briefly before navigating to
/// [ScannerPage] and immediately starting a BLE scan.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Radar sweep
  late final AnimationController _sweepCtrl;
  // Dots fade-in / pulse
  late final AnimationController _pulseCtrl;
  // Progress bar
  late final AnimationController _progressCtrl;

  static const Duration _splashDuration = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();

    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _progressCtrl = AnimationController(
      vsync: this,
      duration: _splashDuration,
    )
      ..forward()
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder<void>(
              pageBuilder: (_, __, ___) => const ScannerPage(),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      });
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _pulseCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      body: SafeArea(
        child: Column(
          children: [
            // ── radar canvas ─────────────────────────────────────────────────
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_sweepCtrl, _pulseCtrl]),
                  builder: (_, __) => CustomPaint(
                    painter: _SplashRadarPainter(
                      sweepFraction: _sweepCtrl.value,
                      pulseFraction: _pulseCtrl.value,
                    ),
                    child: const SizedBox(width: 280, height: 280),
                  ),
                ),
              ),
            ),

            // ── title & tagline ───────────────────────────────────────────────
            const Text(
              'T1 BLE Scanner',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Офлайн-дешифровка T1-меток',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 40),

            // ── progress bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _progressCtrl,
                    builder: (_, __) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressCtrl.value,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF00FF87),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _progressCtrl,
                    builder: (_, __) {
                      final remaining = ((_splashDuration.inMilliseconds *
                                  (1 - _progressCtrl.value)) /
                              1000)
                          .ceil();
                      return Text(
                        'Подготовка… $remaining с',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash radar painter (decorative, no real devices)
// ─────────────────────────────────────────────────────────────────────────────

class _SplashRadarPainter extends CustomPainter {
  const _SplashRadarPainter({
    required this.sweepFraction,
    required this.pulseFraction,
  });

  final double sweepFraction;
  final double pulseFraction;

  // Decorative demo dots: (angleDeg, radiusFraction, color)
  static const _dots = [
    (42.0, 0.32, Color(0xFF00FF87)), // resolved T1
    (110.0, 0.61, Color(0xFF00FF87)), // resolved T1
    (200.0, 0.45, Color(0xFFFFAA00)), // T1 unresolved
    (290.0, 0.78, Color(0xFF40C4FF)), // iBeacon
    (330.0, 0.28, Color(0xFFFFAA00)), // T1 unresolved
    (155.0, 0.85, Color(0xFF546E7A)), // plain BLE
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(cx, cy) - 2.0;
    final center = Offset(cx, cy);
    final sweepAngle = sweepFraction * math.pi * 2;
    final circleRect = Rect.fromCircle(center: center, radius: R);

    // Background
    canvas.drawCircle(center, R, Paint()..color = const Color(0xFF071628));

    // Rings
    final ringPaint = Paint()
      ..color = const Color(0xFF1B3A5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, R * i / 3, ringPaint);
    }

    // Crosshairs
    final crossPaint = Paint()
      ..color = const Color(0xFF1B3A5C)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(cx - R, cy), Offset(cx + R, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - R), Offset(cx, cy + R), crossPaint);

    // Sweep tail
    canvas.save();
    canvas.clipPath(Path()..addOval(circleRect));
    const int tailSegs = 14;
    const double tailSpan = math.pi * 0.55;
    for (var i = 0; i < tailSegs; i++) {
      final t = (i + 1) / tailSegs;
      final segStart = sweepAngle - tailSpan + tailSpan * (i / tailSegs);
      final segSpan = tailSpan / tailSegs;
      canvas.drawArc(
        circleRect,
        segStart,
        segSpan,
        true,
        Paint()..color = Color.fromARGB((t * t * 55).round(), 0, 255, 65),
      );
    }
    canvas.restore();

    // Sweep line
    canvas.drawLine(
      center,
      center + Offset(math.cos(sweepAngle), math.sin(sweepAngle)) * R,
      Paint()
        ..color = const Color(0xBB00FF41)
        ..strokeWidth = 1.5,
    );

    // Demo dots
    for (final (angleDeg, radiusFrac, color) in _dots) {
      final a = angleDeg * math.pi / 180;
      final r = radiusFrac * R;
      final pos = center + Offset(math.cos(a), math.sin(a)) * r;

      // Pulse glow for T1 dots
      if (color == const Color(0xFF00FF87) ||
          color == const Color(0xFFFFAA00)) {
        final glowAlpha = 0.1 + pulseFraction * 0.15;
        canvas.drawCircle(
          pos,
          10,
          Paint()
            ..color = color.withValues(alpha: glowAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      final dotR = color == const Color(0xFF00FF87) ? 6.5 : 5.0;
      canvas.drawCircle(pos, dotR, Paint()..color = color);
      canvas.drawCircle(
        pos,
        dotR,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

      // Label for green dots
      if (color == const Color(0xFF00FF87)) {
        final tp = TextPainter(
          text: TextSpan(
            text: angleDeg < 100 ? '#50' : '#42',
            style: const TextStyle(
              color: Color(0xFF00FF87),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos + Offset(dotR + 2, -(tp.height / 2)));
      }
    }

    // Centre dot
    canvas.drawCircle(center, 5, Paint()..color = const Color(0xFF1D4ED8));
    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white);

    // Border
    canvas.drawCircle(
      center,
      R,
      Paint()
        ..color = const Color(0xFF1B3A5C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SplashRadarPainter o) =>
      o.sweepFraction != sweepFraction || o.pulseFraction != pulseFraction;
}
