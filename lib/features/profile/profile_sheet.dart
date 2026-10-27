import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/adaptive_sheet.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/avatar_presets.dart';
import '../../core/theme/picture_store.dart';
import '../../core/widgets/pill_button.dart';
import 'profile_avatar.dart';
import 'profile_provider.dart';

/// Edit the name and picture. The picture changes at once; the name is saved with Save.
Future<void> showProfileSheet(BuildContext context) =>
    showAdaptiveSheet<void>(context, builder: (_) => const _ProfileEditor());

class _ProfileEditor extends ConsumerStatefulWidget {
  const _ProfileEditor();

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: ref.read(profileProvider).name,
  );
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _upload(PictureSource source) async {
    setState(() => _message = null);
    try {
      final stored = await ref.read(picturePickerProvider)(source, 'avatar');
      if (stored != null) {
        await ref.read(profileProvider.notifier).useFile(stored.path);
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } on Object {
      if (mounted) {
        setState(() => _message = 'The picture could not be opened.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final profile = ref.watch(profileProvider);
    final controller = ref.read(profileProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Your profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: ProfileAvatar(key: ValueKey('profile-preview'), size: 88),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('profile-name'),
          controller: _name,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 8),
        Text('Picture', style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final p in kAvatarPresets)
              Semantics(
                button: true,
                selected: profile.presetId == p.id,
                label: '${p.name} avatar',
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey('avatar-${p.id}'),
                  customBorder: const CircleBorder(),
                  onTap: () => controller.usePreset(p.id),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.color,
                      border: Border.all(
                        color: profile.presetId == p.id
                            ? t.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Icon(p.icon, size: 24, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            PillButton(
              key: const ValueKey('avatar-upload'),
              label: canTakePhoto ? 'Choose from gallery' : 'Upload a picture',
              style: PillStyle.outlined,
              height: 44,
              icon: Icons.photo_library_outlined,
              onTap: () => _upload(PictureSource.gallery),
            ),
            if (canTakePhoto)
              PillButton(
                key: const ValueKey('avatar-camera'),
                label: 'Take a photo',
                style: PillStyle.outlined,
                height: 44,
                onTap: () => _upload(PictureSource.camera),
              ),
            PillButton(
              key: const ValueKey('avatar-initial'),
              label: 'Use my initial',
              style: PillStyle.outlined,
              height: 44,
              onTap: controller.useInitial,
            ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _message!,
              key: const ValueKey('profile-message'),
              style: TextStyle(fontSize: 13, color: t.rose),
            ),
          ),
        const SizedBox(height: 18),
        PillButton(
          key: const ValueKey('profile-save'),
          label: 'Save',
          onTap: () async {
            await controller.setName(_name.text);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
