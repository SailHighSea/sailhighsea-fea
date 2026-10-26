import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/page_layout.dart';
import '../../core/layout/window_class.dart';
import '../../core/money/currency.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/widgets/surface_card.dart' show TextLinkButton;
import '../../core/money/money_format.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/theme/appearance_settings.dart';
import '../../core/theme/color_themes.dart';
import '../../core/widgets/currency_picker.dart';

/// Appearance settings (Themes, TabAppearance and DeskAppearance mockups). Every control
/// is wired to the real theme switch, so changes apply live and persist.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final money = ref.watch(moneyFormatterProvider);

    return AdaptiveTwoPane(
      secondaryWidth: 300,
      header: PageHeader(
        title: 'Appearance',
        onBack: context.layout.isCompact ? () => context.go('/home') : null,
      ),
      primary: (context, mode) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Mode'),
          const SizedBox(height: 10),
          _ModeSelector(selected: settings.mode, onChanged: controller.setMode),
          const SizedBox(height: 18),
          const _SectionLabel('Colour theme'),
          const SizedBox(height: 10),
          _ThemeGrid(
            columns: mode == PaneMode.stacked ? 2 : 4,
            selected: settings.colorTheme,
            showSelectedLabel: mode == PaneMode.stacked,
            onChanged: controller.setColorTheme,
          ),
          const SizedBox(height: 18),
          _SettingsCard(
            settings: settings,
            controller: controller,
            money: money,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLinkButton(
              key: const ValueKey('keyboard-shortcuts'),
              label: 'Keyboard shortcuts',
              onTap: () => showShortcutHelp(context),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLinkButton(
              key: const ValueKey('open-privacy-data'),
              label: 'Privacy and data: backup, restore, import, lock',
              onTap: () => context.go('/data'),
            ),
          ),
          if (mode == PaneMode.stacked) const SizedBox(height: 16),
        ],
      ),
      secondary: (context, mode) {
        final t = context.tokens;
        final previewDark = _PillButton(
          label: 'Preview in dark mode',
          background: t.text,
          foreground: t.background,
          big: mode == PaneMode.stacked,
          onTap: () => controller.setMode(AppearanceMode.dark),
        );
        if (mode == PaneMode.stacked) return previewDark;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel('Preview'),
            const SizedBox(height: 10),
            _PreviewCard(money: money),
            const SizedBox(height: 14),
            previewDark,
            const SizedBox(height: 12),
            _PillButton(
              label: 'Preview in pure black',
              background: Colors.transparent,
              foreground: t.text,
              outline: t.text,
              onTap: () => controller.setMode(AppearanceMode.pureBlack),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: context.tokens.text,
      ),
    ),
  );
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.selected, required this.onChanged});

  final AppearanceMode selected;
  final ValueChanged<AppearanceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.border,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          for (final mode in AppearanceMode.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: mode == selected,
                label: mode.label,
                excludeSemantics: true,
                child: Material(
                  color: mode == selected ? t.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onChanged(mode),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: kMinTapTarget,
                      ),
                      child: Center(
                        child: Text(
                          mode.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: mode == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: t.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({
    required this.columns,
    required this.selected,
    required this.showSelectedLabel,
    required this.onChanged,
  });

  final int columns;
  final ColorThemeId selected;
  final bool showSelectedLabel;
  final ValueChanged<ColorThemeId> onChanged;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    const themes = ColorThemeId.values;
    final rows = <Widget>[];
    for (var i = 0; i < themes.length; i += columns) {
      final slice = themes.sublist(i, (i + columns).clamp(0, themes.length));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: gap),
              Expanded(
                child: j < slice.length
                    ? _ThemeTile(
                        theme: slice[j],
                        selected: slice[j] == selected,
                        showSelectedLabel: showSelectedLabel,
                        onTap: () => onChanged(slice[j]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
      if (i + columns < themes.length) rows.add(const SizedBox(height: gap));
    }
    return Column(children: rows);
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.showSelectedLabel,
    required this.onTap,
  });

  final ColorThemeId theme;
  final bool selected;
  final bool showSelectedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final preview = previewFor(theme);
    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.label} colour theme',
      excludeSemantics: true,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadii.smallCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.smallCard),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.smallCard),
              border: Border.all(
                color: selected ? t.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 84,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: preview.hero,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.6,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: preview.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        widthFactor: 0.85,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: preview.track,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: showSelectedLabel
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        theme.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ),
                    // DM Sans has no check mark glyph, so draw it as an icon.
                    if (selected && showSelectedLabel)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Selected',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: t.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.check, size: 14, color: t.primary),
                        ],
                      )
                    else if (selected)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.check, size: 16, color: t.text),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.settings,
    required this.controller,
    required this.money,
  });

  final AppearanceSettings settings;
  final AppearanceController controller;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final currency = currencyByCode(settings.currencyCode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadii.smallCard),
      ),
      child: Column(
        children: [
          _SwitchRow(
            label: 'Larger text',
            value: settings.largerText,
            onChanged: controller.setLargerText,
          ),
          Divider(height: 1, color: t.border),
          _SwitchRow(
            label: 'Colour-blind friendly charts',
            value: settings.colorBlindCharts,
            onChanged: controller.setColorBlindCharts,
          ),
          Divider(height: 1, color: t.border),
          _CurrencyRow(currency: currency, onChanged: controller.setCurrency),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, color: t.text),
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({required this.currency, required this.onChanged});

  final CurrencyInfo currency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      key: const ValueKey('currency-row'),
      onTap: () async {
        final code = await showCurrencyPicker(context, selected: currency.code);
        if (code != null) onChanged(code);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Text('Currency', style: TextStyle(fontSize: 15, color: t.text)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${currency.name} (${currency.symbol})',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.money});

  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: t.hero,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: t.heroBorder),
      ),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spent this month',
              style: TextStyle(fontSize: 13, color: t.heroMuted),
            ),
            const SizedBox(height: 6),
            Text(
              money.formatWhole(184200),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: t.heroText,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: t.heroTrack)),
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.74,
                        child: ColoredBox(color: t.ringAccent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.outline,
    this.big = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? outline;
  final bool big;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: StadiumBorder(
          side: outline == null ? BorderSide.none : BorderSide(color: outline!),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: big ? 16 : 15,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
