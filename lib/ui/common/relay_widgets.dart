import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/relay_theme.dart';

/// Grey bars shown while data loads, so a pane is never blank.
class PlaceholderRows extends StatelessWidget {
  const PlaceholderRows({super.key, this.count = 3, this.height = 72});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = RelayColors.of(context);
    return Semantics(
      label: 'Loading',
      child: Column(
        key: const ValueKey('placeholder-rows'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              height: height,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(c.line, 120),
                  const SizedBox(height: 8),
                  _bar(c.line, 240),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(Color color, double width) => Container(
    width: width,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// Small filled circle for status. Always paired with coloured text.
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A panel on the page background (pairing, setup, drafts), as in the
/// design's `.panel`: background fill, radius 12, soft shadow.
class RelayPanel extends StatelessWidget {
  const RelayPanel({super.key, required this.child, this.maxWidth = 480});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = RelayColors.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          // A hairline keeps the panel's edge visible in dark mode, where
          // the shadow alone disappears.
          border: theme.brightness == Brightness.dark
              ? Border.all(color: c.line)
              : null,
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Dashed rounded outline, for the Locked memo.
class DashedBorderBox extends StatelessWidget {
  const DashedBorderBox({
    super.key,
    required this.color,
    required this.child,
    this.radius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Color color;
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedRRectPainter(color, radius),
    child: Padding(padding: padding, child: child),
  );
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          Radius.circular(radius),
        ),
      );
    for (final PathMetric metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}
