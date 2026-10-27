import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/page_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/personal_look.dart';
import '../../core/theme/picture_store.dart';
import '../../core/theme/preset_pictures.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';

enum _Target { page, card }

/// Backgrounds and pictures: a colour, a gradient or the person's own picture behind every
/// screen, and the same for the Home card that shows what was spent. Changes apply at once.
class PersonaliseScreen extends ConsumerStatefulWidget {
  const PersonaliseScreen({super.key});

  @override
  ConsumerState<PersonaliseScreen> createState() => _PersonaliseScreenState();
}

class _PersonaliseScreenState extends ConsumerState<PersonaliseScreen> {
  _Target _target = _Target.page;
  String? _message;

  BackgroundStyle get _style {
    final look = ref.read(personalLookProvider);
    return _target == _Target.page ? look.page : look.card;
  }

  Future<void> _set(BackgroundStyle s) {
    final c = ref.read(personalLookProvider.notifier);
    return _target == _Target.page ? c.setPage(s) : c.setCard(s);
  }

  Future<void> _pick(PictureSource source) async {
    setState(() => _message = null);
    try {
      final stored = await ref.read(picturePickerProvider)(
        source,
        _target.name,
      );
      if (stored == null) return;
      await _set(
        _style.copyWith(
          kind: BackgroundKind.picture,
          picturePath: stored.path,
          pictureLuminance: stored.luminance,
        ),
      );
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
    final style = ref.watch(
      personalLookProvider.select(
        (l) => _target == _Target.page ? l.page : l.card,
      ),
    );
    final kind = style.kind == BackgroundKind.none
        ? BackgroundKind.solid
        : style.kind;
    final ratio = style.active ? style.contrast : null;
    return AdaptivePage(
      header: PageHeader(
        title: 'Backgrounds and pictures',
        onBackWhenCompact: () => context.go('/appearance'),
      ),
      children: [
        _Section(
          title: 'What to change',
          note: _target == _Target.page
              ? 'Behind every screen. Cards stay solid on top, so numbers are easy to read. The light or dark look follows the picture.'
              : 'The "Spent this month" card on Home. Other cards keep their plain surface.',
          child: _Segments<_Target>(
            keyPrefix: 'bg-target',
            value: _target,
            options: const {
              _Target.page: 'App background',
              _Target.card: 'Home card',
            },
            onChanged: (v) => setState(() {
              _target = v;
              _message = null;
            }),
          ),
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Style',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Segments<BackgroundKind>(
                keyPrefix: 'bg-kind',
                value: kind,
                options: const {
                  BackgroundKind.solid: 'Colour',
                  BackgroundKind.gradient: 'Gradient',
                  BackgroundKind.picture: 'Picture',
                },
                onChanged: (k) => _set(style.copyWith(kind: k)),
              ),
              const SizedBox(height: 14),
              if (kind == BackgroundKind.solid)
                _Swatches(
                  keyPrefix: 'bg-color',
                  count: kBackgroundColors.length,
                  selected: style.kind == BackgroundKind.solid
                      ? kBackgroundColors.indexOf(style.color)
                      : -1,
                  decoration: (i) =>
                      BoxDecoration(color: Color(kBackgroundColors[i])),
                  onTap: (i) => _set(
                    style.copyWith(
                      kind: BackgroundKind.solid,
                      color: kBackgroundColors[i],
                    ),
                  ),
                ),
              if (kind == BackgroundKind.gradient) ...[
                _Swatches(
                  keyPrefix: 'bg-gradient',
                  count: kBackgroundGradients.length,
                  selected: style.kind == BackgroundKind.gradient
                      ? style.gradient
                      : -1,
                  decoration: (i) => BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(kBackgroundGradients[i].$1),
                        Color(kBackgroundGradients[i].$2),
                      ],
                    ),
                  ),
                  onTap: (i) => _set(
                    style.copyWith(kind: BackgroundKind.gradient, gradient: i),
                  ),
                ),
                _Slider(
                  key: const ValueKey('bg-angle'),
                  label: 'Angle',
                  value: style.angle.toDouble(),
                  min: 0,
                  max: 360,
                  divisions: 36,
                  suffix: '°',
                  onChanged: (v) => _set(
                    style.copyWith(
                      kind: BackgroundKind.gradient,
                      angle: v.round(),
                    ),
                  ),
                ),
              ],
              if (kind == BackgroundKind.picture) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final p in kPresetPictures)
                      Semantics(
                        button: true,
                        selected: style.picturePath == p.path,
                        label: '${p.name} picture',
                        excludeSemantics: true,
                        child: InkWell(
                          key: ValueKey('bg-preset-${p.id}'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _set(
                            style.copyWith(
                              kind: BackgroundKind.picture,
                              picturePath: p.path,
                              pictureLuminance: p.luminance,
                            ),
                          ),
                          child: Container(
                            width: 92,
                            height: 68,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: style.picturePath == p.path
                                    ? t.primary
                                    : t.border,
                                width: style.picturePath == p.path ? 3 : 1,
                              ),
                            ),
                            child: Image.asset(p.asset, fit: BoxFit.cover),
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
                      key: const ValueKey('bg-gallery'),
                      label: canTakePhoto
                          ? 'Choose from gallery'
                          : 'Choose a picture',
                      height: 44,
                      onTap: () => _pick(PictureSource.gallery),
                    ),
                    if (canTakePhoto)
                      PillButton(
                        key: const ValueKey('bg-camera'),
                        label: 'Take a photo',
                        style: PillStyle.outlined,
                        height: 44,
                        onTap: () => _pick(PictureSource.camera),
                      ),
                  ],
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        key: const ValueKey('bg-message'),
                        style: TextStyle(fontSize: 13, color: t.rose),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Your own pictures stay on this device, shrunk to a sensible size, and travel with your backup file. The six above come with the app.',
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
                if (style.picturePath != null) ...[
                  _Slider(
                    key: const ValueKey('bg-blur'),
                    label: 'Blur',
                    value: style.blur.toDouble(),
                    min: 0,
                    max: 24,
                    divisions: 24,
                    onChanged: (v) => _set(style.copyWith(blur: v.round())),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_target == _Target.page && style.active) ...[
          _Section(
            title: 'Glass',
            child: SwitchListTile(
              key: const ValueKey('bg-glass'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Glass cards and bottom bar',
                style: TextStyle(fontSize: 15, color: t.text),
              ),
              subtitle: Text(
                'Frosted, see-through cards and bar that blur the background behind them.',
                style: TextStyle(fontSize: 13, color: t.muted),
              ),
              value: style.glass,
              onChanged: (v) => _set(style.copyWith(glass: v)),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _Section(
          title: 'Keep text readable',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kind == BackgroundKind.picture)
                _Slider(
                  key: const ValueKey('bg-dim'),
                  label: 'Dim the picture',
                  value: style.dim.toDouble(),
                  min: 0,
                  max: 80,
                  divisions: 16,
                  suffix: '%',
                  onChanged: (v) => _set(style.copyWith(dim: v.round())),
                ),
              Text(
                'Text colour',
                style: TextStyle(fontSize: 13, color: t.muted),
              ),
              const SizedBox(height: 6),
              _Segments<TextTone>(
                keyPrefix: 'bg-tone',
                value: style.tone,
                options: const {
                  TextTone.auto: 'Automatic',
                  TextTone.light: 'Light',
                  TextTone.dark: 'Dark',
                },
                onChanged: (v) => _set(style.copyWith(tone: v)),
              ),
              const SizedBox(height: 10),
              Text(
                ratio == null
                    ? 'Contrast: the theme\'s own colours'
                    : ratio >= 4.5
                    ? 'Contrast ${ratio.toStringAsFixed(1)} to 1: good'
                    : 'Contrast ${ratio.toStringAsFixed(1)} to 1: low. Dim the picture more or change the text colour.',
                key: const ValueKey('bg-contrast'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ratio != null && ratio < 4.5 ? t.rose : t.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PillButton(
              key: const ValueKey('bg-reset-this'),
              label: _target == _Target.page
                  ? 'Reset the app background'
                  : 'Reset the Home card',
              style: PillStyle.outlined,
              height: 44,
              onTap: () => _set(BackgroundStyle.none),
            ),
            TextLinkButton(
              key: const ValueKey('bg-reset-all'),
              label: 'Reset everything',
              onTap: () => ref.read(personalLookProvider.notifier).reset(),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.note});
  final String title;
  final Widget child;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 12),
          child,
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!, style: TextStyle(fontSize: 13, color: t.muted)),
          ],
        ],
      ),
    );
  }
}

class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.keyPrefix,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String keyPrefix;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        for (final e in options.entries)
          Expanded(
            child: Semantics(
              button: true,
              selected: e.key == value,
              label: e.value,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Material(
                  color: e.key == value ? t.primary : t.background,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: e.key == value ? t.primary : t.border,
                    ),
                  ),
                  child: InkWell(
                    key: ValueKey('$keyPrefix-${(e.key as Enum).name}'),
                    customBorder: const StadiumBorder(),
                    onTap: () => onChanged(e.key),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: kMinTapTarget,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        e.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: e.key == value ? t.onPrimary : t.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.keyPrefix,
    required this.count,
    required this.selected,
    required this.decoration,
    required this.onTap,
  });

  final String keyPrefix;
  final int count;
  final int selected;
  final BoxDecoration Function(int) decoration;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: '$keyPrefix ${i + 1}',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('$keyPrefix-$i'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTap(i),
              child: Container(
                width: 52,
                height: 52,
                decoration: decoration(i).copyWith(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: i == selected ? t.primary : t.border,
                    width: i == selected ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
              ),
              Text(
                '${value.round()}$suffix',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (v) => '${v.round()}$suffix',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
