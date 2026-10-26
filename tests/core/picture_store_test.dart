// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:family_expenses/core/theme/picture_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

Future<Uint8List> _png(ui.Color color, {int w = 64, int h = 48}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(w, h);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps a picture in the app folder and measures its brightness', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('pics');
    addTearDown(() => dir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePaths(dir.path);
    await tester.runAsync(() async {
      final white = await keepPicture(
        await _png(const ui.Color(0xFFFFFFFF)),
        'page',
      );
      expect(white.luminance, greaterThan(0.95));
      expect(File(white.path).existsSync(), isTrue);

      final black = await keepPicture(
        await _png(const ui.Color(0xFF000000)),
        'page',
      );
      expect(black.luminance, lessThan(0.05));
      expect(File(black.path).existsSync(), isTrue);
      expect(
        File(white.path).existsSync(),
        isFalse,
        reason: 'the older picture for the same slot is removed',
      );

      final other = await keepPicture(
        await _png(const ui.Color(0xFF808080)),
        'card',
      );
      expect(File(black.path).existsSync(), isTrue, reason: 'other slot kept');
      expect(other.luminance, closeTo(0.5, 0.05));
    });
  });

  testWidgets('a big picture is scaled down', (tester) async {
    final dir = Directory.systemTemp.createTempSync('pics');
    addTearDown(() => dir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePaths(dir.path);
    await tester.runAsync(() async {
      final stored = await keepPicture(
        await _png(const ui.Color(0xFF336699), w: 3200, h: 2000),
        'page',
      );
      final codec = await ui.instantiateImageCodec(
        File(stored.path).readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 1600);
    });
  });

  testWidgets('a file that is not a picture is refused', (tester) async {
    final dir = Directory.systemTemp.createTempSync('pics');
    addTearDown(() => dir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePaths(dir.path);
    await tester.runAsync(() async {
      await expectLater(
        keepPicture(Uint8List.fromList([1, 2, 3, 4]), 'page'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
