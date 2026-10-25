import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Where a receipt photo comes from. The only platform-specific part of scanning: a camera on
/// phones, a file chooser on desktop. Everything after the path is picked is shared code.
abstract interface class ReceiptImageSource {
  bool get hasCamera;

  /// Opens the camera. Null when cancelled.
  Future<String?> takePhoto();

  /// Opens a file chooser (or the gallery). Null when cancelled.
  Future<String?> chooseFile();
}

class ImagePickerReceiptSource implements ReceiptImageSource {
  ImagePickerReceiptSource([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  bool get hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<String?> takePhoto() async => (await _picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 2000,
    imageQuality: 85,
  ))?.path;

  @override
  Future<String?> chooseFile() async => (await _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  ))?.path;
}

/// Reads text out of a receipt photo.
abstract interface class ReceiptOcr {
  /// False where no recogniser exists (desktop): the photo is attached and the details are typed.
  bool get isAvailable;

  Future<String> recognise(String imagePath);
}

/// On-device Google ML Kit (Android and iOS). The image never leaves the phone for recognition.
class MlKitReceiptOcr implements ReceiptOcr {
  @override
  bool get isAvailable => true;

  @override
  Future<String> recognise(String imagePath) async {
    final recogniser = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recogniser.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return result.text;
    } finally {
      await recogniser.close();
    }
  }
}

class NoReceiptOcr implements ReceiptOcr {
  const NoReceiptOcr();

  @override
  bool get isAvailable => false;

  @override
  Future<String> recognise(String imagePath) async => '';
}

/// Shared receipts, one private object per expense: `<household id>/<expense id>.jpg`.
abstract interface class ReceiptStorage {
  /// Uploads and returns the object path to keep in `expenses.receipt_path`.
  Future<String> upload({
    required String householdId,
    required String expenseId,
    required String localPath,
  });
}

class SupabaseReceiptStorage implements ReceiptStorage {
  SupabaseReceiptStorage(this._client);

  final sb.SupabaseClient _client;

  static const bucket = 'receipts';

  @override
  Future<String> upload({
    required String householdId,
    required String expenseId,
    required String localPath,
  }) async {
    final objectPath = '$householdId/$expenseId.jpg';
    await _client.storage
        .from(bucket)
        .upload(
          objectPath,
          File(localPath),
          fileOptions: const sb.FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return objectPath;
  }
}

final receiptImageSourceProvider = Provider<ReceiptImageSource>(
  (ref) => ImagePickerReceiptSource(),
);

final receiptOcrProvider = Provider<ReceiptOcr>(
  (ref) =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
      ? MlKitReceiptOcr()
      : const NoReceiptOcr(),
);

/// Null when there is no Supabase project (local-only mode): photos then stay on the device.
final receiptStorageProvider = Provider<ReceiptStorage?>((ref) => null);
