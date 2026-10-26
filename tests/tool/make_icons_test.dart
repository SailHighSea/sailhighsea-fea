// Draws the app icon (tri-colour ring with FET) into assets/icon. Not part of the normal run:
//   ICONS=1 flutter test tests/tool/make_icons_test.dart
// then: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

const _bg = Color(0xFF0E1512);
const _green = Color(0xFF4CC38A);
const _blue = Color(0xFF6FB3D9);
const _amber = Color(0xFFF2B84B);
const _text = Color(0xFFE8F0EC);

/// The artwork on a 100 x 100 grid, scaled by [scale] around the centre of a [size] canvas.
void _art(
  Canvas c,
  double size, {
  required double scale,
  Color? green,
  Color? blue,
  Color? amber,
  Color? text,
}) {
  final u = size / 100 * scale;
  final origin = (size - 100 * u) / 2;
  Offset p(double x, double y) => Offset(origin + x * u, origin + y * u);
  final ring = Rect.fromCircle(center: p(50, 50), radius: 30 * u);
  Paint arc(Color col) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10 * u
    ..color = col
    ..strokeCap = StrokeCap.butt;
  // Circumference 188.5 on the grid: three arcs of 52 with gaps of 10.8.
  const full = 2 * math.pi;
  const arcLen = 52 / 188.495 * full;
  const step = 63 / 188.495 * full;
  const start = -math.pi / 2;
  c.drawArc(ring, start, arcLen, false, arc(green ?? _green));
  c.drawArc(ring, start + step, arcLen, false, arc(blue ?? _blue));
  c.drawArc(ring, start + 2 * step, arcLen, false, arc(amber ?? _amber));
  final tp = TextPainter(
    text: TextSpan(
      text: 'FET',
      style: TextStyle(
        fontFamily: 'DM Sans',
        fontWeight: FontWeight.w800,
        fontSize: 22 * u,
        letterSpacing: -1 * u,
        color: text ?? _text,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, p(50, 50) - Offset(tp.width / 2, tp.height / 2));
}

Future<void> _save(
  WidgetTester tester,
  String name,
  void Function(Canvas c, double size) draw,
) async {
  await tester.runAsync(() async {
    const size = 1024.0;
    final rec = ui.PictureRecorder();
    draw(Canvas(rec), size);
    final image = await rec.endRecording().toImage(1024, 1024);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('assets/icon/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadTestFonts);
  final on = Platform.environment['ICONS'] == '1';

  testWidgets('draws the icons', (tester) async {
    // Full icon: the ring fills most of the square on a dark ground.
    await _save(tester, 'icon', (c, s) {
      c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = _bg);
      _art(c, s, scale: 1.05);
    });
    // Android adaptive icon: only the middle 66% is always visible, so the artwork is smaller.
    await _save(tester, 'icon_foreground', (c, s) {
      _art(c, s, scale: 0.9);
    });
    // Android 13 themed icon: one colour, the system tints it.
    const white = Color(0xFFFFFFFF);
    await _save(tester, 'icon_monochrome', (c, s) {
      _art(
        c,
        s,
        scale: 0.9,
        green: white,
        blue: white,
        amber: white,
        text: white,
      );
    });
  }, skip: !on);
}
