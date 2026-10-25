import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import '../../core/widgets/surface_card.dart';
import '../expenses/expense_form_controller.dart';
import '../expenses/expense_form_screen.dart';
import '../expenses/expense_providers.dart';
import 'receipt_parser.dart';
import 'receipt_services.dart';

enum _Stage { pick, reading, result }

/// Scan a receipt: take a photo (phone) or choose one (desktop), read it on the device, show what
/// was found, and either save it straight away or open the Add form with it filled in.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _Stage _stage = _Stage.pick;
  String? _imagePath;
  ParsedReceipt _found = const ParsedReceipt();
  bool _share = false;
  bool _saving = false;
  String? _message;

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _pick({required bool camera}) async {
    final source = ref.read(receiptImageSourceProvider);
    final String? path;
    try {
      path = camera ? await source.takePhoto() : await source.chooseFile();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not open the camera or files.');
      }
      return;
    }
    if (path == null || !mounted) return;
    setState(() {
      _imagePath = path;
      _stage = _Stage.reading;
      _message = null;
    });
    final ocr = ref.read(receiptOcrProvider);
    var parsed = const ParsedReceipt();
    if (ocr.isAvailable) {
      try {
        parsed = parseReceiptText(
          await ocr.recognise(path),
          now: ref.read(clockProvider)(),
        );
      } catch (_) {
        // Fall through: the photo is attached and the details are typed.
      }
    }
    if (!mounted) return;
    setState(() {
      _found = parsed;
      _stage = _Stage.result;
      _message = !ocr.isAvailable
          ? 'Reading receipts is not available on this device. The photo is attached; type the details.'
          : (parsed.isEmpty
                ? 'We could not read anything. Try a flatter, brighter photo, or type the details.'
                : null);
    });
  }

  String? _categoryId(List<CategoryRow> categories) {
    final hint = _found.categoryHint?.toLowerCase();
    if (hint == null) return null;
    return categories
        .where((c) => c.name.toLowerCase().contains(hint))
        .firstOrNull
        ?.id;
  }

  void _fillDraft() {
    final categories = ref.read(categoriesProvider).value ?? const [];
    ref
        .read(expenseFormProvider(null).notifier)
        .applyReceipt(
          imagePath: _imagePath!,
          cents: _found.cents,
          date: _found.date,
          categoryId: _categoryId(categories),
          note: _found.merchant,
          share: _share,
        );
  }

  Future<void> _save() async {
    if (_saving || _imagePath == null) return;
    setState(() => _saving = true);
    _fillDraft();
    final controller = ref.read(expenseFormProvider(null).notifier);
    final saved = await controller.save();
    if (!mounted) return;
    if (saved) {
      controller.reset();
      context.go('/home');
    } else {
      setState(() => _saving = false);
    }
  }

  void _edit() {
    _fillDraft();
    context.pushReplacement('/add');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final source = ref.watch(receiptImageSourceProvider);
    final canShare = ref.watch(receiptStorageProvider) != null;
    final money = ref.watch(moneyFormatterProvider);
    final now = ref.watch(clockProvider)();
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final categoryName = categories
        .where((c) => c.id == _categoryId(categories))
        .firstOrNull
        ?.name;
    final hasAmount = _found.cents != null;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.close,
                      label: 'Close',
                      onTap: _close,
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Scan receipt',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: kMinTapTarget),
                  ],
                ),
                const SizedBox(height: 16),
                _Viewfinder(
                  imagePath: _imagePath,
                  reading: _stage == _Stage.reading,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (source.hasCamera)
                      _SourceButton(
                        key: const ValueKey('take-photo'),
                        icon: Icons.photo_camera_outlined,
                        label: 'Take photo',
                        onTap: () => _pick(camera: true),
                      ),
                    _SourceButton(
                      key: const ValueKey('choose-photo'),
                      icon: Icons.image_outlined,
                      label: source.hasCamera
                          ? 'Choose photo'
                          : 'Choose a photo of the receipt',
                      onTap: () => _pick(camera: false),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    key: const ValueKey('scan-message'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: t.muted),
                  ),
                ],
                if (_stage == _Stage.result) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    child: Text(
                      'We read this from your receipt',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _ResultRow(
                          label: 'Amount',
                          value: hasAmount
                              ? money.format(_found.cents!)
                              : 'Not found',
                          found: hasAmount,
                        ),
                        _ResultRow(
                          label: 'Shop',
                          value: _found.merchant ?? 'Not found',
                          found: _found.merchant != null,
                        ),
                        _ResultRow(
                          label: 'Date',
                          value: relativeDateLabel(_found.date ?? now, now),
                          found: _found.date != null,
                        ),
                        _ResultRow(
                          label: 'Category',
                          value: categoryName ?? 'Not found',
                          found: categoryName != null,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Check the details. You can change anything before saving. The photo stays on your device unless you share it with the household.',
                    style: TextStyle(fontSize: 13, color: t.muted),
                  ),
                  if (canShare)
                    SwitchListTile(
                      key: const ValueKey('share-receipt'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Share the photo with the household',
                        style: TextStyle(fontSize: 15, color: t.text),
                      ),
                      value: _share,
                      onChanged: (v) => setState(() => _share = v),
                    ),
                  const SizedBox(height: 16),
                  if (hasAmount)
                    PrimaryPillButton(
                      label: 'Save expense',
                      busy: _saving,
                      onTap: _save,
                    )
                  else
                    PrimaryPillButton(
                      label: 'Fill in the details',
                      onTap: _edit,
                    ),
                  const SizedBox(height: 4),
                  if (hasAmount)
                    Center(
                      child: TextLinkButton(
                        label: 'Change details first',
                        onTap: _edit,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: t.surface,
        shape: StadiumBorder(side: BorderSide(color: t.chipBorder)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: t.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
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
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.found,
    this.last = false,
  });

  final String label;
  final String value;
  final bool found;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: t.border)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              Text(label, style: TextStyle(fontSize: 15, color: t.muted)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: found ? t.text : t.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark "camera" panel from the mockup with its four green corner marks. It shows the chosen
/// photo once there is one.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.imagePath, required this.reading});

  final String? imagePath;
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: imagePath == null
          ? 'No receipt chosen yet'
          : (reading ? 'Reading the receipt' : 'Receipt photo'),
      child: AspectRatio(
        aspectRatio: 1.6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.hero,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(28),
                child: imagePath == null
                    ? Center(
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 56,
                          color: t.heroMuted,
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(imagePath!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(
                            child: Icon(
                              Icons.receipt_long_outlined,
                              size: 56,
                              color: t.heroMuted,
                            ),
                          ),
                        ),
                      ),
              ),
              CustomPaint(painter: _CornerPainter(t.ringAccent)),
              if (reading)
                Center(child: CircularProgressIndicator(color: t.heroText)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const inset = 16.0;
    const len = 30.0;
    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * len, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * len), p);
    }

    corner(inset, inset, 1, 1);
    corner(size.width - inset, inset, -1, 1);
    corner(inset, size.height - inset, 1, -1);
    corner(size.width - inset, size.height - inset, -1, -1);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}
