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

/// The built-in background pictures, drawn on a 400 x 300 grid scaled to the canvas.
void _picture(Canvas c, String id) {
  Paint f(int argb) => Paint()..color = Color(argb);
  Path poly(List<double> pts) {
    final p = Path()..moveTo(pts[0], pts[1]);
    for (var i = 2; i < pts.length; i += 2) {
      p.lineTo(pts[i], pts[i + 1]);
    }
    return p..close();
  }

  switch (id) {
    case 'dunes':
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 300), f(0xFFF4C27A));
      c.drawCircle(const Offset(300, 70), 36, f(0xFFFFF1C9));
      c.drawPath(
        Path()
          ..moveTo(0, 200)
          ..quadraticBezierTo(100, 120, 200, 190)
          ..quadraticBezierTo(300, 240, 400, 170)
          ..lineTo(400, 300)
          ..lineTo(0, 300)
          ..close(),
        f(0xFFD9893F),
      );
      c.drawPath(
        Path()
          ..moveTo(0, 250)
          ..quadraticBezierTo(120, 190, 240, 245)
          ..quadraticBezierTo(320, 270, 400, 230)
          ..lineTo(400, 300)
          ..lineTo(0, 300)
          ..close(),
        f(0xFFA85B27),
      );
    case 'harbour':
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 300), f(0xFF1B4F7A));
      c.drawRect(const Rect.fromLTWH(0, 150, 400, 150), f(0xFF0B2F4E));
      c.drawCircle(const Offset(90, 70), 28, f(0xFFF5E6B8));
      c.drawRect(const Rect.fromLTWH(0, 148.5, 400, 3), f(0xFF6FB3D9));
      c.drawPath(poly([230, 150, 260, 80, 290, 150]), f(0xFFE8F0F5));
      c.drawPath(poly([320, 150, 340, 105, 360, 150]), f(0xFFE8F0F5));
    case 'forest':
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 300), f(0xFFC7E0CC));
      for (final t in [
        [0.0, 300.0, 60.0, 120.0, 120.0, 300.0],
        [90.0, 300.0, 170.0, 90.0, 250.0, 300.0],
        [220.0, 300.0, 300.0, 140.0, 380.0, 300.0],
      ]) {
        c.drawPath(poly(t), f(0xFF2F6B4F));
      }
      c.drawPath(poly([0, 300, 40, 200, 90, 300]), f(0xFF1F4A38));
      c.drawPath(poly([300, 300, 360, 180, 420, 300]), f(0xFF1F4A38));
    case 'sunset':
      c.drawRect(
        const Rect.fromLTWH(0, 0, 400, 300),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4A1F6B), Color(0xFFE0604A), Color(0xFFF5B14B)],
            stops: [0, 0.6, 1],
          ).createShader(const Rect.fromLTWH(0, 0, 400, 300)),
      );
      c.drawCircle(const Offset(200, 215), 48, f(0xFFFFE29A));
      c.drawRect(const Rect.fromLTWH(0, 235, 400, 65), f(0xFF2A1530));
    case 'city':
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 300), f(0xFF10162E));
      for (final b in [
        [20.0, 130.0, 50.0, 170.0],
        [80.0, 90.0, 60.0, 210.0],
        [150.0, 150.0, 45.0, 150.0],
        [205.0, 70.0, 70.0, 230.0],
        [285.0, 120.0, 55.0, 180.0],
      ]) {
        c.drawRect(Rect.fromLTWH(b[0], b[1], b[2], b[3]), f(0xFF243059));
      }
      for (final w in [
        [95.0, 110.0],
        [115.0, 140.0],
        [225.0, 95.0],
        [245.0, 130.0],
        [300.0, 150.0],
      ]) {
        c.drawRect(Rect.fromLTWH(w[0], w[1], 8, 8), f(0xFFF5D77A));
      }
    case 'blossom':
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 300), f(0xFFFBE3EA));
      c.drawCircle(const Offset(90, 90), 46, f(0xFFF4A6BD));
      c.drawCircle(const Offset(170, 150), 60, f(0xFFEE86A6));
      c.drawCircle(const Offset(290, 80), 50, f(0xFFF7B8CB));
      c.drawCircle(const Offset(320, 210), 64, f(0xFFF4A6BD));
      c.drawCircle(const Offset(70, 230), 52, f(0xFFEE86A6));
  }
}

const _pictureIds = ['dunes', 'harbour', 'forest', 'sunset', 'city', 'blossom'];

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

  testWidgets('draws the built-in background pictures', (tester) async {
    await tester.runAsync(() async {
      Directory('assets/backgrounds').createSync(recursive: true);
      for (final id in _pictureIds) {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        c.scale(3);
        _picture(c, id);
        final image = await rec.endRecording().toImage(1200, 900);
        final raw = (await image.toByteData())!;
        var sum = 0.0;
        final n = raw.lengthInBytes ~/ 4;
        for (var i = 0; i < n; i++) {
          sum +=
              (0.2126 * raw.getUint8(i * 4) +
                  0.7152 * raw.getUint8(i * 4 + 1) +
                  0.0722 * raw.getUint8(i * 4 + 2)) /
              255;
        }
        // ignore: avoid_print
        print('LUMINANCE $id ${(sum / n).toStringAsFixed(3)}');
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        File('assets/backgrounds/$id.png')
            .writeAsBytesSync(png.buffer.asUint8List());
      }
    });
  }, skip: !on);
}
