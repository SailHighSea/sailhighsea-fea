/// A background picture that comes with the app.
class PresetPicture {
  const PresetPicture(this.id, this.name, this.luminance);

  final String id;
  final String name;

  /// Average brightness, 0 to 1 (measured when the picture was drawn).
  final double luminance;

  /// What is stored as a picture path for it.
  String get path => 'asset:assets/backgrounds/$id.png';
  String get asset => 'assets/backgrounds/$id.png';
}

const kPresetPictures = <PresetPicture>[
  PresetPicture('dunes', 'Dunes', 0.674),
  PresetPicture('harbour', 'Harbour', 0.254),
  PresetPicture('forest', 'Forest', 0.666),
  PresetPicture('sunset', 'Sunset', 0.334),
  PresetPicture('city', 'City night', 0.135),
  PresetPicture('blossom', 'Blossom', 0.825),
];

/// Whether a stored picture path is one of the built-in pictures (not a file on this device).
bool isPresetPath(String? path) => path != null && path.startsWith('asset:');
