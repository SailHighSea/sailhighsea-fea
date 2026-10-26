import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

enum PictureSource { gallery, camera }

/// A picture copied into the app, with how bright it is on average (0 to 1).
class StoredPicture {
  const StoredPicture(this.path, this.luminance);
  final String path;
  final double luminance;
}

/// Lets the person choose a picture and returns the copy the app keeps, or null when cancelled.
/// [slot] names what it is for (`page` or `card`); an older picture of the same slot is removed.
typedef PicturePicker = Future<StoredPicture?> Function(
  PictureSource source,
  String slot,
);

bool get _isPhone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Whether this device can take a photo (phones; computers only choose a file).
bool get canTakePhoto => _isPhone;

final picturePickerProvider = Provider<PicturePicker>(
  (ref) => (source, slot) async {
    Uint8List? bytes;
    if (_isPhone) {
      final file = await ImagePicker().pickImage(
        source: source == PictureSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      bytes = await file?.readAsBytes();
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Pictures',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
          ),
        ],
      );
      bytes = await file?.readAsBytes();
    }
    if (bytes == null) return null;
    return keepPicture(bytes, slot);
  },
);

/// Scales a picture down (so it does not slow the app), measures its brightness and stores it in
/// the app's own folder. Throws [FormatException] for a file that is not a picture.
Future<StoredPicture> keepPicture(Uint8List bytes, String slot) async {
  final ui.Image small;
  final ui.Image big;
  try {
    final tiny = await ui.instantiateImageCodec(bytes, targetWidth: 24);
    small = (await tiny.getNextFrame()).image;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1600);
    big = (await codec.getNextFrame()).image;
  } on Object {
    throw const FormatException('That file is not a picture.');
  }
  final raw = (await small.toByteData())!;
  var sum = 0.0;
  final pixels = raw.lengthInBytes ~/ 4;
  for (var i = 0; i < pixels; i++) {
    final r = raw.getUint8(i * 4), g = raw.getUint8(i * 4 + 1);
    final b = raw.getUint8(i * 4 + 2);
    sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  }
  final luminance = pixels == 0 ? 0.5 : sum / pixels;
  final png = (await big.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = Directory(
    '${(await getApplicationSupportDirectory()).path}/backgrounds',
  )..createSync(recursive: true);
  for (final f in dir.listSync()) {
    if (f is File && f.uri.pathSegments.last.startsWith('$slot-')) {
      f.deleteSync();
    }
  }
  final file = File(
    '${dir.path}/$slot-${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(png.buffer.asUint8List());
  return StoredPicture(file.path, luminance);
}

/// Puts picture [bytes] (already scaled, taken from a backup) back in the app's folder and returns
/// its path. An older picture for the same [slot] is removed.
Future<String> storePictureBytes(Uint8List bytes, String slot) async {
  final dir = Directory(
    '${(await getApplicationSupportDirectory()).path}/backgrounds',
  )..createSync(recursive: true);
  for (final f in dir.listSync()) {
    if (f is File && f.uri.pathSegments.last.startsWith('$slot-')) {
      f.deleteSync();
    }
  }
  final file = File(
    '${dir.path}/$slot-${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(bytes);
  return file.path;
}
