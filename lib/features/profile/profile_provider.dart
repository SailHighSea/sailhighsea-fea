import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sheets_sync/sheets_settings.dart';
import '../../core/theme/appearance_provider.dart';
import '../family/member_providers.dart';

const kProfileNameKey = 'profile.name';
const kProfileAvatarKey = 'profile.avatar';

/// Who the person is on this device: a name and a picture. The picture is `preset:<id>`,
/// `file:<path>` (their own upload) or empty for the initial letter.
class Profile {
  const Profile({this.name = '', this.avatar = ''});

  final String name;
  final String avatar;

  String? get presetId =>
      avatar.startsWith('preset:') ? avatar.substring(7) : null;
  String? get filePath =>
      avatar.startsWith('file:') ? avatar.substring(5) : null;
}

class ProfileController extends Notifier<Profile> {
  @override
  Profile build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return Profile(
      name: prefs.getString(kProfileNameKey) ?? '',
      avatar: prefs.getString(kProfileAvatarKey) ?? '',
    );
  }

  Future<void> setName(String name) async {
    final clean = name.trim();
    state = Profile(name: clean, avatar: state.avatar);
    await ref.read(sharedPreferencesProvider).setString(kProfileNameKey, clean);
    // In Google Sheets mode the name is also what the family sees.
    if (clean.isNotEmpty && ref.read(isSheetsModeProvider)) {
      await ref
          .read(sheetsSettingsProvider.notifier)
          .update((s) => s.copyWith(displayName: clean));
    }
  }

  Future<void> _setAvatar(String avatar) {
    state = Profile(name: state.name, avatar: avatar);
    return ref
        .read(sharedPreferencesProvider)
        .setString(kProfileAvatarKey, avatar);
  }

  Future<void> usePreset(String id) => _setAvatar('preset:$id');
  Future<void> useFile(String path) => _setAvatar('file:$path');
  Future<void> useInitial() => _setAvatar('');
}

final profileProvider = NotifierProvider<ProfileController, Profile>(
  ProfileController.new,
);

/// The name shown in the app: the one the person chose, else their household name, else "You".
final displayNameProvider = Provider<String>((ref) {
  final chosen = ref.watch(profileProvider).name;
  if (chosen.isNotEmpty) return chosen;
  final member = ref.watch(myMemberProvider).value?.displayName.trim() ?? '';
  if (member.isNotEmpty) return member;
  if (ref.watch(isSheetsModeProvider)) {
    final sheets = ref.watch(
      sheetsSettingsProvider.select((s) => s.displayName.trim()),
    );
    if (sheets.isNotEmpty) return sheets;
  }
  return 'You';
});
